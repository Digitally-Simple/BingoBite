import Foundation
import SwiftData

/// App-wide preferences. Kept as a model so future settings have a home;
/// the Dodo license/trial fields were removed when licensing was dropped.
@Model
final class AppSettings {
    var lastOpenedDate: Date? = nil

    // MARK: - Playback fades
    //
    // App-wide rather than per-song: a host wants every track in the night to
    // come up and go down the same way. Per-clip start and end times stay on
    // `SoundByte`.

    var fadesEnabled: Bool = true
    /// Stored as the curve's raw value so the enum can gain cases without a
    /// schema change.
    var fadeInCurveRaw: String = FadeCurve.smooth.rawValue
    var fadeInDuration: TimeInterval = 1.5
    var fadeOutCurveRaw: String = FadeCurve.smooth.rawValue
    var fadeOutDuration: TimeInterval = 2.0

    // MARK: - Autoplay
    //
    // The silence a room hears between one round's segment ending and the next
    // one starting. It lives here rather than on a game because it describes
    // how the host runs the room, not what's in a particular night's playlist.

    var autoplayGap: TimeInterval = 5.0

    // MARK: - Level
    //
    // Where the host left the fader. Remembered because a level set at
    // soundcheck shouldn't reset to full the next time the app launches —
    // finding out it did, mid-room, is the wrong way to find out.

    var playbackVolume: Double = 1.0

    init(lastOpenedDate: Date? = nil) {
        self.lastOpenedDate = lastOpenedDate
    }

    var fadeInCurve: FadeCurve {
        get { FadeCurve(rawValue: fadeInCurveRaw) ?? .smooth }
        set { fadeInCurveRaw = newValue.rawValue }
    }

    var fadeOutCurve: FadeCurve {
        get { FadeCurve(rawValue: fadeOutCurveRaw) ?? .smooth }
        set { fadeOutCurveRaw = newValue.rawValue }
    }

    /// The envelope the player should apply, or a flat one when fades are off.
    var fadeEnvelope: FadeEnvelope {
        guard fadesEnabled else { return .none }
        return FadeEnvelope(
            fadeInCurve: fadeInCurve,
            fadeInDuration: fadeInDuration,
            fadeOutCurve: fadeOutCurve,
            fadeOutDuration: fadeOutDuration
        )
    }

    /// Longest fade the UI offers. Beyond this a "fade" is really just a slow
    /// volume ride, and it starts eating short clips.
    static let maximumFadeDuration: TimeInterval = 15

    /// Longest gap the UI offers. Past half a minute of silence the room
    /// assumes something broke and looks at the host anyway.
    static let maximumAutoplayGap: TimeInterval = 30
}
