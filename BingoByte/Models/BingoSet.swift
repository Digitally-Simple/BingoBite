import Foundation
import SwiftData

@Model
final class BingoSet {
    var name: String
    var playlistUUID: String
    var playlistName: String
    var songURLStrings: [String]
    var numberOfCards: Int
    var hasFreeSpace: Bool
    var cardsData: Data
    var creationDate: Date

    var songCount: Int {
        songURLStrings.count
    }

    init(
        name: String,
        playlistUUID: String,
        playlistName: String,
        songURLStrings: [String],
        numberOfCards: Int,
        hasFreeSpace: Bool,
        cardsData: Data,
        creationDate: Date = Date()
    ) {
        self.name = name
        self.playlistUUID = playlistUUID
        self.playlistName = playlistName
        self.songURLStrings = songURLStrings
        self.numberOfCards = numberOfCards
        self.hasFreeSpace = hasFreeSpace
        self.cardsData = cardsData
        self.creationDate = creationDate
    }
}
