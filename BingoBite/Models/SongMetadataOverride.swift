import Foundation
import SwiftData

@Model
final class SongMetadataOverride {
    @Attribute(.unique) var songURLString: String
    var title: String?
    var artist: String?
    var album: String?
    @Attribute(.externalStorage) var artworkData: Data?
    var genre: String?
    var year: String?
    var comments: String?

    init(
        songURLString: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artworkData: Data? = nil,
        genre: String? = nil,
        year: String? = nil,
        comments: String? = nil
    ) {
        self.songURLString = songURLString
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.genre = genre
        self.year = year
        self.comments = comments
    }
}
