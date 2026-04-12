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

            // AVFoundation: artwork + duration only
            let asset = AVURLAsset(url: fileURL)
            let duration = try await asset.load(.duration)
            let commonMetadata = try await asset.load(.commonMetadata)
            let artwork = await artworkData(in: commonMetadata)

            // ffprobe: all text metadata as flat key-value pairs
            let tags = probeTags(for: fileURL)

            let song = Song(
                id: fileURL,
                fileName: fileURL.deletingPathExtension().lastPathComponent,
                fileSize: fileSize,
                duration: duration.seconds.isNaN ? nil : duration.seconds,
                artist: tags["artist"],
                title: tags["title"],
                album: tags["album"],
                artworkData: artwork,
                genre: tags["genre"],
                year: extractYear(from: tags["date"]),
                comments: tags["USER_NOTES"],
                songDescription: tags["DESCRIPTION"],
                annotations: decodeJSON([AnnotationFact].self, from: tags["ANNOTATIONS"]),
                featuredArtists: decodeJSON([String].self, from: tags["FEATURED_ARTISTS"]),
                producerArtists: decodeJSON([String].self, from: tags["PRODUCERS"]),
                writerArtists: decodeJSON([String].self, from: tags["WRITERS"]),
                credits: decodeJSON([CreditEntry].self, from: tags["CREDITS"]),
                recordingLocation: tags["RECORDING_LOCATION"],
                language: tags["language"],
                releaseDate: tags["date"],
                mediaLinks: decodeJSON([MediaLink].self, from: tags["MEDIA_LINKS"]),
                songRelationships: decodeJSON([SongRelationshipEntry].self, from: tags["RELATIONSHIPS"]),
                geniusURL: tags["GENIUS_URL"].flatMap { URL(string: $0) }
            )
            songs.append(song)
        }

        return songs.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    // MARK: - ffprobe metadata

    /// Run ffmpeg to extract all tags as a flat [String: String] dictionary.
    /// Uses `-f ffmetadata` output which gives `key=value` lines.
    /// Returns empty dict on failure (non-fatal — song still gets basic info).
    private static func probeTags(for fileURL: URL) -> [String: String] {
        let proc = Process()
        proc.executableURL = BinaryLocator.ffmpeg
        proc.arguments = [
            "-i", fileURL.path,
            "-f", "ffmetadata",
            "-v", "quiet",
            "pipe:1"
        ]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return [:]
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return [:]
        }
        return parseFFMetadata(output)
    }

    /// Parse ffmetadata format: `;FFMETADATA1` header, then `key=value` lines.
    /// Handles ffmetadata escaping: `\=`, `\;`, `\#`, `\\`, `\n` (literal backslash-n for newlines).
    private static func parseFFMetadata(_ text: String) -> [String: String] {
        var tags: [String: String] = [:]
        var currentKey: String?
        var currentValue: String = ""

        for line in text.components(separatedBy: "\n") {
            // Skip the header and comment lines
            if line.hasPrefix(";") || line.hasPrefix("#") { continue }
            // Skip section headers like [CHAPTER]
            if line.hasPrefix("[") { continue }

            if let eqRange = line.range(of: "=") {
                // Save previous key-value if any
                if let key = currentKey {
                    tags[key] = unescapeFFMetadata(currentValue)
                }
                currentKey = String(line[line.startIndex..<eqRange.lowerBound])
                currentValue = String(line[eqRange.upperBound...])
            } else if currentKey != nil {
                // Continuation line (multiline value)
                currentValue += "\n" + line
            }
        }
        // Save last key-value
        if let key = currentKey {
            tags[key] = unescapeFFMetadata(currentValue)
        }
        return tags
    }

    /// Unescape ffmetadata special characters.
    private static func unescapeFFMetadata(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\=", with: "=")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\#", with: "#")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Decode a JSON-encoded string value into a typed Swift object.
    private static func decodeJSON<T: Decodable>(_ type: T.Type, from value: String?) -> T? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Extract 4-digit year from a date string like "2023-05-15".
    private static func extractYear(from date: String?) -> String? {
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    // MARK: - AVFoundation (artwork only)

    private static func artworkData(in metadata: [AVMetadataItem]) async -> Data? {
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let item = items.first else { return nil }
        return try? await item.load(.dataValue)
    }
}
