import Foundation
import SwiftData

/// Keeps a cached index of the master library so browsing it is instant.
///
/// The problem this solves: `FolderScannerService.scanForAudio` reads tags from
/// every file, which means spawning ffmpeg per file on macOS or parsing the
/// container on iOS. At thirty songs that's imperceptible. At a thousand it's
/// minutes — every time a view appears.
///
/// The fix is that a sweep only *stats* each file and compares `contentStamp`
/// (`size-mtime`). Unchanged files reuse their cached row and read nothing.
/// Only genuinely new or modified files pay the tag-reading cost. A warm sweep
/// over a thousand songs is a thousand stat calls, which is milliseconds.
@MainActor
enum LibraryIndexService {

    /// Bump when scanning or parsing changes in a way that makes cached rows
    /// wrong. Forces a full re-read without touching the SwiftData schema.
    static let indexFormatVersion = 1

    /// Thumbnail edge length in pixels. Big enough for a retina list row,
    /// small enough that a thousand of them stay well under ~20 MB.
    private static let thumbnailSize: CGFloat = 128

    struct Progress: Sendable {
        var processed: Int
        var total: Int
        var isReadingTags: Bool

        var fraction: Double {
            total > 0 ? Double(processed) / Double(total) : 0
        }
    }

    struct SweepResult {
        var scanned: Int = 0
        var added: Int = 0
        var updated: Int = 0
        var reused: Int = 0
        var missing: Int = 0
        /// Wall-clock seconds. A warm sweep should be a small fraction of a
        /// second regardless of library size — if it isn't, the `contentStamp`
        /// fast path is being missed and every file is being re-read.
        var duration: TimeInterval = 0

        var summary: String {
            String(
                format: "swept %d files in %.2fs (%d new, %d changed, %d cached, %d missing)",
                scanned, duration, added, updated, reused, missing
            )
        }
    }

    // MARK: - Root management

    /// The single library root, if one has been set up.
    static func root(in context: ModelContext) -> LibraryRoot? {
        try? context.fetch(FetchDescriptor<LibraryRoot>()).first
    }

    /// Points the library at `url`, replacing any existing root. Changing the
    /// root invalidates every cached row, since paths are relative to it.
    @discardableResult
    static func setRoot(
        url: URL,
        name: String? = nil,
        bookmarkData: Data = Data(),
        in context: ModelContext
    ) -> LibraryRoot {
        if let existing = root(in: context) {
            if existing.path != url.path {
                deleteAllEntries(in: context)
                existing.path = url.path
                existing.lastSweepDate = nil
                existing.songCount = 0
                existing.missingCount = 0
            }
            existing.bookmarkData = bookmarkData
            if let name { existing.name = name }
            try? context.save()
            return existing
        }

        let created = LibraryRoot(
            path: url.path,
            name: name ?? url.lastPathComponent,
            bookmarkData: bookmarkData
        )
        context.insert(created)
        try? context.save()
        return created
    }

    static func deleteAllEntries(in context: ModelContext) {
        try? context.delete(model: LibraryIndexEntry.self)
        try? context.save()
    }

    // MARK: - Reading

