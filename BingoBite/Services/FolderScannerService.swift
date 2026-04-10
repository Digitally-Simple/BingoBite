import Foundation
import AVFoundation

enum FolderScannerService {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "opus"]

    static func scanForAudio(in folderURL: URL) async throws -> [Song] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )

        let audioFiles = contents.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }

        var songs: [Song] = []
        for fileURL in audioFiles {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resourceValues.fileSize ?? 0)

            let asset = AVURLAsset(url: fileURL)
            let metadata = try await asset.load(.commonMetadata)
            let duration = try await asset.load(.duration)

            let artist = await metadataValue(for: .commonKeyArtist, in: metadata)
            let title = await metadataValue(for: .commonKeyTitle, in: metadata)
            let album = await metadataValue(for: .commonKeyAlbumName, in: metadata)
            let artworkData = await artworkData(in: metadata)

            let song = Song(
                id: fileURL,
                fileName: fileURL.deletingPathExtension().lastPathComponent,
                fileSize: fileSize,
                duration: duration.seconds.isNaN ? nil : duration.seconds,
                artist: artist,
                title: title,
                album: album,
                artworkData: artworkData
            )
            songs.append(song)
        }

        return songs.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private static func metadataValue(for key: AVMetadataKey, in metadata: [AVMetadataItem]) async -> String? {
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifier(from: key))
        guard let item = items.first else { return nil }
        let value = try? await item.load(.stringValue)
        return value
    }

    private static func artworkData(in metadata: [AVMetadataItem]) async -> Data? {
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let item = items.first else { return nil }
        let value = try? await item.load(.dataValue)
        return value
    }
}

private extension AVMetadataIdentifier {
    static func commonIdentifier(from key: AVMetadataKey) -> AVMetadataIdentifier {
        switch key {
        case .commonKeyArtist: return .commonIdentifierArtist
        case .commonKeyTitle: return .commonIdentifierTitle
        case .commonKeyAlbumName: return .commonIdentifierAlbumName
        default: return AVMetadataIdentifier(rawValue: key.rawValue)
        }
    }
}
