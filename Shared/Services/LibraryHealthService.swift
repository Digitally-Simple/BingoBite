import Foundation
import SwiftData

/// Answers "what's broken right now" across the whole library and every
/// playlist, rather than only noticing when a playlist happens to be opened.
///
/// Everything here is stat-only — it reads the cached index and checks file
/// existence. No tag parsing, so it's cheap enough to run on every appearance.
@MainActor
enum LibraryHealthService {

    struct Report {
        var missingSongs: [LibraryIndexEntry] = []
        /// Playlists that reference at least one song no longer resolvable,
        /// with how many each is short.
        var affectedPlaylists: [(playlist: Playlist, missingCount: Int)] = []

        var isHealthy: Bool { missingSongs.isEmpty && affectedPlaylists.isEmpty }
        var missingCount: Int { missingSongs.count }
    }

    /// Cross-references the index and every playlist.
    static func report(in context: ModelContext, libraryRoot: URL) -> Report {
        var report = Report()
        report.missingSongs = LibraryIndexService.missingEntries(in: context)

        let index = LibraryIndexService.songIndex(in: context, libraryRoot: libraryRoot)
        for playlist in PlaylistService.fetchAll(in: context) {
            // Library-backed playlists resolve through the index; folder-backed
            // ones own their folder and are checked when opened, so only count
            // the keys this index is actually responsible for.
            let missing = playlist.songKeys.count { index.song(for: $0) == nil }
            if missing > 0 {
                report.affectedPlaylists.append((playlist, missing))
            }
        }
        return report
    }

    /// How many songs a single playlist can't resolve. Used for row badges.
    static func missingCount(for playlist: Playlist, in context: ModelContext, libraryRoot: URL) -> Int {
        let index = LibraryIndexService.songIndex(in: context, libraryRoot: libraryRoot)
        return playlist.songKeys.count { index.song(for: $0) == nil }
    }

    /// Re-checks existence of every index row without re-reading any tags.
    ///
    /// Cheaper than a full sweep and safe to call often — it only flips
    /// `isMissing`, so a file that reappears is picked straight back up.
    @discardableResult
    static func refreshMissingFlags(in context: ModelContext, libraryRoot: URL) -> Int {
        let fm = FileManager.default
        var missing = 0
        for entry in LibraryIndexService.allEntries(in: context) {
            let exists = fm.fileExists(atPath: libraryRoot.appendingPathComponent(entry.relativePath).path)
            if entry.isMissing != !exists {
                entry.isMissing = !exists
            }
            if !exists { missing += 1 }
        }
        try? context.save()
        return missing
    }

    /// Permanently forgets rows whose files are gone.
    ///
    /// Only ever user-initiated: an unplugged drive or a folder mid-reorganize
    /// looks identical to a deletion, and silently dropping those rows would
    /// take the playlists' ability to point at what to replace with it.
    static func purgeMissing(in context: ModelContext) {
        for entry in LibraryIndexService.missingEntries(in: context) {
            context.delete(entry)
        }
        try? context.save()
    }
}
