import Foundation
import SwiftData

@Model
final class SongMetadataOverride {
    /// Stable song key — see `SongKey`. Defaulted so a future schema change
    /// doesn't fail migration on a mandatory attribute with no value.
    @Attribute(.unique) var songKey: String = ""
    var title: String?
    var artist: String?
    var album: String?
    @Attribute(.externalStorage) var artworkData: Data?
    var genre: String?
    var year: String?
    var comments: String?

    init(
        songKey: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artworkData: Data? = nil,
        genre: String? = nil,
        year: String? = nil,
        comments: String? = nil
    ) {
        self.songKey = songKey
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.genre = genre
        self.year = year
        self.comments = comments
    }
}
