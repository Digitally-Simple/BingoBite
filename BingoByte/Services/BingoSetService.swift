import Foundation
import SwiftData

enum BingoSetService {
    static func fetchAll(in context: ModelContext) -> [BingoSet] {
        let descriptor = FetchDescriptor<BingoSet>(
            sortBy: [SortDescriptor(\.creationDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchBingoSets(forPlaylistUUID uuid: String, in context: ModelContext) -> [BingoSet] {
        let descriptor = FetchDescriptor<BingoSet>(
            predicate: #Predicate { $0.playlistUUID == uuid }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func isPlaylistLocked(_ playlist: Playlist, in context: ModelContext) -> Bool {
        !fetchBingoSets(forPlaylistUUID: playlist.uuid, in: context).isEmpty
    }

    static func create(
        name: String,
        playlist: Playlist,
        songs: [Song],
        numberOfCards: Int,
        hasFreeSpace: Bool,
        in context: ModelContext
    ) -> BingoSet {
        let songURLStrings = playlist.songURLStrings
        let cards = generateCards(
            numberOfCards: numberOfCards,
            numberOfSongs: songURLStrings.count,
            hasFreeSpace: hasFreeSpace
        )
        let cardsData = encodeCards(cards)

        let bingoSet = BingoSet(
            name: name,
            playlistUUID: playlist.uuid,
            playlistName: playlist.name,
            songURLStrings: songURLStrings,
            numberOfCards: numberOfCards,
            hasFreeSpace: hasFreeSpace,
            cardsData: cardsData
        )
        context.insert(bingoSet)
        try? context.save()
        return bingoSet
    }

    static func delete(_ bingoSet: BingoSet, in context: ModelContext) {
        context.delete(bingoSet)
        try? context.save()
    }

    // MARK: - Card Generation

    static func generateCards(numberOfCards: Int, numberOfSongs: Int, hasFreeSpace: Bool) -> [[[Int]]] {
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

    // MARK: - JSON Encoding/Decoding

    static func encodeCards(_ cards: [[[Int]]]) -> Data {
        (try? JSONEncoder().encode(cards)) ?? Data()
    }

    static func decodeCards(from data: Data) -> [[[Int]]] {
        (try? JSONDecoder().decode([[[Int]]].self, from: data)) ?? []
    }

    static func bingoCards(from bingoSet: BingoSet) -> [BingoCard] {
        let grids = decodeCards(from: bingoSet.cardsData)
        return grids.enumerated().map { index, grid in
            BingoCard(id: index + 1, grid: grid)
        }
    }
}
