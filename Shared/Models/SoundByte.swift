import Foundation
import SwiftData

@Model
final class SoundByte {
    /// Stable song key — see `SongKey`. Defaulted so a future schema change
    /// doesn't fail migration on a mandatory attribute with no value.
    @Attribute(.unique) var songKey: String = ""
    var startTime: TimeInterval = 0
    var endTime: TimeInterval = 0

    var clipDuration: TimeInterval {
        endTime - startTime
    }

    init(songKey: String, startTime: TimeInterval = 0, endTime: TimeInterval = 0) {
        self.songKey = songKey
        self.startTime = startTime
        self.endTime = endTime
    }
}
