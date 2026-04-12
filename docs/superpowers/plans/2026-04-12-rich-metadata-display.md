# Rich Song Metadata Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display all Genius metadata from TXXX ID3 frames in BingoBite's playlist inspector and bingo game views, so hosts can read facts about songs to the audience.

**Architecture:** Bundle ffprobe binary for reading ID3 tags as JSON. Expand the Song model with new fields. Rewrite FolderScannerService to use ffprobe for text metadata (keep AVFoundation for artwork+duration). Add metadata display sections to InspectorPaneView and BingoGameInfoView.

**Tech Stack:** Swift, SwiftUI, ffprobe (Process), AVFoundation (artwork/duration only), macOS

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `BingoBite/Models/CreditEntry.swift` | Create | Performance credit struct |
| `BingoBite/Models/MediaLink.swift` | Create | External music service link struct |
| `BingoBite/Models/SongRelationshipEntry.swift` | Create | Song relationship struct |
| `BingoBite/Models/Song.swift` | Modify | Add 10 new metadata fields |
| `BingoBite/Services/BinaryLocator.swift` | Create | Locate bundled ffprobe binary |
| `BingoBite/Services/FolderScannerService.swift` | Modify | Rewrite to use ffprobe, delete old comment parsing |
| `BingoBite/Views/InspectorPaneView.swift` | Modify | Add metadata rows + credits/relationships/media sections |
| `BingoBite/Views/BingoGameInfoView.swift` | Modify | Add metadata rows + credits/relationships/media sections |

---

### Task 1: Create supporting model structs

**Files:**
- Create: `BingoBite/Models/CreditEntry.swift`
- Create: `BingoBite/Models/MediaLink.swift`
- Create: `BingoBite/Models/SongRelationshipEntry.swift`

- [ ] **Step 1: Create CreditEntry.swift**

Create file at `BingoBite/Models/CreditEntry.swift`:

```swift
import Foundation

/// A single performance credit (e.g., "Guitar" played by ["Person A"]).
struct CreditEntry: Codable, Hashable {
    let role: String
    let artists: [String]
}
```

- [ ] **Step 2: Create MediaLink.swift**

Create file at `BingoBite/Models/MediaLink.swift`:

```swift
import Foundation

/// A link to an external music service (Spotify, Apple Music, etc.).
struct MediaLink: Codable, Hashable {
    let provider: String
    let url: URL
}
```

- [ ] **Step 3: Create SongRelationshipEntry.swift**

Create file at `BingoBite/Models/SongRelationshipEntry.swift`:

```swift
import Foundation

/// A song relationship entry (samples, sampled_in, cover_of, etc.).
struct SongRelationshipEntry: Codable, Hashable {
    let type: String
    let title: String
    let artist: String
}
```

- [ ] **Step 4: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Models/CreditEntry.swift" "BingoBite/Models/MediaLink.swift" "BingoBite/Models/SongRelationshipEntry.swift" && git commit -m "feat: add CreditEntry, MediaLink, SongRelationshipEntry model structs"
```

---

### Task 2: Expand Song model with new metadata fields

**Files:**
- Modify: `BingoBite/Models/Song.swift`

- [ ] **Step 1: Add new fields to Song**

Add these properties after the existing `annotations` field (after line 19 in Song.swift):

```swift
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
```

- [ ] **Step 2: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Models/Song.swift" && git commit -m "feat: add rich metadata fields to Song model"
```

---

### Task 3: Create BinaryLocator for ffprobe

**Files:**
- Create: `BingoBite/Services/BinaryLocator.swift`

- [ ] **Step 1: Create BinaryLocator.swift**

Create file at `BingoBite/Services/BinaryLocator.swift`:

```swift
import Foundation

/// Resolves the bundled `ffprobe` binary shipped inside the app's
/// `Contents/Resources/bin` directory.
enum BinaryLocator {
    static let ffprobe: URL = locate("ffprobe")

    private static func locate(_ name: String) -> URL {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "bin"
        ) else {
            fatalError("Bundled binary missing: \(name). Add ffprobe to Resources/bin and ensure the 'Copy & Sign' build phase runs.")
        }
        return url
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (BinaryLocator is never called yet, so the fatalError won't trigger)

- [ ] **Step 3: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Services/BinaryLocator.swift" && git commit -m "feat: add BinaryLocator for bundled ffprobe"
```

