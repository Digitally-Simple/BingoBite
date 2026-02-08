import Foundation
import SwiftData

@Model
final class Playlist {
    var uuid: String = ""
    var name: String
    var descriptionText: String
    var songURLStrings: [String]
    var creationDate: Date

    var songCount: Int {
        songURLStrings.count
    }

    init(name: String = "New Playlist", descriptionText: String = "", songURLStrings: [String] = [], creationDate: Date = Date()) {
        self.uuid = UUID().uuidString
        self.name = name
        self.descriptionText = descriptionText
        self.songURLStrings = songURLStrings
        self.creationDate = creationDate
    }
}
