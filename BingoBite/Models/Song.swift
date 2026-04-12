import Foundation
import AppKit

struct Song: Identifiable, Hashable {
    var id: URL
    var fileName: String
    var fileSize: Int64
    var duration: TimeInterval?
    var artist: String?
    var title: String?
    var album: String?
    var artworkData: Data?

    // Extended metadata (read from file tags written by Music Downloader)
    var genre: String?
    var year: String?
    var comments: String?
    var songDescription: String?
    var annotations: [AnnotationFact]?

    // Rich metadata from TXXX ID3 frames (written by Music Downloader)
    var featuredArtists: [String]?
    var producerArtists: [String]?
    var writerArtists: [String]?
    var credits: [CreditEntry]?
    var recordingLocation: String?
    var language: String?
    var releaseDate: String?
    var mediaLinks: [MediaLink]?
    var songRelationships: [SongRelationshipEntry]?
    var geniusURL: URL?

    private static let imageCache = NSCache<NSURL, NSImage>()

    var artworkImage: NSImage? {
        guard let data = artworkData else { return nil }
        let cacheKey = id as NSURL
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let image = NSImage(data: data) else { return nil }
        Self.imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        return fileName
    }

    var displayArtist: String {
        artist ?? "Unknown Artist"
    }

    var displayAlbum: String {
        album ?? "Unknown Album"
    }

    var sortableDuration: TimeInterval {
        duration ?? 0
    }

    var formattedDuration: String {
        guard let duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Returns a copy with override values applied. Clears the image cache if artwork changed.
    func applying(override: SongMetadataOverride) -> Song {
        var copy = self
        copy.title = override.title
        copy.artist = override.artist
        copy.album = override.album
        copy.genre = override.genre
        copy.year = override.year
        copy.comments = override.comments
        if override.artworkData != copy.artworkData {
            Self.imageCache.removeObject(forKey: id as NSURL)
            copy.artworkData = override.artworkData
        }
        return copy
    }

    static func clearCachedImage(for url: URL) {
        imageCache.removeObject(forKey: url as NSURL)
    }
}
