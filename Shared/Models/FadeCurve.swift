import Foundation

/// The shape a fade follows over its duration.
///
/// Every case maps a normalized position `t` in 0...1 to a gain in 0...1 for a
/// **rising** fade. Fade-outs reuse the same functions mirrored, so a fade-in
/// and fade-out of the same curve are symmetric.
///
/// Worth knowing when picking one: loudness perception is roughly logarithmic,
/// so a linear gain ramp does *not* sound like a steady fade — it seems to rush
/// at the quiet end. `.equalPower` and `.exponential` sound more even to the
/// ear even though their numbers look less even on paper.
enum FadeCurve: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear
    case smooth
    case exponential
    case logarithmic
    case equalPower

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear:       "Linear"
        case .smooth:       "S-Curve"
        case .exponential:  "Exponential"
        case .logarithmic:  "Logarithmic"
        case .equalPower:   "Equal Power"
        }
    }

    /// One line on what it sounds like, not what it looks like.
    var explanation: String {
        switch self {
        case .linear:
            "Volume rises at a constant rate. Simple, but tends to sound like it rushes at the quiet end."
        case .smooth:
            "Eases in and out at both ends. The gentlest option, good for long fades."
        case .exponential:
            "Stays quiet, then climbs quickly. Close to how the ear hears a steady fade."
        case .logarithmic:
            "Jumps up quickly, then levels off. Gets the track audible fast."
        case .equalPower:
            "Holds steady perceived loudness throughout. The usual choice for crossfades."
        }
    }

    /// Steepness for the exponential and logarithmic shapes. Higher is more
    /// dramatic; 4 is pronounced without being extreme.
    private static let curvature: Double = 4

    /// Gain for a **rising** fade at normalized position `t`.
    func gain(at t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .smooth:
            // Smoothstep: zero slope at both ends.
            return t * t * (3 - 2 * t)
        case .exponential:
            return (exp(Self.curvature * t) - 1) / (exp(Self.curvature) - 1)
        case .logarithmic:
            return log(1 + Self.curvature * t) / log(1 + Self.curvature)
        case .equalPower:
            // sin sweep keeps power, not amplitude, constant against its
            // cos-shaped counterpart.
            return sin(t * .pi / 2)
        }
    }

    /// Gain for a **falling** fade — the rising curve mirrored, so a fade-out
    /// is the visual and audible reverse of the matching fade-in.
    func fallingGain(at t: Double) -> Double {
        gain(at: 1 - min(max(t, 0), 1))
    }
}

/// How a clip's volume behaves from its first sample to its last.
///
/// Kept separate from storage so the visualization, the player and the tests
/// all read the same maths.
struct FadeEnvelope: Equatable {
    var fadeInCurve: FadeCurve = .smooth
    var fadeInDuration: TimeInterval = 0
    var fadeOutCurve: FadeCurve = .smooth
    var fadeOutDuration: TimeInterval = 0

    static let none = FadeEnvelope(fadeInDuration: 0, fadeOutDuration: 0)

    var isActive: Bool { fadeInDuration > 0 || fadeOutDuration > 0 }

    /// Fade lengths actually used for a clip of `clipDuration`.
    ///
    /// Two 5-second fades don't fit in a 6-second clip, so when they overlap
    /// both are scaled down proportionally rather than one silently winning.
    func resolvedDurations(clipDuration: TimeInterval) -> (fadeIn: TimeInterval, fadeOut: TimeInterval) {
        guard clipDuration > 0 else { return (0, 0) }
        let requested = fadeInDuration + fadeOutDuration
        guard requested > clipDuration, requested > 0 else {
            return (fadeInDuration, fadeOutDuration)
        }
        let scale = clipDuration / requested
        return (fadeInDuration * scale, fadeOutDuration * scale)
    }

    /// Gain at `elapsed` seconds into a clip lasting `clipDuration`.
    func gain(atElapsed elapsed: TimeInterval, clipDuration: TimeInterval) -> Double {
        guard clipDuration > 0 else { return 1 }
        let elapsed = min(max(elapsed, 0), clipDuration)
        let (fadeIn, fadeOut) = resolvedDurations(clipDuration: clipDuration)

        if fadeIn > 0, elapsed < fadeIn {
            return fadeInCurve.gain(at: elapsed / fadeIn)
        }
        let remaining = clipDuration - elapsed
        if fadeOut > 0, remaining < fadeOut {
            return fadeOutCurve.fallingGain(at: 1 - (remaining / fadeOut))
        }
        return 1
    }

    /// The envelope sampled evenly, for drawing. Returns `(time, gain)` pairs.
    func samples(clipDuration: TimeInterval, count: Int = 160) -> [(time: TimeInterval, gain: Double)] {
        guard clipDuration > 0, count > 1 else { return [] }
        return (0..<count).map { step in
            let time = clipDuration * Double(step) / Double(count - 1)
            return (time, gain(atElapsed: time, clipDuration: clipDuration))
        }
    }
}
