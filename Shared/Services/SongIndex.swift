import Foundation

/// Resolves the song keys frozen into a playlist or game back to the songs
/// actually found on disk.
///
/// Four rungs, most durable first:
///
/// 1. **`SONG_UID`** — survives renames, moves, and re-copies. Only files from
///    Music Downloader carry one.
/// 2. **Relative path** — survives the app's data container being re-created on
///    reinstall or restore, which rewrites every absolute path.
/// 3. **Absolute URL** — legacy keys written before this scheme existed.
/// 4. **File name** — last resort, and the only rung that survives a folder
///    being reorganized.
struct SongIndex {
    private let byUID: [String: Song]
    private let byRelativePath: [String: Song]
    private let byURL: [String: Song]
    private let byFileName: [String: Song]

    init(_ songs: [Song]) {
        var uid: [String: Song] = [:]
        var relative: [String: Song] = [:]
        var url: [String: Song] = [:]
        var name: [String: Song] = [:]

        for song in songs {
            if let songUID = song.uid, !songUID.isEmpty, uid[songUID] == nil {
                uid[songUID] = song
            }
            if let path = song.relativePath, !path.isEmpty, relative[path] == nil {
                relative[path] = song
            }
            let absolute = song.id.absoluteString
            if url[absolute] == nil { url[absolute] = song }
            let fileName = song.id.lastPathComponent
            if name[fileName] == nil { name[fileName] = song }
        }

        byUID = uid
        byRelativePath = relative
        byURL = url
        byFileName = name
    }

    /// The song for a stored key, or nil when the file is really gone.
    func song(for key: String) -> Song? {
        // Rung 1 — the embedded UID.
        if let uid = SongKey.uid(from: key), let hit = byUID[uid] { return hit }

        // Rung 2 — the relative path.
        if let path = SongKey.path(from: key), let hit = byRelativePath[path] { return hit }

        // Rung 3 — a legacy absolute URL string.
        if SongKey.isLegacyURLString(key), let hit = byURL[key] { return hit }

        // Rung 4 — the bare file name.
        if let fileName = SongKey.fileName(from: key), let hit = byFileName[fileName] { return hit }

        return nil
    }

    /// True when the key resolved on a weaker rung than it was written on,
    /// meaning the caller should refresh the stored key.
    func needsRelink(_ key: String) -> Bool {
        guard let song = song(for: key) else { return false }
        return song.stableKey != key
    }

    /// The key this song should be stored under now.
    func currentKey(for key: String) -> String? {
        song(for: key)?.stableKey
    }

    static func fileName(from key: String) -> String? {
        SongKey.fileName(from: key)
    }
}
