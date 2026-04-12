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
        let songURLStrings = includedSongs.map { $0.id.absoluteString }
        let grids = CardGenerator.generate(
            numberOfCards: numberOfCards,
            numberOfSongs: songURLStrings.count,
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
            songURLStrings: songURLStrings,
            numberOfCards: numberOfCards,
            hasFreeSpace: hasFreeSpace,
            cardsData: cardsData,
            coverArtData: coverArtData
        )
        context.insert(playlist)
        try context.save()
        return playlist
    }

    // MARK: - Loading songs for an existing playlist

    /// Resolves the playlist's folder bookmark, starts security-scoped access,
    /// rescans the folder, and filters to the songs that were frozen at
    /// creation time. Caller must release the returned URL via
    /// `BookmarkService.stopAccessing(_:)` when done.
    @MainActor
    static func loadSongs(
        for playlist: Playlist
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
            let scannedLookup = Dictionary(uniqueKeysWithValues: scanned.map { ($0.id.absoluteString, $0) })

            var songs: [Song] = []
            var missingTracks: [MissingTrack] = []

            for (index, urlString) in playlist.songURLStrings.enumerated() {
                if let song = scannedLookup[urlString] {
                    songs.append(song)
                } else {
                    missingTracks.append(MissingTrack(index: index, originalURLString: urlString))
                }
            }

            return (songs, missingTracks, scanned, url)
        } catch {
            BookmarkService.stopAccessing(url)
            throw error
        }
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