    static func allEntries(in context: ModelContext) -> [LibraryIndexEntry] {
        let descriptor = FetchDescriptor<LibraryIndexEntry>(
            sortBy: [
                SortDescriptor(\.artist),
                SortDescriptor(\.title),
            ]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func missingEntries(in context: ModelContext) -> [LibraryIndexEntry] {
        let descriptor = FetchDescriptor<LibraryIndexEntry>(
            predicate: #Predicate { $0.isMissing }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// A `SongIndex` over the whole library, built entirely from cached rows —
    /// no disk access at all.
    static func songIndex(in context: ModelContext, libraryRoot: URL) -> SongIndex {
        SongIndex(allEntries(in: context).map { $0.makeSong(libraryRoot: libraryRoot) })
    }

    static func songs(in context: ModelContext, libraryRoot: URL) -> [Song] {
        allEntries(in: context).map { $0.makeSong(libraryRoot: libraryRoot) }
    }

    // MARK: - Sweep

    /// Reconciles the index against what's on disk.
    ///
    /// - Parameter force: re-reads tags for every file, ignoring `contentStamp`.
    ///   For recovering from a bad parse rather than routine use.
    @discardableResult
    static func sweep(
        root: LibraryRoot,
        in context: ModelContext,
        force: Bool = false,
        onProgress: (@MainActor (Progress) -> Void)? = nil
    ) async throws -> SweepResult {
        let libraryURL = root.url
        let startedAt = Date()
        var result = SweepResult()

        // A version bump means cached rows can't be trusted.
        let forceAll = force || root.indexFormatVersion != indexFormatVersion

        let fileURLs = try FolderScannerService.audioFileURLs(in: libraryURL, recursive: true)
        result.scanned = fileURLs.count

        let existing = allEntries(in: context)
        var byPath: [String: LibraryIndexEntry] = [:]
        var byUID: [String: LibraryIndexEntry] = [:]
        var byFileName: [String: LibraryIndexEntry] = [:]
        for entry in existing {
            byPath[entry.relativePath] = entry
            if !entry.uid.isEmpty, byUID[entry.uid] == nil { byUID[entry.uid] = entry }
            if byFileName[entry.fileName] == nil { byFileName[entry.fileName] = entry }
        }

        var seen = Set<ObjectIdentifier>()
        /// Files that need their tags read. Collected first so the expensive
        /// work can run with bounded parallelism rather than one at a time.
        var needsRead: [(url: URL, relativePath: String, stamp: String)] = []
        var processed = 0

        for fileURL in fileURLs {
            let relative = FolderScannerService.relativePath(of: fileURL, under: libraryURL)
            let stamp = contentStamp(for: fileURL)

            // 1 — same path. The overwhelmingly common case on a warm sweep.
            if let entry = byPath[relative] {
                if !forceAll && entry.contentStamp == stamp {
                    entry.isMissing = false
                    entry.lastSeenAt = .now
                    seen.insert(ObjectIdentifier(entry))
                    result.reused += 1
                    processed += 1
                    continue
                }
                seen.insert(ObjectIdentifier(entry))
                needsRead.append((fileURL, relative, stamp))
                result.updated += 1
                processed += 1
                continue
            }

            // 2 — same UID at a different path: the file was renamed or moved.
            // Rewrite the path; only re-read tags if the content also changed.
            if !forceAll,
               let uid = quickUID(for: fileURL),
               let entry = byUID[uid],
               !seen.contains(ObjectIdentifier(entry)) {
                entry.relativePath = relative
                entry.isMissing = false
                entry.lastSeenAt = .now
                seen.insert(ObjectIdentifier(entry))
                if entry.contentStamp == stamp {
                    result.reused += 1
                } else {
                    needsRead.append((fileURL, relative, stamp))
                    result.updated += 1
                }
                processed += 1
                continue
            }

            // 3 — same file name, unchanged content. Covers untagged music that
            // was reorganized into a different subfolder.
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            if !forceAll,
               let entry = byFileName[fileName],
               !seen.contains(ObjectIdentifier(entry)),
               entry.contentStamp == stamp {
                entry.relativePath = relative
                entry.isMissing = false
                entry.lastSeenAt = .now
                seen.insert(ObjectIdentifier(entry))
                result.reused += 1
                processed += 1
                continue
            }

            // 4 — genuinely new.
            needsRead.append((fileURL, relative, stamp))
            result.added += 1
            processed += 1
        }

        onProgress?(Progress(processed: processed, total: fileURLs.count, isReadingTags: false))

        // Anything not seen this sweep is missing. Rows are kept, not deleted —
        // an unplugged drive or a folder being reorganized must not wipe the
        // index, and playlists need the row to show what to replace.
        for entry in existing where !seen.contains(ObjectIdentifier(entry)) {
            entry.isMissing = true
            result.missing += 1
        }

        try? context.save()

        // The expensive half: read tags only for files that actually changed.
        if !needsRead.isEmpty {
            try await readTags(
                for: needsRead,
                libraryURL: libraryURL,
                existingByPath: byPath,
                in: context,
                onProgress: onProgress
            )
        }

        root.lastSweepDate = .now
        root.indexFormatVersion = indexFormatVersion
        root.songCount = result.scanned
        root.missingCount = result.missing
        try? context.save()

        result.duration = Date().timeIntervalSince(startedAt)
        print("LibraryIndexService: \(result.summary)")
        return result
    }

    // MARK: - Tag reading

    private static func readTags(
        for files: [(url: URL, relativePath: String, stamp: String)],
        libraryURL: URL,
        existingByPath: [String: LibraryIndexEntry],
        in context: ModelContext,
        onProgress: (@MainActor (Progress) -> Void)?
    ) async throws {
        // ffmpeg spawns (macOS) and container parsing (iOS) are the bottleneck,
        // and both are off-MainActor work. Read in bounded-parallel batches,
        // then apply each batch's results here on the MainActor, where the
        // ModelContext lives. Batching keeps peak memory bounded — a thousand
        // songs' artwork held at once would be hundreds of megabytes.
        let batchSize = min(max(ProcessInfo.processInfo.activeProcessorCount - 2, 2), 6)
        var completed = 0

        for batchStart in stride(from: 0, to: files.count, by: batchSize) {
            let batch = Array(files[batchStart..<min(batchStart + batchSize, files.count)])

            let scanned: [(index: Int, song: Song?)] = await withTaskGroup(
                of: (Int, Song?).self
            ) { group in
                for (offset, file) in batch.enumerated() {
                    group.addTask {
                        let song = try? await FolderScannerService.scanFile(
                            at: file.url,
                            under: libraryURL
                        )
                        return (offset, song)
                    }
                }
                var results: [(index: Int, song: Song?)] = []
                for await item in group { results.append((item.0, item.1)) }
                return results
            }

            for entry in scanned.sorted(by: { $0.index < $1.index }) {
                let file = batch[entry.index]
                upsert(
                    song: entry.song,
                    fileURL: file.url,
                    relativePath: file.relativePath,
                    stamp: file.stamp,
                    existing: existingByPath[file.relativePath],
                    in: context
                )
            }

            completed += batch.count
            try? context.save()
            onProgress?(Progress(processed: completed, total: files.count, isReadingTags: true))
        }

        try? context.save()
    }

    private static func upsert(
        song: Song?,
        fileURL: URL,
        relativePath: String,
        stamp: String,
        existing: LibraryIndexEntry?,
        in context: ModelContext
    ) {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let entry = existing ?? {
            let created = LibraryIndexEntry(relativePath: relativePath)
            context.insert(created)
            return created
        }()

        entry.relativePath = relativePath
        entry.fileName = fileName
        entry.contentStamp = stamp
        entry.isMissing = false
        entry.lastSeenAt = .now

        if let song {
            entry.uid = song.uid ?? ""
            entry.title = song.title ?? ""
            entry.artist = song.artist ?? ""
            entry.album = song.album ?? ""
            entry.genre = song.genre ?? ""
            entry.year = song.year ?? ""
            entry.duration = song.duration ?? 0
            entry.fileSize = song.fileSize
            entry.geniusID = song.geniusID ?? 0
            entry.thumbnailData = song.artworkData.flatMap {
                ImageDownsampler.downsampledPNG(from: $0, maxDimension: thumbnailSize)
            }
        } else {
            // Tags couldn't be read. Keep the row so the file is still
            // browsable and playable — it just shows as its filename.
            entry.fileSize = fileSize(for: fileURL)
        }
    }

    // MARK: - Stat helpers

    /// `"<size>-<mtimeEpoch>"`. Cheap, and enough to know whether re-reading
    /// tags could possibly produce a different answer.
    static func contentStamp(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else { return "" }
        let modified = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(size)-\(modified)"
    }

    private static func fileSize(for url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(size)
    }

    /// Reads only the UID frame, for the renamed-file check.
    ///
    /// On iOS this parses the container directly, which is far cheaper than a
    /// full scan. On macOS there's no cheap path — a full read means spawning
    /// ffmpeg — so the rename check is skipped and the file falls through to
    /// being treated as new. It still ends up correct, just with one wasted
    /// tag read.
    private static func quickUID(for url: URL) -> String? {
        #if os(macOS)
        return nil
        #else
        let parsed = AudioTagReader.read(url: url)
        return FolderScannerService.tag(parsed.tags, SongUID.uidKey)
        #endif
    }
}
