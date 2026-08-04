import Foundation

/// Handles the destructive store reset that a schema change requires.
///
/// The app has never supported SwiftData migration — a schema change wipes the
/// store. This service keeps that behavior but **archives the old store instead
/// of deleting it**, so a reset is recoverable by hand rather than final.
///
/// Note on why there's no nice JSON export here: the reset has to happen before
/// `ModelContainer` is created, and the old store can't be opened with the new
/// schema — which is the whole reason it's being reset. Archiving the raw
/// SQLite file is the only thing that can actually be done at that point, and
/// it preserves strictly more than deleting does.
enum StoreResetService {

    static let schemaVersionKey = "BingoBite.SchemaVersion"

    /// Bump when the shape of any `@Model` changes.
    ///
    /// **Version 4** — playlists and games now store stable song keys (the
    /// embedded `SONG_UID`, or a path relative to the folder root) instead of
    /// absolute file URLs, and the library index was added. Existing playlists
    /// cannot be carried across, because their stored URLs don't describe the
    /// songs well enough to rebuild a key.
    ///
    /// **Version 5** — `SoundByte.songURLString` and
    /// `SongMetadataOverride.songURLString` were renamed to `songKey` and now
    /// hold the stable key too, so a renamed file keeps its trim and its
    /// metadata edits. A rename reads to SwiftData as a new mandatory
    /// attribute with no value on existing rows, which fails migration
    /// outright — it has to go through the reset.
    static let currentSchemaVersion = 5

    private static let storeFileNames = ["default.store", "default.store-shm", "default.store-wal"]

    /// Archives and clears the store when the schema version has moved on.
    /// Returns the archive folder when one was made, for surfacing to the user.
    @discardableResult
    static func resetIfNeeded(storeDirectory: URL) -> URL? {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: schemaVersionKey)
        guard previous < currentSchemaVersion else { return nil }

        defer { defaults.set(currentSchemaVersion, forKey: schemaVersionKey) }

        let fm = FileManager.default
        let existing = storeFileNames
            .map { storeDirectory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        // Nothing to preserve — a fresh install, not an upgrade.
        guard !existing.isEmpty else { return nil }

        let archive = storeDirectory
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("store-v\(previous)-\(timestamp())", isDirectory: true)

        do {
            try fm.createDirectory(at: archive, withIntermediateDirectories: true)
            for url in existing {
                try fm.moveItem(at: url, to: archive.appendingPathComponent(url.lastPathComponent))
            }
            return archive
        } catch {
            // Archiving failed, but the reset still has to happen or the app
            // won't launch. Fall back to deleting.
            for url in existing { try? fm.removeItem(at: url) }
            return nil
        }
    }

    /// Archives the store unconditionally, for recovering from a container
    /// that won't open.
    ///
    /// The version check in `resetIfNeeded` only fires when someone remembers
    /// to bump the number. When that's missed, the store fails to load and the
    /// app used to die on `try!` at launch with no way back short of deleting
    /// it. This is the escape hatch.
    @discardableResult
    static func forceArchive(storeDirectory: URL) -> URL? {
        let previous = UserDefaults.standard.integer(forKey: schemaVersionKey)
        let fm = FileManager.default
        let existing = storeFileNames
            .map { storeDirectory.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let archive = storeDirectory
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("store-v\(previous)-unreadable-\(timestamp())", isDirectory: true)
        do {
            try fm.createDirectory(at: archive, withIntermediateDirectories: true)
            for url in existing {
                try fm.moveItem(at: url, to: archive.appendingPathComponent(url.lastPathComponent))
            }
            return archive
        } catch {
            for url in existing { try? fm.removeItem(at: url) }
            return nil
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
