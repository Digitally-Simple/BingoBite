import Foundation
import SwiftData

enum SongMetadataService {
    static func fetch(for song: Song, in context: ModelContext) -> SongMetadataOverride? {
        let urlString = song.id.absoluteString
        let descriptor = FetchDescriptor<SongMetadataOverride>(
            predicate: #Predicate { $0.songURLString == urlString }
        )
        return try? context.fetch(descriptor).first
    }

    static func fetchAll(in context: ModelContext) -> [String: SongMetadataOverride] {
        let descriptor = FetchDescriptor<SongMetadataOverride>()
        let all = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: all.map { ($0.songURLString, $0) })
    }

    static func save(
        for song: Song,
        title: String?,
        artist: String?,
        album: String?,
        artworkData: Data?,
        genre: String? = nil,
        year: String? = nil,
        comments: String? = nil,
        in context: ModelContext
    ) {
        if let existing = fetch(for: song, in: context) {
            existing.title = title
            existing.artist = artist
            existing.album = album
            existing.artworkData = artworkData
            existing.genre = genre
            existing.year = year
            existing.comments = comments
        } else {
            let override = SongMetadataOverride(
                songURLString: song.id.absoluteString,
                title: title,
                artist: artist,
                album: album,
                artworkData: artworkData,
                genre: genre,
                year: year,
                comments: comments
            )
            context.insert(override)
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
