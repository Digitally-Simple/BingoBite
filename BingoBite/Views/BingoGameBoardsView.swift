import SwiftUI

struct BingoGameBoardsView: View {
    var bingoGame: BingoGame
    var songLookup: [String: Song]

    private enum BoardViewMode: String, CaseIterable {
        case grid = "Grid"
        case table = "Table"
    }

    @State private var viewMode: BoardViewMode = .grid

    private var cards: [BingoCard] {
        let grids = CardGenerator.decode(from: bingoGame.cardsData)
        return grids.enumerated().map { index, grid in
            BingoCard(id: index + 1, grid: grid)
        }
    }

    private var playedURLs: Set<String> {
        BingoGameService.playedSongURLs(
            shuffledSongs: bingoGame.shuffledSongURLStrings,
            currentIndex: bingoGame.currentIndex
        )
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if bingoGame.currentIndex < 0 {
                ContentUnavailableView(
                    "No Songs Played",
                    systemImage: "forward.circle",
                    description: Text("Press Next to start playing songs and see the boards update.")
                )
                .padding(.top, 40)
                .frame(maxHeight: .infinity)
            } else {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(BoardViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch viewMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(cards) { card in
                                let scored = BingoGameService.scoreCard(
                                    card: card,
                                    songURLStrings: bingoGame.songURLStrings,
                                    playedSongURLs: playedURLs,
                                    hasFreeSpace: bingoGame.hasFreeSpace
                                )
                                BingoGameCardView(
                                    card: card,
                                    scoredMatrix: scored,
                                    songURLStrings: bingoGame.songURLStrings,
                                    shuffledSongs: bingoGame.shuffledSongURLStrings,
                                    currentIndex: bingoGame.currentIndex,
                                    songLookup: songLookup
                                )
                            }
                        }
                        .padding()
                    }
                case .table:
                    BingoGameTableView(
                        bingoGame: bingoGame
                    )
                }
            }
        }
    }
}
