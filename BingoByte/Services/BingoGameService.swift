import Foundation
import SwiftData

enum BingoGameService {

    // MARK: - CRUD

    static func create(
        name: String,
        bingoSet: BingoSet,
        in context: ModelContext
    ) -> BingoGame {
        let gameName = name.isEmpty
            ? "\(bingoSet.name) - \(Date().formatted(date: .abbreviated, time: .shortened))"
            : name

        let game = BingoGame(
            name: gameName,
            bingoSetName: bingoSet.name,
            songURLStrings: bingoSet.songURLStrings,
            cardsData: bingoSet.cardsData,
            numberOfCards: bingoSet.numberOfCards,
            hasFreeSpace: bingoSet.hasFreeSpace,
            shuffledSongURLStrings: bingoSet.songURLStrings.shuffled()
        )
        context.insert(game)
        try? context.save()
        return game
    }

    static func delete(_ game: BingoGame, in context: ModelContext) {
        context.delete(game)
        try? context.save()
    }

    static func advanceToNextSong(_ game: BingoGame, in context: ModelContext) {
        guard game.currentIndex < game.shuffledSongURLStrings.count - 1 else { return }
        game.currentIndex += 1
        try? context.save()
    }

    static func goToPreviousSong(_ game: BingoGame, in context: ModelContext) {
        guard game.currentIndex >= 0 else { return }
        game.currentIndex -= 1
        try? context.save()
    }

    static func updateShuffledOrder(_ game: BingoGame, newOrder: [String], in context: ModelContext) {
        game.shuffledSongURLStrings = newOrder
        try? context.save()
    }

    static func endGame(_ game: BingoGame, in context: ModelContext) {
        game.isCompleted = true
        game.completionDate = Date()
        try? context.save()
    }

    // MARK: - Scoring
    enum CellState {
        case unplayed
        case played
        case bingo
    }

    static func playedSongURLs(shuffledSongs: [String], currentIndex: Int) -> Set<String> {
        guard currentIndex >= 0, currentIndex < shuffledSongs.count else { return [] }
        return Set(shuffledSongs[0...currentIndex])
    }

    static func scoreCard(
        card: BingoCard,
        songURLStrings: [String],
        playedSongURLs: Set<String>,
        hasFreeSpace: Bool
    ) -> [[CellState]] {
        var matrix: [[CellState]] = card.grid.map { row in
            row.map { value in
                if value == 0 {
                    return .played // free space always counts as played
                }
                guard value > 0, value <= songURLStrings.count else { return .unplayed }
                let url = songURLStrings[value - 1]
                return playedSongURLs.contains(url) ? .played : .unplayed
            }
        }

        // Row scan
        for r in 0..<5 {
            if matrix[r].allSatisfy({ $0 != .unplayed }) {
                for c in 0..<5 { matrix[r][c] = .bingo }
            }
        }

        // Column scan
        for c in 0..<5 {
            if (0..<5).allSatisfy({ matrix[$0][c] != .unplayed }) {
                for r in 0..<5 { matrix[r][c] = .bingo }
            }
        }

        // Diagonal scan (top-left to bottom-right)
        if (0..<5).allSatisfy({ matrix[$0][$0] != .unplayed }) {
            for i in 0..<5 { matrix[i][i] = .bingo }
        }

        // Diagonal scan (top-right to bottom-left)
        if (0..<5).allSatisfy({ matrix[$0][4 - $0] != .unplayed }) {
            for i in 0..<5 { matrix[i][4 - i] = .bingo }
        }

        return matrix
    }

    // MARK: - Analytics

    struct CardStats: Identifiable {
        let id: Int               // card.id
        let hitsCount: Int        // played/bingo cells excluding free space
        let bingoCount: Int       // number of completed lines
        let firstBingoRound: Int? // 1-based round where first bingo occurs

        /// Sort-friendly value: nil maps to Int.max so nil sorts last in ascending order.
        var firstBingoRoundSort: Int { firstBingoRound ?? Int.max }
    }

    static func cardStats(
        card: BingoCard,
        songURLStrings: [String],
        playedSongURLs: Set<String>,
        hasFreeSpace: Bool
    ) -> (hitsCount: Int, bingoCount: Int) {
        let scored = scoreCard(
            card: card,
            songURLStrings: songURLStrings,
            playedSongURLs: playedSongURLs,
            hasFreeSpace: hasFreeSpace
        )

        // Count hits excluding free space (value == 0)
        var hits = 0
        for r in 0..<5 {
            for c in 0..<5 {
                if card.grid[r][c] != 0 && scored[r][c] != .unplayed {
                    hits += 1
                }
            }
        }

        // Count completed lines (5 rows + 5 cols + 2 diags)
        var bingos = 0
        for r in 0..<5 {
            if scored[r].allSatisfy({ $0 == .bingo }) { bingos += 1 }
        }
        for c in 0..<5 {
            if (0..<5).allSatisfy({ scored[$0][c] == .bingo }) { bingos += 1 }
        }
        if (0..<5).allSatisfy({ scored[$0][$0] == .bingo }) { bingos += 1 }
        if (0..<5).allSatisfy({ scored[$0][4 - $0] == .bingo }) { bingos += 1 }

        return (hits, bingos)
    }

    static func firstBingoRound(
        card: BingoCard,
        songURLStrings: [String],
        shuffledSongs: [String],
        hasFreeSpace: Bool
    ) -> Int? {
        var played = Set<String>()
        for round in 1...shuffledSongs.count {
            played.insert(shuffledSongs[round - 1])
            let scored = scoreCard(
                card: card,
                songURLStrings: songURLStrings,
                playedSongURLs: played,
                hasFreeSpace: hasFreeSpace
            )
            // Check if any line is a bingo
            let hasBingo = scored.contains { row in row.allSatisfy({ $0 == .bingo }) }
            if hasBingo { return round }
        }
        return nil
    }
}
