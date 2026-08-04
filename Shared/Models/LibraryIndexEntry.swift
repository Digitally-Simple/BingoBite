import Foundation
import SwiftData

/// A cached scan result for one file in the master library.
///
/// Exists so opening the Songs tab doesn't re-read tags for every file. Reading
/// tags means spawning ffmpeg per file on macOS, or parsing the container on
/// iOS — fine for a 30-song folder, minutes for a thousand-song library. On a
/// warm open the sweep only stats each file and compares `contentStamp`.
///
/// No `@Attribute(.unique)` on anything: `uid` is empty for music that didn't
/// come from Music Downloader, and a unique constraint over many empty values
/// is a crash waiting to happen. Uniqueness is enforced in
/// `LibraryIndexService` instead.
@Model
final class LibraryIndexEntry {
    /// Path relative to the library root. The primary match key.
    var relativePath: String = ""
    /// `SONG_UID` from the file's tags, empty when it has none.
    var uid: String = ""
    var fileName: String = ""

    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var genre: String = ""
    var year: String = ""
    var duration: Double = 0
    var fileSize: Int64 = 0
    var geniusID: Int = 0

    /// `"<fileSize>-<mtimeEpoch>"`. Equal means the file is byte-identical as
    /// far as we care, so the cached row is reused and no tags are re-read.
    /// This comparison is the entire reason the index is fast.
    var contentStamp: String = ""

    /// Downscaled cover art for list rows. Full artwork is loaded on demand for
    /// the one song being inspected — storing it for every song would put
    /// hundreds of megabytes in the store.
    @Attribute(.externalStorage) var thumbnailData: Data?

    /// True when the file wasn't seen in the last sweep. The row is kept rather
    /// than deleted so playlists can show what's gone and offer a replacement,
    /// and so a temporarily unavailable volume doesn't wipe the index.
    var isMissing: Bool = false

    var addedAt: Date = Date()
    var lastSeenAt: Date = Date()

    init(
        relativePath: String,
        uid: String = "",
        fileName: String = "",
        title: String = "",
        artist: String = "",
        album: String = "",
        genre: String = "",
        year: String = "",
        duration: Double = 0,
        fileSize: Int64 = 0,
        geniusID: Int = 0,
        contentStamp: String = "",
        thumbnailData: Data? = nil,
        isMissing: Bool = false,
        addedAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.relativePath = relativePath
        self.uid = uid
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.duration = duration
        self.fileSize = fileSize
        self.geniusID = geniusID
        self.contentStamp = contentStamp
        self.thumbnailData = thumbnailData
        self.isMissing = isMissing
        self.addedAt = addedAt
        self.lastSeenAt = lastSeenAt
    }

    /// The key a playlist stores for this song.
    var stableKey: String {
        SongKey.make(
            uid: uid.isEmpty ? nil : uid,
            relativePath: relativePath,
            fileName: fileName
        )
    }

    var displayTitle: String { title.isEmpty ? fileName : title }
    var displayArtist: String { artist.isEmpty ? "Unknown Artist" : artist }
    var displayAlbum: String { album.isEmpty ? "Unknown Album" : album }

    /// Rebuilds a `Song` from the cached row, without touching the disk.
    ///
    /// Carries the thumbnail rather than full artwork — views that need the
    /// real thing load it lazily for the single song being shown.
    func makeSong(libraryRoot: URL) -> Song {
        Song(
            id: libraryRoot.appendingPathComponent(relativePath),
            fileName: fileName,
            fileSize: fileSize,
            duration: duration > 0 ? duration : nil,
            artist: artist.isEmpty ? nil : artist,
            title: title.isEmpty ? nil : title,
            album: album.isEmpty ? nil : album,
            artworkData: thumbnailData,
            uid: uid.isEmpty ? nil : uid,
            relativePath: relativePath,
            geniusID: geniusID == 0 ? nil : geniusID,
            genre: genre.isEmpty ? nil : genre,
            year: year.isEmpty ? nil : year
        )
    }
}
