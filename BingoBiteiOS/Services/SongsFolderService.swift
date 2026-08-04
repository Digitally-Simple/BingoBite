import Foundation

/// Bridges BingoBite to the Files app.
///
/// `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` publish the
/// app's Documents directory as **On My iPad › BingoBite**, so songs can be
/// dropped straight in from Files, AirDrop, or a Mac. Any subfolder of that
/// directory shows up as a one-tap suggestion when creating a playlist; the
/// folder picker still reaches anywhere else in Files (iCloud Drive, Dropbox…).
enum SongsFolderService {

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The master library: one folder holding one copy of every song.
    ///
    /// Fixed inside the app's own Documents directory, which means the app owns
    /// it — no security-scoped bookmarks, no stale-bookmark failures, and it
    /// shows up in Files as **On My iPad › BingoBite › Library** for dragging
    /// an export folder straight in.
    static let libraryFolderName = "Library"

    static var libraryURL: URL {
        documentsURL.appendingPathComponent(libraryFolderName, isDirectory: true)
    }

    /// Folders in Documents that look like a Music Downloader export — they
    /// carry a manifest at the top level. Offered as one-tap imports.
    static func pendingExportFolders() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.lastPathComponent != libraryFolderName }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { fm.fileExists(atPath: $0.appendingPathComponent(manifestFileName).path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static let manifestFileName = "bingobite-library.json"

    /// Folders inside Documents that contain at least one supported audio file.
    /// These need no security-scoped access — the app owns them.
    static func suggestedFolders() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            // The library has its own dedicated entry in the picker; listing it
            // here too would offer the same songs twice, once as a one-off
            // folder copy and once by reference.
            .filter { $0.lastPathComponent != libraryFolderName }
            .filter { containsAudio($0) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// True when Documents itself holds loose audio files, which makes it a
    /// valid pick on its own.
    static func documentsRootHasAudio() -> Bool {
        containsAudio(documentsURL)
    }

    static func containsAudio(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return entries.contains { FolderScannerService.supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// A folder inside the app's own container needs no `startAccessingSecurityScopedResource`.
    static func isAppOwned(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(documentsURL.standardizedFileURL.path)
    }

    /// Writes a short README the first time the app runs so the folder is
    /// visible in Files even before any songs are added.
    static func prepareDocumentsFolder() {
        // The library folder always exists, so it's visible in Files from the
        // first launch and an export can be dropped straight into it.
        try? FileManager.default.createDirectory(
            at: libraryURL,
            withIntermediateDirectories: true
        )

        let readme = documentsURL.appendingPathComponent("Add your music here.txt")
        guard !FileManager.default.fileExists(atPath: readme.path) else { return }

        let text = """
        BingoBite — Music Folders

        Library/
          Your master library. Every song lives here once, and playlists point
          at it, so the same song used in five playlists is stored one time.
          Drop songs or a whole folder in here and open the Songs tab.

        Anywhere else in this folder
          Drop a folder of songs here and it shows up as a suggestion when you
          create a playlist, kept separate from the library.

        Supported formats: \(FolderScannerService.supportedExtensions.sorted().joined(separator: ", "))

        You can also tap "Browse Files…" when creating a playlist to pick a
        folder anywhere else — iCloud Drive, Dropbox, or a connected drive.
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }

    /// Human-readable location for a folder URL, e.g. "BingoBite › 90s Hits".
    static func displayPath(for url: URL) -> String {
        if isAppOwned(url) {
            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: documentsURL.standardizedFileURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? "BingoBite" : "BingoBite › \(relative.replacingOccurrences(of: "/", with: " › "))"
        }
        return url.lastPathComponent
    }
}
