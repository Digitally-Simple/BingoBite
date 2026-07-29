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

        return HStack(spacing: 16) {
            Text("#\(stat.id)")
                .font(.headline)
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(stat.hitsCount), total: 24)
                    .tint(stat.bingoCount > 0 ? .green : .accentColor)
                Text("\(stat.hitsCount) of 24 squares")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if stat.bingoCount > 0 {
                Label("\(stat.bingoCount)", systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 5) {
                if let round = stat.firstBingoRound {
                    Text("Round \(round)")
                        .monospacedDigit()
                    if alreadyHit {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("No bingo")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
