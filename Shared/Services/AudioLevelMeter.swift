import Foundation
import Combine

/// The fast-moving numbers, kept off the player's own publisher.
///
/// `AudioPlayerService` publishes things a whole screen reacts to — the song,
/// the round, the playhead. Volume moves far faster than any of that: a fade
/// ticks at 60Hz and the signal meter at 24. Hanging those off the same
/// publisher would redraw the game screen, boards and all, two dozen times a
/// second for a bar a few points wide. They live here instead, and only the
/// meter view observes it.
@MainActor
final class AudioLevelMeter: ObservableObject {

    /// The gain the player is outputting: the fader scaled by wherever the
    /// envelope is. Where the *fader* sits, not how loud the music is.
    @Published private(set) var output: Double = 1

    /// How loud the music itself is right now, 0...1, after that gain. This is
    /// the one that bumps — it follows the track, so it moves with the beat and
    /// goes quiet in the quiet parts.
    @Published private(set) var signal: Double = 0

    func set(output: Double) {
        let clamped = min(max(output, 0), 1)
        guard abs(clamped - self.output) > 0.001 else { return }
        self.output = clamped
    }

    func set(signal: Double) {
        let clamped = min(max(signal, 0), 1)
        guard abs(clamped - self.signal) > 0.002 else { return }
        self.signal = clamped
    }

    /// Nothing is playing: drop the needle rather than leaving it stuck at
    /// whatever the last sample happened to be.
    func silence() {
        signal = 0
    }

    // MARK: - Ballistics

    /// Where the meter bottoms out.
    ///
    /// Tuned for what a modern master actually does rather than for the format:
    /// a loud mix lives between roughly -20 and -6 dBFS and almost never visits
    /// the bottom half of a -60 dB scale, so a deep floor spends most of the bar
    /// on silence and the meter looks welded in place. -40 puts the range the
    /// music actually uses across the whole column.
    private static let floorDB: Double = -40

    /// Decibels to a 0...1 bar height.
    ///
    /// Linear *in dB* rather than in amplitude: amplitude puts everything the
    /// ear calls "loud" in the top sliver of the bar and the meter looks dead.
    static func normalize(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels - floorDB) / -floorDB, 0), 1)
    }

    /// Rises instantly and falls away — the same asymmetry a hardware meter
    /// has. Without it the bar strobes on every kick drum instead of dancing.
    private var smoothed: Double = 0
    private static let release: Double = 0.4

    func feed(decibels: Double, gain: Double) {
        let target = Self.normalize(decibels: decibels) * min(max(gain, 0), 1)
        if target > smoothed {
            smoothed = target
        } else {
            smoothed += (target - smoothed) * Self.release
        }
        set(signal: smoothed)
    }

    func reset() {
        smoothed = 0
        silence()
    }
}
