import Foundation
import Combine

/// The live signal level, per channel, kept off the player's own publisher.
///
/// `AudioPlayerService` publishes things a whole screen reacts to — the song,
/// the round, the playhead. Level moves far faster than any of that: this ticks
/// twenty-four times a second. Hanging it off the same publisher would redraw
/// the game screen, boards and all, at that rate for two bars a few points
/// wide. It lives here instead, and only the meter observes it.
@MainActor
final class AudioLevelMeter: ObservableObject {

    /// How loud each channel is right now, 0...1, after the gain going out — so
    /// these fall away through a fade even though the music hasn't changed.
    /// A mono file feeds the same value to both.
    @Published private(set) var left: Double = 0
    @Published private(set) var right: Double = 0

    /// Nothing is playing: drop the needles rather than leaving them stuck at
    /// whatever the last sample happened to be.
    func silence() {
        smoothedLeft = 0
        smoothedRight = 0
        if left != 0 { left = 0 }
        if right != 0 { right = 0 }
    }

    func feed(leftDecibels: Double, rightDecibels: Double, gain: Double) {
        let gain = min(max(gain, 0), 1)
        smoothedLeft = Self.ballistics(
            current: smoothedLeft,
            target: Self.normalize(decibels: leftDecibels) * gain
        )
        smoothedRight = Self.ballistics(
            current: smoothedRight,
            target: Self.normalize(decibels: rightDecibels) * gain
        )
        publish(&left, smoothedLeft)
        publish(&right, smoothedRight)
    }

    private func publish(_ stored: inout Double, _ value: Double) {
        // Below this the bar moves less than a pixel, so a redraw buys nothing.
        guard abs(value - stored) > 0.002 else { return }
        stored = min(max(value, 0), 1)
    }

    // MARK: - Ballistics

    private var smoothedLeft: Double = 0
    private var smoothedRight: Double = 0

    /// Where the meter bottoms out.
    ///
    /// Tuned for what a modern master actually does rather than for the format:
    /// a loud mix lives between roughly -20 and -6 dBFS and almost never visits
    /// the bottom half of a -60 dB scale, so a deep floor spends most of the bar
    /// on silence and the meter looks welded in place. -40 puts the range the
    /// music actually uses across the whole bar.
    private static let floorDB: Double = -40

    /// Decibels to a 0...1 bar height.
    ///
    /// Linear *in dB* rather than in amplitude: amplitude puts everything the
    /// ear calls "loud" in the top sliver of the bar and the meter looks dead.
    static func normalize(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels - floorDB) / -floorDB, 0), 1)
    }

    // MARK: - Zones
    //
    // Where the bar changes colour, given as fractions of its height so a view
    // can build a gradient from them — but *defined* in dBFS, because that's
    // what the boundaries actually mean. Comfortable below -12, working up to
    // -3, hot above it. Note these describe the level going out, not the file:
    // pulling the fader down takes the meter out of the red, which is exactly
    // what a host wants it to mean.

    /// Green gives way to amber here.
    static let cautionThreshold = normalize(decibels: -12)

    /// Amber gives way to red here.
    static let hotThreshold = normalize(decibels: -3)

    /// Rises instantly and falls away — the same asymmetry a hardware meter
    /// has. Without it the bar strobes on every kick drum instead of dancing.
    private static let release: Double = 0.4

    private static func ballistics(current: Double, target: Double) -> Double {
        target > current ? target : current + (target - current) * release
    }
}
