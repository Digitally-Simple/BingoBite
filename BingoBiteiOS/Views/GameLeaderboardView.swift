import SwiftUI

/// Card standings — hits, completed lines, and which round each card first
/// hits bingo, so the host can see what's coming.
struct GameLeaderboardView: View {
    var game: BingoGame

    private enum SortField: String, CaseIterable, Identifiable {
        case firstBingo = "First Bingo"
        case hits = "Hits"
        case bingos = "Bingos"
        case number = "Card #"
        var id: String { rawValue }
    }

    @State private var sortField: SortField = .firstBingo

    private var cards: [BingoCard] {
        CardGenerator.decode(from: game.cardsData).enumerated().map { BingoCard(id: $0.offset + 1, grid: $0.element) }
    }

    private var stats: [BingoGameService.CardStats] {
        let played = BingoGameService.playedSongURLs(
            shuffledSongs: game.shuffledSongURLStrings,
            currentIndex: game.currentIndex
        )
        let raw = cards.map { card in
            let (hits, bingos) = BingoGameService.cardStats(
                card: card,
                songURLStrings: game.songURLStrings,
                playedSongURLs: played,
                hasFreeSpace: game.hasFreeSpace
            )
            return BingoGameService.CardStats(
                id: card.id,
                hitsCount: hits,
                bingoCount: bingos,
                firstBingoRound: BingoGameService.firstBingoRound(
                    card: card,
                    songURLStrings: game.songURLStrings,
                    shuffledSongs: game.shuffledSongURLStrings,
                    hasFreeSpace: game.hasFreeSpace
                )
            )
        }

        switch sortField {
        case .firstBingo: return raw.sorted { $0.firstBingoRoundSort < $1.firstBingoRoundSort }
        case .hits:       return raw.sorted { $0.hitsCount > $1.hitsCount }
        case .bingos:     return raw.sorted { $0.bingoCount > $1.bingoCount }
        case .number:     return raw.sorted { $0.id < $1.id }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Sort by", selection: $sortField) {
                ForEach(SortField.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                        row(stat)
                        if index < stats.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .glassCard(corner: Glassware.panelCorner)
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .padding(.top, 4)
    }

    private func row(_ stat: BingoGameService.CardStats) -> some View {
        let alreadyHit = stat.firstBingoRound.map { game.currentIndex >= 0 && $0 <= game.currentIndex + 1 } ?? false

        // A card that has already hit wears gold; one that will hit later stays
        // in the game's own colour so the two read as different kinds of news.
        let tint: Color = alreadyHit ? BingoActivityTheme.gold : BingoActivityTheme.live

        return HStack(spacing: 16) {
            Text("#\(stat.id)")
                .font(.headline)
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)

            MeterLane(
                title: "SQUARES MARKED",
                filled: stat.hitsCount,
                total: 24,
                tint: tint,
                isMuted: stat.hitsCount == 0,
                height: 7,
                labelColor: .secondary,
                trackColor: .primary.opacity(0.12)
            )

            Spacer(minLength: 8)

            Group {
                if stat.bingoCount > 0 {
                    BingoBadge(
                        bingoCount: stat.bingoCount,
                        label: stat.bingoCount == 1 ? "1 LINE" : "\(stat.bingoCount) LINES"
                    )
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 84, alignment: .trailing)

            HStack(spacing: 6) {
                if let round = stat.firstBingoRound {
                    if alreadyHit {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(BingoActivityTheme.gold)
                    }
                    RoundChip(
                        round: round,
                        size: 15,
                        tint: alreadyHit ? BingoActivityTheme.gold : .primary
                    )
                    CapsLabel(alreadyHit ? "HIT" : "TO COME", color: .secondary)
                } else {
                    CapsLabel("NO BINGO", color: .secondary.opacity(0.6))
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
