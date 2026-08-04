import Foundation
import SwiftData

@Model
final class BingoGame {
    var name: String = ""
    var creationDate: Date = Date()
    var playlistUUID: String = ""
    var playlistName: String = ""
    var songKeys: [String] = []
    var cardsData: Data = Data()
    var numberOfCards: Int = 0
    var hasFreeSpace: Bool = true
    var shuffledSongKeys: [String] = []
    var currentIndex: Int = -1
    var highestPlayedIndex: Int = -1
    var isCompleted: Bool = false
    var completionDate: Date? = nil

    var songCount: Int {
        songKeys.count
    }

    var progress: String {
        if currentIndex < 0 {
            return "0 / \(shuffledSongKeys.count)"
        }
        return "\(currentIndex + 1) / \(shuffledSongKeys.count)"
    }

    init(
        name: String,
        playlistUUID: String,
        playlistName: String,
        songKeys: [String],
        cardsData: Data,
        numberOfCards: Int,
        hasFreeSpace: Bool,
        shuffledSongKeys: [String]
    ) {
        self.name = name
        self.creationDate = Date()
        self.playlistUUID = playlistUUID
        self.playlistName = playlistName
        self.songKeys = songKeys
        self.cardsData = cardsData
        self.numberOfCards = numberOfCards
        self.hasFreeSpace = hasFreeSpace
        self.shuffledSongKeys = shuffledSongKeys
        self.currentIndex = -1
        self.highestPlayedIndex = -1
        self.isCompleted = false
        self.completionDate = nil
    }
}
