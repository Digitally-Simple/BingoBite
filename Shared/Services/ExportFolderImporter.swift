import Foundation
import SwiftData

/// Merges a Music Downloader export folder into the master library.
///
/// The library lives inside the app's own Documents directory, so the app can
/// copy files into it directly — no security-scoped access, no bookmarks. The
/// user drags an export folder into **On My iPad › BingoBite** and taps Import.
@MainActor
enum ExportFolderImporter {

    struct Result {
        var copied: Int = 0
        var skippedDuplicates: Int = 0
        var playlistsCreated: Int = 0
        var playlistsSkipped: [String] = []
        var failures: [(file: String, error: String)] = []

        var isEmpty: Bool { copied == 0 && playlistsCreated == 0 }
    }

    /// A folder that looks importable, with a preview of what's in it.
    struct Candidate: Identifiable {
        let folderURL: URL
        let manifest: LibraryManifest?
        let audioFileCount: Int

        var id: String { folderURL.path }
        var name: String { folderURL.lastPathComponent }
        var playlistCount: Int { manifest?.playlists.count ?? 0 }
    }

    /// Inspects a folder without changing anything.
    static func inspect(_ folderURL: URL) -> Candidate {
        let manifest = LibraryManifest.read(from: folderURL)
        let count = (try? FolderScannerService.audioFileURLs(in: folderURL, recursive: true).count) ?? 0
        return Candidate(folderURL: folderURL, manifest: manifest, audioFileCount: count)
    }

    /// Copies the folder's audio into the library, then creates any playlists
    /// its manifest describes.
    ///
    /// Files already in the library are skipped — matched by UID when both
    /// sides have one, by filename otherwise. Re-importing the same export is
    /// therefore a no-op rather than a pile of duplicates.
    static func `import`(
        candidate: Candidate,
        libraryURL: URL,
        in context: ModelContext,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> Result {
        var result = Result()
        let fm = FileManager.default
        try fm.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let existing = LibraryIndexService.allEntries(in: context)
        var knownUIDs = Set(existing.map(\.uid).filter { !$0.isEmpty })
        var knownFileNames = Set(existing.map(\.relativePath))

        // The manifest tells us each file's UID without opening it, which keeps
        // the duplicate check cheap. Fall back to filename when it's absent.
        var uidByFile: [String: String] = [:]
        for song in candidate.manifest?.songs ?? [] {
            uidByFile[song.file] = song.uid
        }

        let sourceFiles = try FolderScannerService.audioFileURLs(
            in: candidate.folderURL,
            recursive: true
        )

        for (offset, sourceURL) in sourceFiles.enumerated() {
            let relative = FolderScannerService.relativePath(of: sourceURL, under: candidate.folderURL)

            if let uid = uidByFile[relative], !uid.isEmpty, knownUIDs.contains(uid) {
                result.skippedDuplicates += 1
                continue
            }
            if knownFileNames.contains(relative) {
                result.skippedDuplicates += 1
                continue
            }

            let destination = libraryURL.appendingPathComponent(relative)
            do {
                try fm.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: sourceURL, to: destination)
                result.copied += 1
                knownFileNames.insert(relative)
                if let uid = uidByFile[relative], !uid.isEmpty { knownUIDs.insert(uid) }
            } catch {
                result.failures.append((relative, error.localizedDescription))
            }

            onProgress?(offset + 1, sourceFiles.count)
        }

        // Reconcile before creating playlists — they resolve against the index,
        // which has to know about the files we just copied.
        let root = LibraryIndexService.setRoot(url: libraryURL, in: context)
        try await LibraryIndexService.sweep(root: root, in: context)

        if let manifest = candidate.manifest {
            let created = createPlaylists(
                from: manifest,
                libraryURL: libraryURL,
                in: context
            )
            result.playlistsCreated = created.created
            result.playlistsSkipped = created.skipped
        }

        return result
    }

    // MARK: - Playlists from a manifest

    private static func createPlaylists(
        from manifest: LibraryManifest,
        libraryURL: URL,
        in context: ModelContext
    ) -> (created: Int, skipped: [String]) {
        let index = LibraryIndexService.songIndex(in: context, libraryRoot: libraryURL)
        let existingNames = Set(PlaylistService.fetchAll(in: context).map(\.name))

        var created = 0
        var skipped: [String] = []

        for definition in manifest.playlists {
            // Don't silently duplicate a playlist the user already has.
            guard !existingNames.contains(definition.name) else {
                skipped.append("\(definition.name) — already exists")
                continue
            }

            var songs: [Song] = []
            var missing = 0
            for uid in definition.songUIDs {
                let key = SongKey.make(uid: uid, relativePath: nil, fileName: uid)
                if let song = index.song(for: key) {
                    songs.append(song)
                } else {
                    missing += 1
                }
            }

            let required = 24
            guard songs.count >= required else {
                skipped.append("\(definition.name) — only \(songs.count) of \(definition.songUIDs.count) songs found")
                continue
            }
            if missing > 0 {
                skipped.append("\(definition.name) — created without \(missing) missing song\(missing == 1 ? "" : "s")")
            }

            do {
                _ = try PlaylistService.create(
                    folderURL: libraryURL,
                    includedSongs: songs,
                    name: definition.name,
                    description: definition.description ?? "",
                    numberOfCards: 30,
                    hasFreeSpace: true,
                    in: context
                )
                created += 1
            } catch {
                skipped.append("\(definition.name) — \(error.localizedDescription)")
            }
        }

        return (created, skipped)
    }
}
