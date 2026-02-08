import Foundation
import SwiftData

enum PlaylistService {
    static func fetchAll(in context: ModelContext) -> [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.creationDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func create(name: String = "New Playlist", in context: ModelContext) -> Playlist {
        let playlist = Playlist(name: name)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    static func delete(_ playlist: Playlist, in context: ModelContext) {
        guard !BingoSetService.isPlaylistLocked(playlist, in: context) else { return }
        context.delete(playlist)
        try? context.save()
    }

    static func addSong(_ song: Song, to playlist: Playlist, in context: ModelContext) {
        guard !BingoSetService.isPlaylistLocked(playlist, in: context) else { return }
        let urlString = song.id.absoluteString
        guard !playlist.songURLStrings.contains(urlString) else { return }
        playlist.songURLStrings.append(urlString)
        try? context.save()
    }

    static func removeSong(_ song: Song, from playlist: Playlist, in context: ModelContext) {
        guard !BingoSetService.isPlaylistLocked(playlist, in: context) else { return }
        let urlString = song.id.absoluteString
        playlist.songURLStrings.removeAll { $0 == urlString }
        try? context.save()
    }
}
