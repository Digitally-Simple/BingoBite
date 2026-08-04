import Foundation
import AVFoundation

enum FolderScannerService {
    /// Opus needs ffmpeg to read and AVAudioPlayer can't play it, so it is
    /// macOS-only.
    static let supportedExtensions: Set<String> = {
        #if os(macOS)
        ["mp3", "m4a", "flac", "wav", "opus"]
        #else
        ["mp3", "m4a", "flac", "wav"]
        #endif
    }()

    /// - Parameter recursive: walks subfolders too. Off by default so the
    ///   existing per-playlist folder pickers behave exactly as before; the
    ///   master library turns it on.
    static func scanForAudio(in folderURL: URL, recursive: Bool = false) async throws -> [Song] {
        let audioFiles = try audioFileURLs(in: folderURL, recursive: recursive)

        var songs: [Song] = []
        for fileURL in audioFiles {
            if let song = try await scanFile(at: fileURL, under: folderURL) {
                songs.append(song)
            }
        }

        return songs.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    /// Reads one file. Split out of `scanForAudio` so the library index can
    /// re-read a single changed file without walking its whole directory —
    /// doing that per file made a rescan quadratic.
    ///
    /// - Parameter root: the folder `relativePath` is measured from.
    static func scanFile(at fileURL: URL, under root: URL) async throws -> Song? {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)

        // AVFoundation: artwork + duration only
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let commonMetadata = try await asset.load(.commonMetadata)
        var artwork = await artworkData(in: commonMetadata)

        // Text metadata as flat key-value pairs: ffmpeg on macOS, native
        // container parsing on iOS (no process spawning there).
        #if os(macOS)
        let tags = probeTags(for: fileURL)
        #else
        let parsed = AudioTagReader.read(url: fileURL)
        let tags = parsed.tags
        artwork = artwork ?? parsed.artwork
        #endif

        return Song(
                id: fileURL,
                fileName: fileURL.deletingPathExtension().lastPathComponent,
                fileSize: fileSize,
                duration: duration.seconds.isNaN ? nil : duration.seconds,
                artist: tags["artist"],
                title: tags["title"],
                album: tags["album"],
                artworkData: artwork,
                // Identity frames written by Music Downloader. Absent for music
                // a customer brought themselves, which is the normal case.
                uid: tag(tags, SongUID.uidKey),
                relativePath: relativePath(of: fileURL, under: root),
                geniusID: tag(tags, SongUID.geniusIDKey).flatMap(Int.init),
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
    }

    // MARK: - Enumeration

    /// Every supported audio file under `folderURL`, sorted for a stable order.
    static func audioFileURLs(in folderURL: URL, recursive: Bool) throws -> [URL] {
        let fileManager = FileManager.default

        guard recursive else {
            let contents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )
            return contents
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.path < $1.path }
        }

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegular else { continue }
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Path of `url` relative to `root`, or just the file name when it isn't
    /// under `root` at all.
    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = String(filePath.dropFirst(rootPath.count))
        return relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Case-insensitive tag lookup.
    ///
    /// ffmpeg doesn't guarantee the case it writes Vorbis comment keys in, and
    /// `AudioTagReader` passes unknown keys through verbatim, so a bare
    /// subscript silently misses the identity frames on flac and m4a.
    static func tag(_ tags: [String: String], _ key: String) -> String? {
        if let exact = tags[key], !exact.isEmpty { return exact }
        let lowered = key.lowercased()
        for (candidate, value) in tags where candidate.lowercased() == lowered {
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - ffprobe metadata (macOS only — iOS cannot spawn processes)

    #if os(macOS)
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
    #endif

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
