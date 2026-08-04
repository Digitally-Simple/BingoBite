import Foundation
import SwiftData

/// Where the master library lives, and when it was last swept.
///
/// On iPad the library is a fixed folder inside the app's own Documents
/// directory (`On My iPad › BingoBite › Library`), so it needs no
/// security-scoped bookmark at all — the app owns it. `bookmarkData` is only
/// populated on macOS, or if a folder outside the container is ever chosen.
@Model
final class LibraryRoot {
    var path: String = ""
    var name: String = ""
    /// Empty for app-owned folders, which need no scoped access.
    var bookmarkData: Data = Data()
    var lastSweepDate: Date?
    /// Bumped in code, not by SwiftData, when the scanning or parsing logic
    /// changes in a way that invalidates cached rows. A mismatch forces a full
    /// re-read at zero schema cost.
    var indexFormatVersion: Int = 0
    var songCount: Int = 0
    var missingCount: Int = 0

    init(
        path: String,
        name: String = "Library",
        bookmarkData: Data = Data(),
        lastSweepDate: Date? = nil,
        indexFormatVersion: Int = 0,
        songCount: Int = 0,
        missingCount: Int = 0
    ) {
        self.path = path
        self.name = name
        self.bookmarkData = bookmarkData
        self.lastSweepDate = lastSweepDate
        self.indexFormatVersion = indexFormatVersion
        self.songCount = songCount
        self.missingCount = missingCount
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// True when the folder needs `startAccessingSecurityScopedResource`.
    var needsScopedAccess: Bool { !bookmarkData.isEmpty }

    var hasBeenSwept: Bool { lastSweepDate != nil }
}
