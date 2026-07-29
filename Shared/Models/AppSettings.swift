import Foundation
import SwiftData

/// App-wide preferences. Kept as a model so future settings have a home;
/// the Dodo license/trial fields were removed when licensing was dropped.
@Model
final class AppSettings {
    var lastOpenedDate: Date? = nil

    init(lastOpenedDate: Date? = nil) {
        self.lastOpenedDate = lastOpenedDate
    }
}
