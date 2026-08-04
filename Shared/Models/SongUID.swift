import Foundation

/// A stable identifier written into an audio file's tags by Music Downloader.
///
/// Mirror of `SongIdentity.swift` in the Music Downloader project. The key
/// names and value grammar are the contract between the two apps — keep them
/// in sync.
///
/// The UID is deterministic from the source video id, so re-downloading a file
/// that was deleted mints the same UID and any playlist referencing it relinks
/// itself with no user action.
enum SongUID {

    // MARK: - Tag keys

    static let uidKey = "SONG_UID"
    static let sourceVideoIDKey = "SOURCE_VIDEO_ID"
    static let geniusIDKey = "GENIUS_ID"

    static let youtubeNamespace = "ytdl"
    static let localNamespace = "mdl"

    // MARK: - Parsing

    struct Parsed: Equatable {
        let namespace: String
        let value: String

        var isYouTube: Bool { namespace == SongUID.youtubeNamespace }
        var videoID: String? { isYouTube ? value : nil }
    }

    static func parse(_ uid: String?) -> Parsed? {
        guard let uid else { return nil }
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(of: ":") else { return nil }
        let namespace = String(trimmed[trimmed.startIndex..<separator])
        let value = String(trimmed[trimmed.index(after: separator)...])
        guard !namespace.isEmpty, !value.isEmpty else { return nil }
        return Parsed(namespace: namespace, value: value)
    }

    static func isValid(_ uid: String?) -> Bool { parse(uid) != nil }
}

/// The positional identifier a playlist stores for each of its songs.
///
/// **Not every song has a `SONG_UID`.** Only files that came through Music
/// Downloader carry one — every customer bringing their own music has none. So
/// the key is the UID when there is one and the file's path otherwise, which
/// keeps those songs exactly as durable as they were before this existed.
///
/// Playlists and games store these positionally: card grids index into the
/// array 1-based, so **order and length are load-bearing**. Replace an element
/// in place, never insert or delete without regenerating the cards.
enum SongKey {
    private static let uidPrefix = "uid:"
    private static let filePrefix = "file:"

    /// The durable key for a song. Prefers the tag-embedded UID; falls back to
    /// the path relative to the folder root, which survives the container path
    /// changing on reinstall even though it doesn't survive a rename.
    static func make(uid: String?, relativePath: String?, fileName: String) -> String {
        if let uid, SongUID.isValid(uid) {
            return uidPrefix + uid
        }
        if let relativePath, !relativePath.isEmpty {
            return filePrefix + relativePath
        }
        return filePrefix + fileName
    }

    /// The UID inside a key, when it has one.
    static func uid(from key: String) -> String? {
        guard key.hasPrefix(uidPrefix) else { return nil }
        return String(key.dropFirst(uidPrefix.count))
    }

    /// The relative path inside a key, when it has one.
    static func path(from key: String) -> String? {
        guard key.hasPrefix(filePrefix) else { return nil }
        return String(key.dropFirst(filePrefix.count))
    }

    /// The trailing file name of whatever the key points at — the last-resort
    /// matching rung, and the only one that survives a folder reorganization.
    static func fileName(from key: String) -> String? {
        let body = uid(from: key) ?? path(from: key) ?? key
        let name = body.split(separator: "/").last.map(String.init)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// True for keys written before this scheme existed — bare absolute URL
    /// strings. Kept so a store that wasn't wiped still resolves.
    static func isLegacyURLString(_ key: String) -> Bool {
        !key.hasPrefix(uidPrefix) && !key.hasPrefix(filePrefix)
    }
}
