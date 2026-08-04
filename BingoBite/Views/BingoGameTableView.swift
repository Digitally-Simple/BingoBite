import SwiftUI

struct BingoGameTableView: View {
    var bingoGame: BingoGame

    private var cards: [BingoCard] {
        let grids = CardGenerator.decode(from: bingoGame.cardsData)
        return grids.enumerated().map { index, grid in
            BingoCard(id: index + 1, grid: grid)
        }
    }

    private var playedURLs: Set<String> {
        BingoGameService.playedSongURLs(
            shuffledSongs: bingoGame.shuffledSongKeys,
            currentIndex: bingoGame.currentIndex
        )
    }

    private var stats: [BingoGameService.CardStats] {
        cards.map { card in
            let (hits, bingos) = BingoGameService.cardStats(
                card: card,
                songKeys: bingoGame.songKeys,
                playedSongURLs: playedURLs,
                hasFreeSpace: bingoGame.hasFreeSpace
            )
            let firstRound = BingoGameService.firstBingoRound(
                card: card,
                songKeys: bingoGame.songKeys,
                shuffledSongs: bingoGame.shuffledSongKeys,
                hasFreeSpace: bingoGame.hasFreeSpace
            )
            return BingoGameService.CardStats(
                id: card.id,
                hitsCount: hits,
                bingoCount: bingos,
                firstBingoRound: firstRound
            )
        }
    }

    @State private var sortOrder = [KeyPathComparator(\BingoGameService.CardStats.firstBingoRoundSort, order: .forward)]

    private var sortedStats: [BingoGameService.CardStats] {
        stats.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedStats, sortOrder: $sortOrder) {
            TableColumn("Card #", value: \.id) { stat in
                Text("#\(stat.id)")
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60, max: 80)

            TableColumn("Hits", value: \.hitsCount) { stat in
                Text("\(stat.hitsCount)")
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 50, max: 70)

            TableColumn("Bingos", value: \.bingoCount) { stat in
                if stat.bingoCount > 0 {
                    Label("\(stat.bingoCount)", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                } else {
                    Text("0")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .width(min: 50, ideal: 70, max: 90)

            TableColumn("First Bingo Round", value: \.firstBingoRoundSort) { stat in
                if let round = stat.firstBingoRound {
                    let alreadyHit = bingoGame.currentIndex >= 0 && round <= bingoGame.currentIndex + 1
                    HStack(spacing: 4) {
                        Text("Round \(round)")
                            .monospacedDigit()
                        if alreadyHit {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140, max: 180)
        }
    }
}
