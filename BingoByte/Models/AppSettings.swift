import Foundation
import SwiftData

@Model
final class AppSettings {
    var folderPath: String
    var bookmarkData: Data?
    var lastScannedDate: Date?
    var geniusAPIKey: String = ""
    var licenseKey: String = ""
    var licenseKeyInstanceId: String = ""
    var lastLicenseValidationDate: Date? = nil

    init(folderPath: String = "", bookmarkData: Data? = nil, lastScannedDate: Date? = nil, geniusAPIKey: String = "", licenseKey: String = "", licenseKeyInstanceId: String = "", lastLicenseValidationDate: Date? = nil) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.lastScannedDate = lastScannedDate
        self.geniusAPIKey = geniusAPIKey
        self.licenseKey = licenseKey
        self.licenseKeyInstanceId = licenseKeyInstanceId
        self.lastLicenseValidationDate = lastLicenseValidationDate
    }
}
