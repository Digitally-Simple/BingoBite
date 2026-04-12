# Rich Song Metadata Display — Design Spec

## Overview

Display all Genius metadata embedded by Music Downloader (via TXXX ID3 frames) in BingoBite. Metadata is shown in the playlist inspector pane and during bingo game playback, so hosts can read facts about songs to the audience.

## Decisions

- Read TXXX frames via **bundled ffprobe** (JSON output), not AVFoundation
- Keep AVFoundation only for artwork bytes and duration
- **Replace** old comment-parsing code entirely (no fallback for old format)
- Full metadata display in both InspectorPaneView and BingoGameInfoView
- New supporting structs match Music Downloader's types exactly
- User adds ffprobe binary to Xcode project in `Resources/bin`

## Section 1: Song Model Expansion

New fields on `Song`:

```swift
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

New supporting Codable structs (same as Music Downloader):
- `CreditEntry` — `{ role: String, artists: [String] }`
- `MediaLink` — `{ provider: String, url: URL }`
- `SongRelationshipEntry` — `{ type: String, title: String, artist: String }`

Existing `AnnotationFact` stays unchanged.

Field mapping from TXXX frames:
- `comments` <- `USER_NOTES`
- `songDescription` <- `DESCRIPTION`
- `annotations` <- `ANNOTATIONS` (JSON decoded)
- `featuredArtists` <- `FEATURED_ARTISTS` (JSON decoded)
- `producerArtists` <- `PRODUCERS` (JSON decoded)
- `writerArtists` <- `WRITERS` (JSON decoded)
- `credits` <- `CREDITS` (JSON decoded)
- `recordingLocation` <- `RECORDING_LOCATION`
- `mediaLinks` <- `MEDIA_LINKS` (JSON decoded)
- `songRelationships` <- `RELATIONSHIPS` (JSON decoded)
- `geniusURL` <- `GENIUS_URL`

## Section 2: FolderScannerService Rewrite

### Keep from AVFoundation
- Artwork bytes (binary data)
- Duration (`AVURLAsset.load(.duration)`)

### Replace with ffprobe
One `ffprobe -v quiet -print_format json -show_entries format_tags` call per file. Returns all tags as a flat JSON object.

Standard tags: `title`, `artist`, `album`, `date`, `genre`, `album_artist`, `composer`, `language`
TXXX keys (uppercase): `FEATURED_ARTISTS`, `PRODUCERS`, `WRITERS`, `CREDITS`, `RECORDING_LOCATION`, `MEDIA_LINKS`, `RELATIONSHIPS`, `GENIUS_URL`, `DESCRIPTION`, `ANNOTATIONS`, `USER_NOTES`

### Delete entirely
- `parseComment` method
- `parseAnnotations` method
- `ParsedComment` struct
- `commentValue` method
- `genreValue` method
- `yearValue` method
- `metadataValue` method (only keep artwork helper)

### New files
- `Services/BinaryLocator.swift` — enum pointing to bundled ffprobe in `Resources/bin`

## Section 3: InspectorPaneView (Playlist Tab)

### Metadata section
New rows after existing ones (Title, Artist, Album, Duration, Size, File), shown only when non-nil/non-empty:

```
Featured     Artist B, Artist C
Producers    Metro Boomin, Wheezy
Writers      Writer A, Writer B
Language     en
Recorded     Conway Studios, LA
Released     2023-05-15
```

### New sections after Song Facts

**Credits** — `DisclosureGroup("Performance Credits")` listing role: artists pairs.

**Song Relationships** — `DisclosureGroup("Connections")` listing type: "title" by artist, with `formatRelationshipType` helper converting snake_case to readable labels.

**Media Links** — Row of clickable `Link` pills for each provider (Spotify, Apple Music, YouTube, etc.).

**Genius URL** — Clickable link if available.

Existing Song Facts section (description, annotations) stays as-is.

## Section 4: BingoGameInfoView (Game Tab)

Same metadata display as inspector, adapted to game info layout (24px horizontal padding, Grid-based rows).

### Metadata section
Same new rows as inspector (Featured, Producers, Writers, Language, Recorded, Released).

### New sections
Same as inspector: Credits disclosure group, Song Relationships disclosure group, Media Links pills, Genius URL link. Placed after existing Song Facts section.

Existing `songFactsSection` and `annotationFactView` methods stay as-is.

## Files Modified

1. `Models/Song.swift` — Add new metadata fields
2. `Models/CreditEntry.swift` — New file, Codable struct
3. `Models/MediaLink.swift` — New file, Codable struct
4. `Models/SongRelationshipEntry.swift` — New file, Codable struct
5. `Services/BinaryLocator.swift` — New file, ffprobe locator
6. `Services/FolderScannerService.swift` — Rewrite to use ffprobe, delete old comment parsing
7. `Views/InspectorPaneView.swift` — Add new metadata rows, credits/relationships/media sections
8. `Views/BingoGameInfoView.swift` — Add new metadata rows, credits/relationships/media sections
