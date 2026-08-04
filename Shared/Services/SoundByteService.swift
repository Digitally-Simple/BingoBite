import Foundation
import SwiftData

enum SoundByteService {
    static func fetch(for song: Song, in context: ModelContext) -> SoundByte? {
        // Stable key, not the absolute URL: a renamed file keeps its trim.
        let key = song.stableKey
        let descriptor = FetchDescriptor<SoundByte>(
            predicate: #Predicate { $0.songKey == key }
        )
        return try? context.fetch(descriptor).first
    }

    static func save(for song: Song, startTime: TimeInterval, endTime: TimeInterval, in context: ModelContext) {
        let key = song.stableKey
        if let existing = fetch(for: song, in: context) {
            existing.startTime = startTime
            existing.endTime = endTime
        } else {
            let soundByte = SoundByte(songKey: key, startTime: startTime, endTime: endTime)
            context.insert(soundByte)
        }
        try? context.save()
    }

    /// Outcome of applying one trim across many songs.
    struct BatchResult {
        var applied: [Song] = []
        /// Songs shorter than the requested start — trimming them would leave
        /// nothing to play, so they're skipped rather than silently zeroed.
        var tooShort: [Song] = []
        /// Songs where the end had to be pulled back to the song's own length.
        var clamped: [Song] = []

        var isEmpty: Bool { applied.isEmpty }
    }

    /// Applies one start/end pair to every song given.
    ///
    /// Each song is clamped against its own duration: a 2:30 track asked to end
    /// at 3:00 ends at 2:30 instead, and anything shorter than the start time
    /// is left alone. Both are reported so the UI can say what happened rather
    /// than quietly producing silent clips.
    @MainActor
    @discardableResult
    static func applyBatch(
        to songs: [Song],
        startTime: TimeInterval,
        endTime: TimeInterval,
        in context: ModelContext
    ) -> BatchResult {
        var result = BatchResult()

        for song in songs {
            let songDuration = song.duration ?? 0

            // No duration means the tags couldn't be read; trust the request
            // rather than refusing to trim.
            if songDuration > 0, startTime >= songDuration {
                result.tooShort.append(song)
                continue
            }

            var resolvedEnd = endTime
            if songDuration > 0, resolvedEnd > songDuration {
                resolvedEnd = songDuration
                result.clamped.append(song)
            }

            guard resolvedEnd > startTime else {
                result.tooShort.append(song)
                continue
            }

            save(for: song, startTime: startTime, endTime: resolvedEnd, in: context)
            result.applied.append(song)
        }

        return result
    }

    /// Clears the trim on every song given.
    @MainActor
    static func removeBatch(from songs: [Song], in context: ModelContext) {
        for song in songs { remove(for: song, in: context) }
    }

    static func remove(for song: Song, in context: ModelContext) {
        if let existing = fetch(for: song, in: context) {
            context.delete(existing)
            try? context.save()
        }
    }
}
