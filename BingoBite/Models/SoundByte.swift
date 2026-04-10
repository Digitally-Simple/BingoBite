import Foundation
import SwiftData

@Model
final class SoundByte {
    @Attribute(.unique) var songURLString: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    var clipDuration: TimeInterval {
        endTime - startTime
    }

    init(songURLString: String, startTime: TimeInterval = 0, endTime: TimeInterval = 0) {
        self.songURLString = songURLString
        self.startTime = startTime
        self.endTime = endTime
    }
}
