import Foundation

/// Resolves the song URL strings frozen into a playlist or game back to the
/// songs actually found on disk.
///
/// Playlists store absolute file URLs, but those go stale whenever the source
/// folder moves — and on iOS the app's data container is re-created on
/// reinstall or restore, which rewrites the path of every file the app owns.
/// The file name inside the playlist's folder is the stable identity, so fall
/// back to it before declaring a track missing.
struct SongIndex {
    private let byURL: [String: Song]
    private let byFileName: [String: Song]

    init(_ songs: [Song]) {
        byURL = Dictionary(songs.map { ($0.id.absoluteString, $0) }, uniquingKeysWith: { first, _ in first })
        byFileName = Dictionary(songs.map { ($0.id.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The song for a stored URL string, or nil when the file is really gone.
    func song(for urlString: String) -> Song? {
        if let exact = byURL[urlString] { return exact }
        guard let fileName = Self.fileName(from: urlString) else { return nil }
        return byFileName[fileName]
    }

    /// True when the stored string resolved only by file name, meaning the
    /// caller should refresh the persisted URL.
    func needsRelink(_ urlString: String) -> Bool {
        byURL[urlString] == nil && song(for: urlString) != nil
    }

    static func fileName(from urlString: String) -> String? {
        if let url = URL(string: urlString) {
            let name = url.lastPathComponent
            if !name.isEmpty { return name }
        }
        // Not a valid URL string — fall back to the trailing path segment.
        return urlString.split(separator: "/").last.map(String.init)
    }
}
