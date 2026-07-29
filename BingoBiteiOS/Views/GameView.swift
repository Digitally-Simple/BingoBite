import SwiftUI
import SwiftData

enum GameTab: String, CaseIterable, Identifiable {
    case songs = "Play Order"
    case boards = "Boards"
    case info = "Now Playing"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .songs: "list.number"
        case .boards: "square.grid.3x3.fill"
        case .info: "info.circle.fill"
        }
    }
}

/// The live game screen: a glass transport deck pinned to the bottom, with the
/// play order, scored boards, and current-song details above it.
struct GameView: View {
    @Environment(\.modelContext) private var modelContext
    var game: BingoGame
    @ObservedObject var audioPlayer: AudioPlayerService

    @State private var activeTab: GameTab = .songs
    @State private var songs: [Song] = []
    @State private var accessedURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEndConfirmation = false

    private var songLookup: SongIndex { SongIndex(songs) }

    private var currentSong: Song? {
        guard game.currentIndex >= 0, game.currentIndex < game.shuffledSongURLStrings.count else { return nil }
        return songLookup.song(for: game.shuffledSongURLStrings[game.currentIndex])
    }

    private var canGoBack: Bool { game.currentIndex >= 0 }
    private var canGoForward: Bool { game.currentIndex < game.shuffledSongURLStrings.count - 1 }

    private var shuffledBinding: Binding<[String]> {
        Binding(
            get: { game.shuffledSongURLStrings },
            set: { BingoGameService.updateShuffledOrder(game, newOrder: $0, in: modelContext) }
        )
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading songs…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Source Folder Unavailable", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(loadError)
                    Text("The playlist this game came from may have been deleted, or its folder moved in Files.")
                }
            } else {
                tabContent
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $activeTab) {
                    ForEach(GameTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !game.isCompleted {
                    Button("End Game", systemImage: "flag.checkered", role: .destructive) {
                        showEndConfirmation = true
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading && loadError == nil {
                transportDeck
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .task(id: game.playlistUUID) { await loadSongs() }
        .onAppear { updateSkipHandlers() }
        .onDisappear {
            audioPlayer.clearSkipHandlers()
            releaseAccess()
        }
        .onChange(of: game.currentIndex) { updateSkipHandlers() }
        .confirmationDialog("End this game?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Game", role: .destructive) { endGame() }
        } message: {
            Text("The final boards stay available, but you won't be able to play more songs.")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .songs:
            GamePlayOrderView(
                shuffledSongs: shuffledBinding,
                currentIndex: game.currentIndex,
                songLookup: songLookup,
                isCompleted: game.isCompleted
            )
        case .boards:
            GameBoardsView(game: game, songLookup: songLookup)
        case .info:
            SongDetailPanel(song: currentSong, audioPlayer: audioPlayer, emptyMessage: "Press Next Song to start the game.")
        }
    }

    // MARK: - Transport deck

    private var transportDeck: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 18) {
                nowPlayingSummary

                Spacer(minLength: 12)

                if game.isCompleted {
                    Label("Game Complete", systemImage: "flag.checkered")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    controls
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassCard(corner: Glassware.panelCorner)
        }
        .frame(maxWidth: 900)
    }

    private var nowPlayingSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                ArtworkView(data: currentSong?.artworkData, corner: 12)
                if currentSong == nil {
                    Image(systemName: "questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(roundLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .monospacedDigit()

                Text(currentSong?.displayTitle ?? "No song played yet")
                    .font(.headline)
                    .lineLimit(1)

                Text(currentSong?.displayArtist ?? "Tap Next Song to reveal the first track")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var roundLabel: String {
        if game.isCompleted { return "Completed" }
        if game.currentIndex < 0 { return "Ready" }
        return "Round \(game.currentIndex + 1) of \(game.shuffledSongURLStrings.count)"
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Previous", systemImage: "backward.fill") { previousSong() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(!canGoBack)

            Button(
                audioPlayer.isPlaying ? "Pause" : "Play",
                systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill"
            ) { playPause() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(game.currentIndex < 0)

            Button("Next Song", systemImage: "forward.fill") { nextSong() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canGoForward)
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadSongs() async {
        isLoading = true
        loadError = nil
        releaseAccess()

        let uuid = game.playlistUUID
        guard !uuid.isEmpty else {
            loadError = "This game has no source playlist."
            isLoading = false
            return
        }

        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == uuid })
        guard let playlist = try? modelContext.fetch(descriptor).first else {
            loadError = "Source playlist not found."
            isLoading = false
            return
        }

        do {
            let (loaded, _, _, url) = try await PlaylistService.loadSongs(for: playlist, in: modelContext)
            songs = loaded
            accessedURL = url
            applyOverrides()
        } catch {
            loadError = error.localizedDescription
            songs = []
        }
        isLoading = false
    }

    private func applyOverrides() {
        let overrides = SongMetadataService.fetchAll(in: modelContext)
        for index in songs.indices {
            if let override = overrides[songs[index].id.absoluteString] {
                songs[index] = songs[index].applying(override: override)
            }
        }
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }

    // MARK: - Playback

    private func playPause() {
        if audioPlayer.currentSong != nil {
            audioPlayer.togglePlayPause()
        } else {
            playCurrentIndex()
        }
    }

    private func nextSong() {
        BingoGameService.advanceToNextSong(game, in: modelContext)
        playCurrentIndex()
    }

    private func previousSong() {
        BingoGameService.goToPreviousSong(game, in: modelContext)
        if game.currentIndex >= 0 {
            playCurrentIndex()
        } else {
            audioPlayer.stop()
        }
    }

    private func playCurrentIndex() {
        guard game.currentIndex >= 0, game.currentIndex < game.shuffledSongURLStrings.count else { return }
        guard let song = songLookup.song(for: game.shuffledSongURLStrings[game.currentIndex]) else { return }
        if let clip = SoundByteService.fetch(for: song, in: modelContext) {
            audioPlayer.play(song, from: clip.startTime)
        } else {
            audioPlayer.play(song)
        }
    }

    private func endGame() {
        audioPlayer.stop()
        audioPlayer.clearSkipHandlers()
        BingoGameService.endGame(game, in: modelContext)
    }

    /// Wires the lock-screen / Control Center skip buttons to the game order so
    /// the host can advance rounds without unlocking the iPad.
    private func updateSkipHandlers() {
        guard !game.isCompleted else {
            audioPlayer.clearSkipHandlers()
            return
        }

        let game = game
        let player = audioPlayer
        let context = modelContext
        let lookup = songLookup

        func play(at index: Int) {
            guard index >= 0, index < game.shuffledSongURLStrings.count else { return }
            guard let song = lookup.song(for: game.shuffledSongURLStrings[index]) else { return }
            if let clip = SoundByteService.fetch(for: song, in: context) {
                player.play(song, from: clip.startTime)
            } else {
                player.play(song)
            }
        }

        player.onSkipForward = canGoForward ? {
            BingoGameService.advanceToNextSong(game, in: context)
            play(at: game.currentIndex)
        } : nil

        player.onSkipBackward = canGoBack ? {
            BingoGameService.goToPreviousSong(game, in: context)
            if game.currentIndex >= 0 {
                play(at: game.currentIndex)
            } else {
                player.stop()
            }
        } : nil

        player.setSkipState(canForward: canGoForward, canBackward: canGoBack)
    }
}
