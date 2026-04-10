import Foundation
import SwiftData

@Model
final class Playlist {
    var uuid: String = ""
    var name: String = ""
    var descriptionText: String = ""
    var creationDate: Date = Date()
    var folderPath: String = ""
    var bookmarkData: Data = Data()
    var songURLStrings: [String] = []
    var numberOfCards: Int = 0
    var hasFreeSpace: Bool = true
    var cardsData: Data = Data()
    var coverArtData: Data? = nil

    var songCount: Int {
        songURLStrings.count
    }

    init(
        uuid: String = UUID().uuidString,
        name: String,
        descriptionText: String = "",
        folderPath: String,
        bookmarkData: Data,
        songURLStrings: [String],
        numberOfCards: Int,
        hasFreeSpace: Bool,
        cardsData: Data,
        coverArtData: Data? = nil,
        creationDate: Date = Date()
    ) {
        self.uuid = uuid
        self.name = name
        self.descriptionText = descriptionText
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.songURLStrings = songURLStrings
        self.numberOfCards = numberOfCards
        self.hasFreeSpace = hasFreeSpace
        self.cardsData = cardsData
        self.coverArtData = coverArtData
        self.creationDate = creationDate
    }
}
