import SwiftUI
import SwiftData

enum GameTab: String, CaseIterable {
    case songs = "Songs"
    case boards = "Boards"
}

struct BingoGameView: View {
    var songs: [Song]
    @ObservedObject var audioPlayer: AudioPlayerService

    @Query(sort: \BingoSet.creationDate) private var bingoSets: [BingoSet]

    @State private var selectedBingoSetID: PersistentIdentifier?
    @State private var isGameActive = false
    @State private var shuffledSongs: [String] = []
    @State private var currentIndex: Int = -1
    @State private var activeTab: GameTab = .songs

    private var selectedBingoSet: BingoSet? {
        bingoSets.first { $0.persistentModelID == selectedBingoSetID }
    }

    private var songLookup: [String: Song] {
        var lookup: [String: Song] = [:]
        for song in songs {
            lookup[song.id.absoluteString] = song
        }
        return lookup
    }

    var body: some View {
        Group {
            if isGameActive, let bingoSet = selectedBingoSet {
                activeGameView(bingoSet: bingoSet)
            } else {
                setupView
            }
        }
        .navigationTitle("Bingo Games")
    }

    // MARK: - Setup Mode

    private var setupView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Start a Bingo Game")
                .font(.title2)
                .fontWeight(.semibold)

            if bingoSets.isEmpty {
                Text("Create a bingo set first to start a game.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Bingo Set", selection: $selectedBingoSetID) {
                    Text("Select a bingo set...")
                        .tag(nil as PersistentIdentifier?)
                    ForEach(bingoSets) { bingoSet in
                        Text("\(bingoSet.name) (\(bingoSet.songCount) songs, \(bingoSet.numberOfCards) cards)")
                            .tag(bingoSet.persistentModelID as PersistentIdentifier?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 400)

                Button("Start Game") {
                    startGame()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedBingoSetID == nil)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Active Game

    private func activeGameView(bingoSet: BingoSet) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bingoSet.name)
                        .font(.headline)
                    if currentIndex >= 0 {
                        Text("Song \(currentIndex + 1) of \(shuffledSongs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No songs played yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Navigation controls
                HStack(spacing: 12) {
                    Button {
                        previousSong()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(currentIndex < 0)
                    .help("Previous Song")

                    Button {
                        nextSong()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(currentIndex >= shuffledSongs.count - 1)
                    .help("Next Song")

                    Divider()
                        .frame(height: 20)

                    Button("End Game", role: .destructive) {
                        endGame()
                    }
                    .help("End Game")
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
                    shuffledSongs: $shuffledSongs,
                    currentIndex: currentIndex,
                    songLookup: songLookup
                )
            case .boards:
                BingoGameBoardsView(
                    bingoSet: bingoSet,
                    shuffledSongs: shuffledSongs,
                    currentIndex: currentIndex,
                    songLookup: songLookup
                )
            }
        }
    }

    // MARK: - Actions

    private func startGame() {
        guard let bingoSet = selectedBingoSet else { return }
        shuffledSongs = bingoSet.songURLStrings.shuffled()
        currentIndex = -1
        activeTab = .songs
        isGameActive = true
    }

    private func nextSong() {
        guard currentIndex < shuffledSongs.count - 1 else { return }
        currentIndex += 1
        playSongAtCurrentIndex()
    }

    private func previousSong() {
        guard currentIndex >= 0 else { return }
        currentIndex -= 1
        if currentIndex >= 0 {
            playSongAtCurrentIndex()
        } else {
            audioPlayer.stop()
        }
    }

    private func playSongAtCurrentIndex() {
        guard currentIndex >= 0, currentIndex < shuffledSongs.count else { return }
        let urlString = shuffledSongs[currentIndex]
        if let song = songLookup[urlString] {
            audioPlayer.play(song)
        }
    }

    private func endGame() {
        audioPlayer.stop()
        isGameActive = false
        shuffledSongs = []
        currentIndex = -1
        activeTab = .songs
    }
}
