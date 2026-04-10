import SwiftUI
import SwiftData

enum GameTab: String, CaseIterable {
    case songs = "Songs"
    case boards = "Boards"
    case info = "Info"
}

struct BingoGameView: View {
    @Environment(\.modelContext) private var modelContext
    var bingoGame: BingoGame
    @ObservedObject var audioPlayer: AudioPlayerService

    @State private var activeTab: GameTab = .songs
    @State private var songs: [Song] = []
    @State private var accessedURL: URL?
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    private var songLookup: [String: Song] {
        var lookup: [String: Song] = [:]
        for song in songs {
            lookup[song.id.absoluteString] = song
        }
        return lookup
    }

    private var shuffledSongsBinding: Binding<[String]> {
        Binding(
            get: { bingoGame.shuffledSongURLStrings },
            set: { newValue in
                BingoGameService.updateShuffledOrder(bingoGame, newOrder: newValue, in: modelContext)
            }
        )
    }

    private var progressText: String {
        if bingoGame.isCompleted {
            return "Completed"
        } else if bingoGame.currentIndex >= 0 {
            return "Song \(bingoGame.currentIndex + 1) of \(bingoGame.shuffledSongURLStrings.count)"
        } else {
            return "No songs played yet"
        }
    }

    private var currentSong: Song? {
        guard bingoGame.currentIndex >= 0,
              bingoGame.currentIndex < bingoGame.shuffledSongURLStrings.count else { return nil }
        let urlString = bingoGame.shuffledSongURLStrings[bingoGame.currentIndex]
        return songLookup[urlString]
    }

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading songs…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Source Folder Unavailable")
                        .font(.headline)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("The playlist this game was created from may have been deleted, or its source folder moved.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                tabContent
            }
        }
        .navigationTitle(bingoGame.name)
        .navigationSubtitle(progressText)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $activeTab) {
                    ForEach(GameTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)
            }

            if !bingoGame.isCompleted {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        previousSong()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(bingoGame.currentIndex < 0)
                    .help("Previous Song")
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        playPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .disabled(bingoGame.currentIndex < 0)
                    .help(audioPlayer.isPlaying ? "Pause" : "Play")
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        nextSong()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(bingoGame.currentIndex >= bingoGame.shuffledSongURLStrings.count - 1)
                    .help("Next Song")
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button("End Game", role: .destructive) {
                        endGame()
                    }
                    .help("End Game")
                }
            }
        }
        .task(id: bingoGame.playlistUUID) {
            await loadSongs()
        }
        .onAppear {
            updateBingoSkipHandlers()
        }
        .onDisappear {
            audioPlayer.clearSkipHandlers()
            releaseAccess()
        }
        .onChange(of: bingoGame.currentIndex) {
            updateBingoSkipHandlers()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .songs:
            BingoGameSongListView(
                shuffledSongs: shuffledSongsBinding,
                currentIndex: bingoGame.currentIndex,
                songLookup: songLookup
            )
        case .boards:
            BingoGameBoardsView(
                bingoGame: bingoGame,
                songLookup: songLookup
            )
        case .info:
            BingoGameInfoView(song: currentSong, audioPlayer: audioPlayer)
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadSongs() async {
        isLoading = true
        loadError = nil
        releaseAccess()

        let uuid = bingoGame.playlistUUID
        guard !uuid.isEmpty else {
            loadError = "This game has no source playlist."
            isLoading = false
            return
        }

        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        guard let playlist = try? modelContext.fetch(descriptor).first else {
            loadError = "Source playlist not found."
            isLoading = false
            return
        }

        do {
            let (loaded, url) = try await PlaylistService.loadSongs(for: playlist)
            songs = loaded
            accessedURL = url
        } catch {
            loadError = error.localizedDescription
            songs = []
        }
        isLoading = false
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }

    // MARK: - Actions

    private func playPause() {
        if audioPlayer.currentSong != nil {
            audioPlayer.togglePlayPause()
        } else {
            playSongAtCurrentIndex()
        }
    }

    private func nextSong() {
        BingoGameService.advanceToNextSong(bingoGame, in: modelContext)
        playSongAtCurrentIndex()
    }

    private func previousSong() {
        BingoGameService.goToPreviousSong(bingoGame, in: modelContext)
        if bingoGame.currentIndex >= 0 {
            playSongAtCurrentIndex()
        } else {
            audioPlayer.stop()
        }
    }

    private func playSongAtCurrentIndex() {
        guard bingoGame.currentIndex >= 0,
              bingoGame.currentIndex < bingoGame.shuffledSongURLStrings.count else { return }
        let urlString = bingoGame.shuffledSongURLStrings[bingoGame.currentIndex]
        if let song = songLookup[urlString] {
            if let soundByte = SoundByteService.fetch(for: song, in: modelContext) {
                audioPlayer.play(song, from: soundByte.startTime)
            } else {
                audioPlayer.play(song)
            }
        }
    }

    private func endGame() {
        audioPlayer.stop()
        audioPlayer.clearSkipHandlers()
        BingoGameService.endGame(bingoGame, in: modelContext)
    }

    private func updateBingoSkipHandlers() {
        guard !bingoGame.isCompleted else {
            audioPlayer.clearSkipHandlers()
            return
        }

        let canBack = bingoGame.currentIndex >= 0
        let canForward = bingoGame.currentIndex < bingoGame.shuffledSongURLStrings.count - 1
        let game = bingoGame
        let player = audioPlayer
        let ctx = modelContext
        let lookup = songLookup

        player.onSkipForward = canForward ? {
            BingoGameService.advanceToNextSong(game, in: ctx)
            guard game.currentIndex >= 0,
                  game.currentIndex < game.shuffledSongURLStrings.count else { return }
            let urlString = game.shuffledSongURLStrings[game.currentIndex]
            if let song = lookup[urlString] {
                if let soundByte = SoundByteService.fetch(for: song, in: ctx) {
                    player.play(song, from: soundByte.startTime)
                } else {
                    player.play(song)
                }
            }
        } : nil

        player.onSkipBackward = canBack ? {
            BingoGameService.goToPreviousSong(game, in: ctx)
            if game.currentIndex >= 0 {
                guard game.currentIndex < game.shuffledSongURLStrings.count else { return }
                let urlString = game.shuffledSongURLStrings[game.currentIndex]
                if let song = lookup[urlString] {
                    if let soundByte = SoundByteService.fetch(for: song, in: ctx) {
                        player.play(song, from: soundByte.startTime)
                    } else {
                        player.play(song)
                    }
                }
            } else {
                player.stop()
            }
        } : nil

        player.setSkipState(canForward: canForward, canBackward: canBack)
    }
}
