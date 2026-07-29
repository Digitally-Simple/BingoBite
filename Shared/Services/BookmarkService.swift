import Foundation

/// Persists access to a user-chosen songs folder across launches.
///
/// macOS uses security-scoped bookmarks. On iOS the `.withSecurityScope`
/// option doesn't exist — bookmarks made from a `fileImporter` URL are already
/// security-scoped — hence the split below.
enum BookmarkService {
    static func createBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        if isStale {
            // Caller should recreate the bookmark
            throw BookmarkError.stale(url)
        }
        return url
    }

    static func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    enum BookmarkError: LocalizedError {
        case stale(URL)

        var errorDescription: String? {
            switch self {
            case .stale(let url):
                return "Bookmark for \(url.path) is stale and needs to be recreated."
            }
        }
    }
}
