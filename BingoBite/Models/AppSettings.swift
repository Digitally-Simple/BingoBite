import Foundation
import SwiftData

@Model
final class AppSettings {
    var licenseKey: String = ""
    var licenseKeyInstanceId: String = ""
    var lastLicenseValidationDate: Date? = nil
    var trialStartDate: Date? = nil

    init(licenseKey: String = "", licenseKeyInstanceId: String = "", lastLicenseValidationDate: Date? = nil, trialStartDate: Date? = nil) {
        self.licenseKey = licenseKey
        self.licenseKeyInstanceId = licenseKeyInstanceId
        self.lastLicenseValidationDate = lastLicenseValidationDate
        self.trialStartDate = trialStartDate
    }
}
