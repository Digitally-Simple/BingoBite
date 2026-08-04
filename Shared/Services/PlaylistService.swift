import Foundation
import SwiftData

enum PlaylistServiceError: LocalizedError {
    case notEnoughSongs(have: Int, need: Int)
    case invalidCardCount
    case bookmarkAccessDenied

    var errorDescription: String? {
        switch self {
        case .notEnoughSongs(let have, let need):
            return "This playlist needs at least \(need) songs but only \(have) are included."
        case .invalidCardCount:
            return "Number of cards must be at least 1."
        case .bookmarkAccessDenied:
            return "Unable to access the playlist's source folder. It may have been moved or deleted."
        }
    }
}

enum PlaylistService {
    struct MissingTrack: Identifiable {
        let index: Int
        let originalURLString: String
        var id: Int { index }

        var originalFileName: String {
            guard let url = URL(string: originalURLString) else {
                return originalURLString
            }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    // MARK: - Fetch

    /// Set codes already in use, so a new deck never collides with one that
    /// might be sitting in the same pile of printed cards.
    static func usedSetIDs(in context: ModelContext) -> Set<String> {
        Set(fetchAll(in: context).map(\.setID).filter { !$0.isEmpty })
    }

    static func fetchAll(in context: ModelContext) -> [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.creationDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - New folder-based create (one-shot)

    /// Creates a playlist from a folder in one shot: freezes the song list,
    /// generates cards, persists the security-scoped bookmark, saves.
    /// The caller must hold active security-scoped access to `folderURL`
    /// when calling this method (the bookmark is created inside).
    @MainActor
    static func create(
        folderURL: URL,
        includedSongs: [Song],
        name: String,
        description: String,
        numberOfCards: Int,
        hasFreeSpace: Bool,
        in context: ModelContext
    ) throws -> Playlist {
        let required = hasFreeSpace ? 24 : 25
        guard includedSongs.count >= required else {
            throw PlaylistServiceError.notEnoughSongs(have: includedSongs.count, need: required)
        }
        guard numberOfCards >= 1 else {
            throw PlaylistServiceError.invalidCardCount
        }

        let bookmarkData = try BookmarkService.createBookmark(for: folderURL)
        // Stable keys, not absolute URLs: the UID when the file carries one,
        // the relative path otherwise. Card grids index into this array
        // 1-based, so its order and length are load-bearing from here on.
        let songKeys = includedSongs.map(\.stableKey)
        let grids = CardGenerator.generate(
            numberOfCards: numberOfCards,
            numberOfSongs: songKeys.count,
            hasFreeSpace: hasFreeSpace
        )
        let cardsData = CardGenerator.encode(grids)
        let coverArtData = includedSongs.first(where: { $0.artworkData != nil })?.artworkData
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? folderURL.lastPathComponent
            : name

        let playlist = Playlist(
            name: finalName,
            descriptionText: description,
            folderPath: folderURL.path,
            bookmarkData: bookmarkData,
            songKeys: songKeys,
            numberOfCards: numberOfCards,
            hasFreeSpace: hasFreeSpace,
            cardsData: cardsData,
            coverArtData: coverArtData
        )
        playlist.setID = Playlist.generateSetID(avoiding: usedSetIDs(in: context))
        context.insert(playlist)
        try context.save()
        return playlist
    }

    // MARK: - Duplicate

    /// Copies a playlist under a new name.
    ///
    /// Regenerates the card grids rather than copying them — two playlists
    /// sharing identical cards would make every game of one a replay of the
    /// other. The song list and its order are preserved exactly.
    @MainActor
    @discardableResult
    static func duplicate(
        _ playlist: Playlist,
        name: String,
        in context: ModelContext
    ) throws -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "\(playlist.name) copy" : trimmed

        let grids = CardGenerator.generate(
            numberOfCards: playlist.numberOfCards,
            numberOfSongs: playlist.songKeys.count,
            hasFreeSpace: playlist.hasFreeSpace
        )

        let copy = Playlist(
            name: finalName,
            descriptionText: playlist.descriptionText,
            folderPath: playlist.folderPath,
            bookmarkData: playlist.bookmarkData,
            songKeys: playlist.songKeys,
            numberOfCards: playlist.numberOfCards,
            hasFreeSpace: playlist.hasFreeSpace,
            cardsData: CardGenerator.encode(grids),
            coverArtData: playlist.coverArtData,
            cardDesignData: playlist.cardDesignData
        )
        // A duplicate is a physically different deck with different grids, so
        // it must not inherit the original's set code — that's exactly the
        // collision the codes exist to prevent.
        copy.setID = Playlist.generateSetID(avoiding: usedSetIDs(in: context))
        context.insert(copy)
        try context.save()
        return copy
    }

    // MARK: - Loading songs for an existing playlist

    /// Resolves the playlist's folder bookmark, starts security-scoped access,
    /// rescans the folder, and filters to the songs that were frozen at
    /// creation time. Caller must release the returned URL via
    /// `BookmarkService.stopAccessing(_:)` when done.
    @MainActor
    static func loadSongs(
        for playlist: Playlist,
        in context: ModelContext? = nil
    ) async throws -> (songs: [Song], missingTracks: [MissingTrack], allScanned: [Song], accessedURL: URL) {
        guard !playlist.bookmarkData.isEmpty else {
            throw PlaylistServiceError.bookmarkAccessDenied
        }
        let url = try BookmarkService.resolveBookmark(playlist.bookmarkData)
        guard BookmarkService.startAccessing(url) else {
            throw PlaylistServiceError.bookmarkAccessDenied
        }
        do {
            let scanned = try await FolderScannerService.scanForAudio(in: url)
            let index = SongIndex(scanned)

            var songs: [Song] = []
            var missingTracks: [MissingTrack] = []
            var relinked: [(Int, String)] = []

            for (position, key) in playlist.songKeys.enumerated() {
                guard let song = index.song(for: key) else {
                    missingTracks.append(MissingTrack(index: position, originalURLString: key))
                    continue
                }
                songs.append(song)

                // Resolved on a weaker rung than it was stored on — the file
                // was renamed, the folder moved, or iOS re-created the app's
                // data container. Heal it so the next load matches exactly.
                let current = song.stableKey
                if current != key {
                    relinked.append((position, current))
                }
            }

            // Heal the stored paths so the next load is an exact match. Card
            // grids index into this array by position, which is preserved.
            if let context {
                let folderMoved = playlist.folderPath != url.path
                for (position, urlString) in relinked {
                    playlist.songKeys[position] = urlString
                }
                if folderMoved {
                    playlist.folderPath = url.path
                }
                if folderMoved || !relinked.isEmpty {
                    try? context.save()
                }
            }

            return (songs, missingTracks, scanned, url)
        } catch {
            BookmarkService.stopAccessing(url)
            throw error
        }
    }

    // MARK: - Track replacement

    /// Replaces a missing track's URL at the given index in the playlist's songKeys.
    /// Deletes any SongMetadataOverride and SoundByte associated with the old URL.
    @MainActor
    static func replaceTrack(
        in playlist: Playlist,
        atIndex index: Int,
        with newSong: Song,
        in context: ModelContext
    ) {
        let oldKey = playlist.songKeys[index]

        // Replace in place — the array is positional and card grids index into
        // it, so the length must not change. Stable key, not an absolute URL.
        playlist.songKeys[index] = newSong.stableKey

        // Delete old SongMetadataOverride
        let overrideDescriptor = FetchDescriptor<SongMetadataOverride>(
            predicate: #Predicate { $0.songKey == oldKey }
        )
        if let oldOverride = try? context.fetch(overrideDescriptor).first {
            context.delete(oldOverride)
        }

        // Delete old SoundByte
        let soundByteDescriptor = FetchDescriptor<SoundByte>(
            predicate: #Predicate { $0.songKey == oldKey }
        )
        if let oldSoundByte = try? context.fetch(soundByteDescriptor).first {
            context.delete(oldSoundByte)
        }

        try? context.save()
    }

    // MARK: - Card helpers

    static func bingoCards(from playlist: Playlist) -> [BingoCard] {
        let grids = CardGenerator.decode(from: playlist.cardsData)
        return grids.enumerated().map { index, grid in
            BingoCard(id: index + 1, grid: grid)
        }
    }

    // MARK: - Delete

    static func delete(_ playlist: Playlist, in context: ModelContext) {
        context.delete(playlist)
        try? context.save()
    }

}
