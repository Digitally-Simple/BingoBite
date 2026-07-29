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
        let readme = documentsURL.appendingPathComponent("Add your music here.txt")
        guard !FileManager.default.fileExists(atPath: readme.path) else { return }

        let text = """
        BingoBite — Music Folders

        Drop a folder of songs into this BingoBite folder and it will show up as
        a suggestion when you create a playlist.

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
