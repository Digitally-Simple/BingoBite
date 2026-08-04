import Foundation

/// The handoff format Music Downloader writes into a library or export folder.
///
/// Mirror of `LibraryManifest.swift` in the Music Downloader project. The
/// snake_case keys are the contract between the two apps.
///
/// Treated as a **hint layer, never as truth**: it makes uid→file resolution
/// cheap and lets playlists be created without typing, but `LibraryIndexService`
/// always reconciles against what's actually on disk, and disk wins.
struct LibraryManifest: Codable, Sendable {
    static let currentVersion = 1
    static let fileName = "bingobite-library.json"

    var manifestVersion: Int = LibraryManifest.currentVersion
    var generatedAt: Date
    var generator: String
    var libraryName: String?
    /// Songs whose files are in *this* folder. For an incremental export that's
    /// the delta, not the whole library.
    var songs: [ManifestSong]
    var playlists: [PlaylistDefinition]

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case generatedAt = "generated_at"
        case generator
        case libraryName = "library_name"
        case songs
        case playlists
    }

    struct ManifestSong: Codable, Sendable, Identifiable {
        var uid: String
        var file: String
        var name: String
        var artist: String
        var album: String?
        var durationSeconds: Double?
        var year: String?
        var releaseDate: String?
        var genre: String?
        var sourceVideoID: String?
        var geniusURL: String?
        var geniusID: Int?
        var fileSize: Int64?

        var id: String { uid }

        enum CodingKeys: String, CodingKey {
            case uid, file, name, artist, album
            case durationSeconds = "duration_seconds"
            case year
            case releaseDate = "release_date"
            case genre
            case sourceVideoID = "source_video_id"
            case geniusURL = "genius_url"
            case geniusID = "genius_id"
            case fileSize = "file_size"
        }

        /// The key a playlist would store for this song.
        var stableKey: String {
            SongKey.make(uid: uid, relativePath: file, fileName: file)
        }
    }

    /// A playlist described by song UIDs, so it survives renames and can
    /// reference songs delivered in an earlier export.
    struct PlaylistDefinition: Codable, Sendable, Identifiable {
        var uuid: String
        var name: String
        var description: String?
        /// Ordered — card grids index into this positionally.
        var songUIDs: [String]

        var id: String { uuid }

        enum CodingKeys: String, CodingKey {
            case uuid, name, description
            case songUIDs = "song_uids"
        }
    }

    var isReadable: Bool { manifestVersion <= LibraryManifest.currentVersion }

    /// Reads the manifest at the root of `folder`. Returns nil when absent,
    /// malformed, or written by a newer version of Music Downloader.
    static func read(from folder: URL) -> LibraryManifest? {
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(LibraryManifest.self, from: data),
              manifest.isReadable
        else { return nil }
        return manifest
    }
}
