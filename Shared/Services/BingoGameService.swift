import Foundation
import SwiftData

enum BingoGameService {

    // MARK: - CRUD

    // New Playlist-based create (post-merge)
    static func create(
        name: String,
        playlist: Playlist,
        in context: ModelContext
    ) -> BingoGame {
        let gameName = name.isEmpty
            ? "\(playlist.name) - \(Date().formatted(date: .abbreviated, time: .shortened))"
            : name

        let game = BingoGame(
            name: gameName,
            playlistUUID: playlist.uuid,
            playlistName: playlist.name,
            songKeys: playlist.songKeys,
            cardsData: playlist.cardsData,
            numberOfCards: playlist.numberOfCards,
            hasFreeSpace: playlist.hasFreeSpace,
            shuffledSongKeys: playlist.songKeys.shuffled()
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
        guard game.currentIndex < game.shuffledSongKeys.count - 1 else { return }
        game.currentIndex += 1
        game.highestPlayedIndex = max(game.highestPlayedIndex, game.currentIndex)
        try? context.save()
    }

    static func goToPreviousSong(_ game: BingoGame, in context: ModelContext) {
        guard game.currentIndex >= 0 else { return }
        game.highestPlayedIndex = max(game.highestPlayedIndex, game.currentIndex)
        game.currentIndex -= 1
        try? context.save()
    }

    static func recordCurrentProgress(_ game: BingoGame, in context: ModelContext) {
        guard game.currentIndex > game.highestPlayedIndex else { return }
        game.highestPlayedIndex = game.currentIndex
        try? context.save()
    }

    static func updateShuffledOrder(_ game: BingoGame, newOrder: [String], in context: ModelContext) {
        game.shuffledSongKeys = newOrder
        try? context.save()
    }

    static func reshuffleRemainingSongs(
        _ game: BingoGame,
        includePreviouslyPlayed: Bool,
        in context: ModelContext
    ) {
        guard game.shuffledSongKeys.count > 1 else { return }

        let protectedIndex = includePreviouslyPlayed
            ? game.currentIndex
            : max(game.currentIndex, game.highestPlayedIndex)
        let boundary = min(max(protectedIndex + 1, 0), game.shuffledSongKeys.count)
        guard boundary < game.shuffledSongKeys.count else { return }

        let locked = Array(game.shuffledSongKeys.prefix(boundary))
        let shuffled = Array(game.shuffledSongKeys.suffix(from: boundary)).shuffled()
        game.shuffledSongKeys = locked + shuffled
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
        songKeys: [String],
        playedSongURLs: Set<String>,
        hasFreeSpace: Bool
    ) -> [[CellState]] {
        var matrix: [[CellState]] = card.grid.map { row in
            row.map { value in
                if value == 0 {
                    return .played // free space always counts as played
                }
                guard value > 0, value <= songKeys.count else { return .unplayed }
                let url = songKeys[value - 1]
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
        songKeys: [String],
        playedSongURLs: Set<String>,
        hasFreeSpace: Bool
    ) -> (hitsCount: Int, bingoCount: Int) {
        let scored = scoreCard(
            card: card,
            songKeys: songKeys,
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
        songKeys: [String],
        shuffledSongs: [String],
        hasFreeSpace: Bool
    ) -> Int? {
        var played = Set<String>()
        for round in 1...shuffledSongs.count {
            played.insert(shuffledSongs[round - 1])
            let scored = scoreCard(
                card: card,
                songKeys: songKeys,
                playedSongURLs: played,
                hasFreeSpace: hasFreeSpace
            )
            // `scoreCard` marks every cell of a completed line, so a single
            // `.bingo` cell anywhere means a line landed. Testing for a fully
            // `.bingo` matrix row instead would only ever catch horizontal
            // bingos and miss every column and diagonal.
            let hasBingo = scored.contains { row in row.contains(.bingo) }
            if hasBingo { return round }
        }
        return nil
    }
}
