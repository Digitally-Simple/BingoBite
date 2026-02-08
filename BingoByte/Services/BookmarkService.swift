import Foundation

enum BookmarkService {
    static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
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
