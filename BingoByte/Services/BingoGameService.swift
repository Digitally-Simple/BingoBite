import Foundation

enum BingoGameService {
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
}
