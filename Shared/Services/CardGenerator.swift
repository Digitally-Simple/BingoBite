import Foundation

enum CardGenerator {
    static func generate(numberOfCards: Int, numberOfSongs: Int, hasFreeSpace: Bool) -> [[[Int]]] {
        let cellsNeeded = hasFreeSpace ? 24 : 25
        guard numberOfSongs >= cellsNeeded else { return [] }

        var cards: [[[Int]]] = []
        for _ in 0..<numberOfCards {
            var indices = Array(1...numberOfSongs)
            // Fisher-Yates shuffle
            for i in stride(from: indices.count - 1, through: 1, by: -1) {
                let j = Int.random(in: 0...i)
                indices.swapAt(i, j)
            }
            let selected = Array(indices.prefix(cellsNeeded))

            var grid: [[Int]] = []
            var idx = 0
            for row in 0..<5 {
                var rowData: [Int] = []
                for col in 0..<5 {
                    if hasFreeSpace && row == 2 && col == 2 {
                        rowData.append(0)
                    } else {
                        rowData.append(selected[idx])
                        idx += 1
                    }
                }
                grid.append(rowData)
            }
            cards.append(grid)
        }
        return cards
    }

    static func encode(_ cards: [[[Int]]]) -> Data {
        (try? JSONEncoder().encode(cards)) ?? Data()
    }

    static func decode(from data: Data) -> [[[Int]]] {
        (try? JSONDecoder().decode([[[Int]]].self, from: data)) ?? []
    }
}
