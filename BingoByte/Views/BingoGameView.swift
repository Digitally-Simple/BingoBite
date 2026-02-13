import SwiftUI
import SwiftData

enum GameTab: String, CaseIterable {
    case songs = "Songs"
    case boards = "Boards"
}

struct BingoGameView: View {
    @Environment(\.modelContext) private var modelContext
    var bingoGame: BingoGame
    var songs: [Song]
    @ObservedObject var audioPlayer: AudioPlayerService

    @State private var activeTab: GameTab = .songs

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

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bingoGame.name)
                        .font(.headline)
                    if bingoGame.isCompleted {
                        Text("Completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if bingoGame.currentIndex >= 0 {
                        Text("Song \(bingoGame.currentIndex + 1) of \(bingoGame.shuffledSongURLStrings.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No songs played yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !bingoGame.isCompleted {
                    HStack(spacing: 12) {
                        Button {
                            previousSong()
                        } label: {
                            Image(systemName: "backward.fill")
                        }
                        .disabled(bingoGame.currentIndex < 0)
                        .help("Previous Song")

                        Button {
                            playPause()
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(bingoGame.currentIndex < 0)
                        .help(audioPlayer.isPlaying ? "Pause" : "Play")

                        Button {
                            nextSong()
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                        .disabled(bingoGame.currentIndex >= bingoGame.shuffledSongURLStrings.count - 1)
                        .help("Next Song")

                        Divider()
                            .frame(height: 20)

                        Button("End Game", role: .destructive) {
                            endGame()
                        }
                        .help("End Game")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Sub-tab picker
            Picker("View", selection: $activeTab) {
                ForEach(GameTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
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
            }
        }
        .navigationTitle("Bingo Games")
        .onAppear {
            updateBingoSkipHandlers()
        }
        .onDisappear {
            audioPlayer.clearSkipHandlers()
        }
        .onChange(of: bingoGame.currentIndex) {
            updateBingoSkipHandlers()
        }
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
