import Foundation
import SwiftData

enum SoundByteService {
    static func fetch(for song: Song, in context: ModelContext) -> SoundByte? {
        let urlString = song.id.absoluteString
        let descriptor = FetchDescriptor<SoundByte>(
            predicate: #Predicate { $0.songURLString == urlString }
        )
        return try? context.fetch(descriptor).first
    }

    static func save(for song: Song, startTime: TimeInterval, endTime: TimeInterval, in context: ModelContext) {
        let urlString = song.id.absoluteString
        if let existing = fetch(for: song, in: context) {
            existing.startTime = startTime
            existing.endTime = endTime
        } else {
            let soundByte = SoundByte(songURLString: urlString, startTime: startTime, endTime: endTime)
            context.insert(soundByte)
        }
        try? context.save()
    }

    static func remove(for song: Song, in context: ModelContext) {
        if let existing = fetch(for: song, in: context) {
            context.delete(existing)
            try? context.save()
        }
    }
}
