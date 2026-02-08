import SwiftUI

struct BingoGameBoardsView: View {
    var bingoSet: BingoSet
    var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: [String: Song]

    private var cards: [BingoCard] {
        BingoSetService.bingoCards(from: bingoSet)
    }

    private var playedURLs: Set<String> {
        BingoGameService.playedSongURLs(shuffledSongs: shuffledSongs, currentIndex: currentIndex)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if currentIndex < 0 {
                ContentUnavailableView(
                    "No Songs Played",
                    systemImage: "forward.circle",
                    description: Text("Press Next to start playing songs and see the boards update.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(cards) { card in
                        let scored = BingoGameService.scoreCard(
                            card: card,
                            songURLStrings: bingoSet.songURLStrings,
                            playedSongURLs: playedURLs,
                            hasFreeSpace: bingoSet.hasFreeSpace
                        )
                        BingoGameCardView(
                            card: card,
                            scoredMatrix: scored,
                            songURLStrings: bingoSet.songURLStrings,
                            shuffledSongs: shuffledSongs,
                            currentIndex: currentIndex,
                            songLookup: songLookup
                        )
                    }
                }
                .padding()
            }
        }
    }
}
