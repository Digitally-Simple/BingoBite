import Foundation
import SwiftData

@Model
final class AppSettings {
    var licenseKey: String = ""
    var licenseKeyInstanceId: String = ""
    var lastLicenseValidationDate: Date? = nil

    init(licenseKey: String = "", licenseKeyInstanceId: String = "", lastLicenseValidationDate: Date? = nil) {
        self.licenseKey = licenseKey
        self.licenseKeyInstanceId = licenseKeyInstanceId
        self.lastLicenseValidationDate = lastLicenseValidationDate
    }
}