---

### Task 4: Rewrite FolderScannerService to use ffprobe

**Files:**
- Modify: `BingoBite/Services/FolderScannerService.swift`

This is the largest task. The file is currently 302 lines. We will:
1. Replace the scan loop to use ffprobe for text metadata
2. Add a `probeTags` method that shells out to ffprobe
3. Add JSON decoding helpers
4. Delete all old comment-parsing code
5. Keep only `artworkData` from AVFoundation

- [ ] **Step 1: Replace the scanForAudio method body**

Replace the entire `scanForAudio` method (lines 7-58) with:

```swift
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
```

- [ ] **Step 2: Add probeTags method**

Replace the old `metadataValue`, `genreValue`, `yearValue`, `commentValue` methods (lines 62-140) and the comment-parsing code (lines 142-283) with these new methods:

```swift
    // MARK: - ffprobe metadata

    /// Run ffprobe to extract all tags as a flat [String: String] dictionary.
    /// Returns empty dict on failure (non-fatal — song still gets basic info).
    private static func probeTags(for fileURL: URL) -> [String: String] {
        let proc = Process()
        proc.executableURL = BinaryLocator.ffprobe
        proc.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_entries", "format_tags",
            fileURL.path
        ]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return [:]
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [:] }

        struct FFProbeOutput: Decodable {
            struct Format: Decodable {
                let tags: [String: String]?
            }
            let format: Format?
        }

        guard let output = try? JSONDecoder().decode(FFProbeOutput.self, from: data) else {
            return [:]
        }
        return output.format?.tags ?? [:]
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
```

- [ ] **Step 3: Delete old helper code**

Delete the following from the bottom of the file:
- The `AVMetadataIdentifier` extension (lines 286-294)
- The `String.trimmedOrNil` extension (lines 297-301)

These were only used by the old comment-parsing code.

- [ ] **Step 4: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Services/FolderScannerService.swift" && git commit -m "feat: rewrite FolderScannerService to use ffprobe for metadata, delete old comment parsing"
```

---

### Task 5: Update InspectorPaneView with new metadata and sections

**Files:**
- Modify: `BingoBite/Views/InspectorPaneView.swift`

- [ ] **Step 1: Add new rows to metadataSection**

In the `metadataSection` method (around line 324), add new conditional rows after the existing File row and before the sound byte rows. Insert after line 345 (`metadataRow(label: "File", value: song.fileName)`):

```swift
                if let featured = song.featuredArtists, !featured.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Featured", value: featured.joined(separator: ", "))
                }
                if let producers = song.producerArtists, !producers.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Producers", value: producers.joined(separator: ", "))
                }
                if let writers = song.writerArtists, !writers.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Writers", value: writers.joined(separator: ", "))
                }
                if let language = song.language, !language.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Language", value: language)
                }
                if let location = song.recordingLocation, !location.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Recorded", value: location)
                }
                if let releaseDate = song.releaseDate, !releaseDate.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Released", value: releaseDate)
                }
```

- [ ] **Step 2: Add new sections to songDetail**

In the `songDetail` method (around line 26), add new sections after the `songFactsSection` block. After line 47 (`songFactsSection(song)`), add:

```swift
                if hasCredits(song) {
                    Divider()
                        .padding(.horizontal)

                    creditsSection(song)
                }

                if hasRelationships(song) {
                    Divider()
                        .padding(.horizontal)

                    relationshipsSection(song)
                }

                if hasMediaLinks(song) {
                    Divider()
                        .padding(.horizontal)

                    mediaLinksSection(song)
                }
