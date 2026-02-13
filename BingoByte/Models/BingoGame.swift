import Foundation
import SwiftData

@Model
final class BingoGame {
    var name: String = ""
    var creationDate: Date = Date()
    var bingoSetName: String = ""
    var songURLStrings: [String] = []
    var cardsData: Data = Data()
    var numberOfCards: Int = 0
    var hasFreeSpace: Bool = true
    var shuffledSongURLStrings: [String] = []
    var currentIndex: Int = -1
    var isCompleted: Bool = false
    var completionDate: Date? = nil

    var songCount: Int {
        songURLStrings.count
    }

    var progress: String {
        if currentIndex < 0 {
            return "0 / \(shuffledSongURLStrings.count)"
        }
        return "\(currentIndex + 1) / \(shuffledSongURLStrings.count)"
    }

    init(
        name: String,
        bingoSetName: String,
        songURLStrings: [String],
        cardsData: Data,
        numberOfCards: Int,
        hasFreeSpace: Bool,
        shuffledSongURLStrings: [String]
    ) {
        self.name = name
        self.creationDate = Date()
        self.bingoSetName = bingoSetName
        self.songURLStrings = songURLStrings
        self.cardsData = cardsData
        self.numberOfCards = numberOfCards
        self.hasFreeSpace = hasFreeSpace
        self.shuffledSongURLStrings = shuffledSongURLStrings
        self.currentIndex = -1
        self.isCompleted = false
        self.completionDate = nil
    }
}
