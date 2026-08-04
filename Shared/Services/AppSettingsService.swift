import Foundation
import SwiftData

/// Reads and writes the single `AppSettings` row.
///
/// The model has always been registered but never instantiated, so everything
/// goes through `current(in:)`, which creates the row on first use rather than
/// leaving callers to guess whether one exists.
@MainActor
enum AppSettingsService {

    @discardableResult
    static func current(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    /// The fade envelope to apply during playback.
    static func fadeEnvelope(in context: ModelContext) -> FadeEnvelope {
        current(in: context).fadeEnvelope
    }

    /// How long autoplay waits between rounds. Read at the moment the gap
    /// starts rather than cached, so a change made mid-game takes effect on the
    /// very next handoff.
    static func autoplayGap(in context: ModelContext) -> TimeInterval {
        current(in: context).autoplayGap
    }

    /// Where the fader was left, clamped in case an old row holds something odd.
    static func playbackVolume(in context: ModelContext) -> Double {
        min(max(current(in: context).playbackVolume, 0), 1)
    }

    /// Written when the host lets go of the fader rather than on every frame
    /// of the drag — a save per tick would hit the store sixty times a second.
    static func setPlaybackVolume(_ value: Double, in context: ModelContext) {
        let settings = current(in: context)
        settings.playbackVolume = min(max(value, 0), 1)
        save(in: context)
    }

    static func save(in context: ModelContext) {
        try? context.save()
    }
}
