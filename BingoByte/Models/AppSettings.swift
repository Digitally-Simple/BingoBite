import Foundation
import SwiftData

@Model
final class AppSettings {
    var folderPath: String
    var bookmarkData: Data?
    var lastScannedDate: Date?

    init(folderPath: String = "", bookmarkData: Data? = nil, lastScannedDate: Date? = nil) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.lastScannedDate = lastScannedDate
    }
}
