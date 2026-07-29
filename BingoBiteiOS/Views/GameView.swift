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
    var onInspectSong: (Song) -> Void

    @State private var activeTab: GameTab = .songs
    @State private var songs: [Song] = []
    @State private var accessedURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEndConfirmation = false
    /// Scoring every board is cheap but not free, so the count is recomputed
    /// when the game moves rather than on every re-render.
    @State private var bingoCount = 0

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
                VStack(spacing: 0) {
                    ScoreboardBanner(
                        game: game,
                        song: currentSong,
                        isPlaying: audioPlayer.isPlaying,
                        bingoCount: bingoCount
                    )
                    tabContent
                }
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !game.isCompleted {
                    Button("End Game", systemImage: "flag.checkered", role: .destructive) {
                        showEndConfirmation = true
                    }
                }
            }
        }
        .modifier(
            DeckOverlay(isVisible: !isLoading && loadError == nil) {
                gameDeck
            }
        )
        .task(id: game.playlistUUID) { await loadSongs() }
        .onAppear { updateSkipHandlers() }
        .onDisappear {
            audioPlayer.clearSkipHandlers()
            BingoLiveActivityCommandBus.shared.setHandler(nil)
            BingoLiveActivityController.stop()
            releaseAccess()
        }
        .onChange(of: game.currentIndex) {
            updateSkipHandlers()
            syncLiveActivity()
        }
        .onChange(of: audioPlayer.isPlaying) { syncLiveActivity() }
        .onChange(of: game.isCompleted) {
            if game.isCompleted {
                let state = liveActivityState
                bingoCount = state.bingoCount
                BingoLiveActivityController.finish(state: state)
            }
        }
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

    private var gameDeck: some View {
        GameDeck(
            roundLabel: roundLabel,
            song: currentSong,
            isCompleted: game.isCompleted,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isPlaying: audioPlayer.isPlaying,
            canPlayPause: game.currentIndex >= 0,
            progress: audioPlayer.progress,
            activeTab: $activeTab,
            onPrevious: previousSong,
            onPlayPause: playPause,
            onNext: nextSong,
            onInspect: { if let currentSong { onInspectSong(currentSong) } }
        )
    }

    private var roundLabel: String {
        if game.isCompleted { return "Completed" }
        if game.currentIndex < 0 { return "Ready" }
        return "Round \(game.currentIndex + 1) of \(game.shuffledSongURLStrings.count)"
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
        if loadError == nil {
            updateSkipHandlers()
            syncLiveActivity()
        }
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
            BingoLiveActivityCommandBus.shared.setHandler(nil)
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

        // The Lock Screen buttons ride the same handlers, so a press from the
        // Live Activity moves the game exactly as the deck does — then pushes
        // the new state straight back to the card, because SwiftUI's `onChange`
        // can't be relied on while the app is backgrounded.
        BingoLiveActivityCommandBus.shared.setHandler { command in
            switch command {
            case .nextRound:
                player.skipForward()
            case .previousRound:
                player.skipBackward()
            case .togglePlayback:
                if player.currentSong != nil {
                    player.togglePlayPause()
                } else {
                    player.skipForward()
                }
            }

            let index = game.currentIndex
            let song = (index >= 0 && index < game.shuffledSongURLStrings.count)
                ? lookup.song(for: game.shuffledSongURLStrings[index])
                : nil
            BingoLiveActivityController.sync(
                game: game,
                state: BingoLiveActivityState.make(game: game, song: song, isPlaying: player.isPlaying)
            )
        }
    }

    // MARK: - Live Activity

    private var liveActivityState: BingoGameActivityAttributes.ContentState {
        BingoLiveActivityState.make(game: game, song: currentSong, isPlaying: audioPlayer.isPlaying)
    }

    /// One pass over the boards feeds both the on-screen scoreboard and the
    /// Lock Screen card — they're showing the same numbers, so they should be
    /// computed together.
    private func syncLiveActivity() {
        let state = liveActivityState
        bingoCount = state.bingoCount
        guard !isLoading, loadError == nil, !game.isCompleted else { return }
        BingoLiveActivityController.sync(game: game, state: state)
    }
}
