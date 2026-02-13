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
    var onBack: () -> Void

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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    audioPlayer.stop()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Games")
                    }
                }
            }
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
            audioPlayer.play(song)
        }
    }

    private func endGame() {
        audioPlayer.stop()
        BingoGameService.endGame(bingoGame, in: modelContext)
    }
}
