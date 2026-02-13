import Foundation
import SwiftData

@Model
final class AppSettings {
    var folderPath: String
    var bookmarkData: Data?
    var lastScannedDate: Date?
    var geniusAPIKey: String = ""

    init(folderPath: String = "", bookmarkData: Data? = nil, lastScannedDate: Date? = nil, geniusAPIKey: String = "") {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.lastScannedDate = lastScannedDate
        self.geniusAPIKey = geniusAPIKey
    }
}