```

- [ ] **Step 3: Add creditsSection method**

Add after the `songFactsSection` method:

```swift
    // MARK: - Credits Section

    private func hasCredits(_ song: Song) -> Bool {
        guard let credits = song.credits else { return false }
        return !credits.isEmpty
    }

    @ViewBuilder
    private func creditsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            DisclosureGroup("Performance Credits (\(song.credits?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.credits ?? []).enumerated()), id: \.offset) { _, credit in
                        HStack(alignment: .top, spacing: 6) {
                            Text(credit.role + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text(credit.artists.joined(separator: ", "))
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
```

- [ ] **Step 4: Add relationshipsSection method**

```swift
    // MARK: - Song Relationships Section

    private func hasRelationships(_ song: Song) -> Bool {
        guard let relationships = song.songRelationships else { return false }
        return !relationships.isEmpty
    }

    @ViewBuilder
    private func relationshipsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Relationships")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            DisclosureGroup("Connections (\(song.songRelationships?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.songRelationships ?? []).enumerated()), id: \.offset) { _, rel in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.formatRelationshipType(rel.type) + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text("\"\(rel.title)\" by \(rel.artist)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private static func formatRelationshipType(_ type: String) -> String {
        switch type {
        case "samples":           "Samples"
        case "sampled_in":        "Sampled in"
        case "interpolates":      "Interpolates"
        case "interpolated_by":   "Interpolated by"
        case "cover_of":          "Cover of"
        case "covered_by":        "Covered by"
        case "remix_of":          "Remix of"
        case "remixed_by":        "Remixed by"
        case "live_version_of":   "Live version of"
        case "performed_live_as": "Performed live as"
        default:                  type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
```

- [ ] **Step 5: Add mediaLinksSection method**

```swift
    // MARK: - Media Links Section

    private func hasMediaLinks(_ song: Song) -> Bool {
        let hasLinks = song.mediaLinks != nil && !song.mediaLinks!.isEmpty
        let hasGenius = song.geniusURL != nil
        return hasLinks || hasGenius
    }

    @ViewBuilder
    private func mediaLinksSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                if let links = song.mediaLinks, !links.isEmpty {
                    WrappingHStack(spacing: 8) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            Link(destination: link.url) {
                                HStack(spacing: 4) {
                                    Image(systemName: Self.iconForProvider(link.provider))
                                    Text(Self.displayNameForProvider(link.provider))
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                if let geniusURL = song.geniusURL {
                    Link(destination: geniusURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on Genius")
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private static func iconForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "arrow.up.right.square"
        case "apple_music":  "arrow.up.right.square"
        case "youtube":      "play.rectangle"
        case "soundcloud":   "arrow.up.right.square"
        default:             "link"
        }
    }

    private static func displayNameForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "Spotify"
        case "apple_music":  "Apple Music"
        case "youtube":      "YouTube"
        case "soundcloud":   "SoundCloud"
        default:             provider.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
```

- [ ] **Step 6: Add WrappingHStack layout helper**

Add at the bottom of the file (after the last closing brace):

```swift
// MARK: - Flow layout for media link pills

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
```

- [ ] **Step 7: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Views/InspectorPaneView.swift" && git commit -m "feat: add credits, relationships, and media links sections to inspector pane"
```

---

### Task 6: Update BingoGameInfoView with new metadata and sections

**Files:**
- Modify: `BingoBite/Views/BingoGameInfoView.swift`

- [ ] **Step 1: Add new rows to metadataSection**

In the `metadataSection` method (around line 283), add new conditional rows after the existing File row. Insert after line 304 (`metadataGridRow(label: "File", value: song.fileName)`):

```swift
                if let featured = song.featuredArtists, !featured.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Featured", value: featured.joined(separator: ", "))
                }
                if let producers = song.producerArtists, !producers.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Producers", value: producers.joined(separator: ", "))
                }
                if let writers = song.writerArtists, !writers.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Writers", value: writers.joined(separator: ", "))
                }
                if let language = song.language, !language.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Language", value: language)
                }
                if let location = song.recordingLocation, !location.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Recorded", value: location)
                }
                if let releaseDate = song.releaseDate, !releaseDate.isEmpty {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Released", value: releaseDate)
                }
```

- [ ] **Step 2: Add new sections to songDetail**

In the `songDetail` method (around line 28), add new sections after the `songFactsSection` block. After line 48 (`songFactsSection(song)`), add:

```swift
                if hasCredits(song) {
                    Divider()
                        .padding(.horizontal, 24)

                    creditsSection(song)
                }

                if hasRelationships(song) {
                    Divider()
                        .padding(.horizontal, 24)

                    relationshipsSection(song)
                }

                if hasMediaLinks(song) {
                    Divider()
                        .padding(.horizontal, 24)

                    mediaLinksSection(song)
                }
```

- [ ] **Step 3: Add creditsSection method**

Add after the `songFactsSection` method:

```swift
    // MARK: - Credits Section

    private func hasCredits(_ song: Song) -> Bool {
        guard let credits = song.credits else { return false }
        return !credits.isEmpty
    }

    @ViewBuilder
    private func creditsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            DisclosureGroup("Performance Credits (\(song.credits?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.credits ?? []).enumerated()), id: \.offset) { _, credit in
                        HStack(alignment: .top, spacing: 6) {
                            Text(credit.role + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text(credit.artists.joined(separator: ", "))
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
```

- [ ] **Step 4: Add relationshipsSection method**

```swift
    // MARK: - Song Relationships Section

    private func hasRelationships(_ song: Song) -> Bool {
        guard let relationships = song.songRelationships else { return false }
        return !relationships.isEmpty
    }

    @ViewBuilder
    private func relationshipsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Relationships")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            DisclosureGroup("Connections (\(song.songRelationships?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.songRelationships ?? []).enumerated()), id: \.offset) { _, rel in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.formatRelationshipType(rel.type) + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text("\"\(rel.title)\" by \(rel.artist)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private static func formatRelationshipType(_ type: String) -> String {
        switch type {
        case "samples":           "Samples"
        case "sampled_in":        "Sampled in"
        case "interpolates":      "Interpolates"
        case "interpolated_by":   "Interpolated by"
        case "cover_of":          "Cover of"
        case "covered_by":        "Covered by"
        case "remix_of":          "Remix of"
        case "remixed_by":        "Remixed by"
        case "live_version_of":   "Live version of"
        case "performed_live_as": "Performed live as"
        default:                  type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
```

- [ ] **Step 5: Add mediaLinksSection method**

```swift
    // MARK: - Media Links Section

    private func hasMediaLinks(_ song: Song) -> Bool {
        let hasLinks = song.mediaLinks != nil && !song.mediaLinks!.isEmpty
        let hasGenius = song.geniusURL != nil
        return hasLinks || hasGenius
    }

    @ViewBuilder
    private func mediaLinksSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                if let links = song.mediaLinks, !links.isEmpty {
                    WrappingHStack(spacing: 8) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            Link(destination: link.url) {
                                HStack(spacing: 4) {
                                    Image(systemName: Self.iconForProvider(link.provider))
                                    Text(Self.displayNameForProvider(link.provider))
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                if let geniusURL = song.geniusURL {
                    Link(destination: geniusURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on Genius")
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private static func iconForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "arrow.up.right.square"
        case "apple_music":  "arrow.up.right.square"
        case "youtube":      "play.rectangle"
        case "soundcloud":   "arrow.up.right.square"
        default:             "link"
        }
    }

    private static func displayNameForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "Spotify"
        case "apple_music":  "Apple Music"
        case "youtube":      "YouTube"
        case "soundcloud":   "SoundCloud"
        default:             provider.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
```

- [ ] **Step 6: Add WrappingHStack layout helper**

Add at the bottom of the file:

```swift
// MARK: - Flow layout for media link pills

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
```

- [ ] **Step 7: Build to verify**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add "BingoBite/Views/BingoGameInfoView.swift" && git commit -m "feat: add credits, relationships, and media links sections to bingo game info view"
```

---

### Task 7: End-to-end verification

- [ ] **Step 1: Full clean build**

Run: `cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && xcodebuild -scheme BingoBite -destination 'platform=macOS' clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual smoke test**

Prerequisites: The user must have added the `ffprobe` binary to `BingoBite/Resources/bin/` in the Xcode project with a "Copy & Sign" build phase.

1. Launch BingoBite
2. Open a playlist that contains MP3s enriched by Music Downloader (with the new TXXX frames)
3. Select a track — verify the inspector pane shows:
   - New metadata rows (Featured, Producers, Writers, Language, Recorded, Released)
   - Credits disclosure group
   - Song Relationships disclosure group
   - Media Links pills
   - Genius URL link
4. Start a bingo game from that playlist
5. Navigate to the Info tab — verify the same metadata sections appear
6. Verify songs WITHOUT enrichment still display correctly (just basic title/artist/album)

- [ ] **Step 3: Final commit (if any fixups needed)**

```bash
cd "/Users/austinlackey/Documents/Digitally-Simple-Local/BingoBite" && git add -A && git commit -m "fix: address issues found during smoke testing"
```
