# Missing Track Detection & Replacement

## Problem

When a playlist is created, the app freezes the song list as absolute URL strings in `Playlist.songURLStrings`. Bingo cards reference songs by 1-based index into this array. If a track file is renamed or deleted from the source folder, the app silently drops it from the loaded song list with no warning. The user has no way to know which track is missing or fix it, and bingo cards referencing that index become broken.

## Solution

Detect missing tracks at load time, warn the user, and let them replace each missing track with another file from the same source folder.

## Detection

### Current Behavior

`PlaylistService.loadSongs()` scans the source folder via `FolderScannerService.scanForAudio()`, then filters scanned songs to those whose `URL.absoluteString` matches a stored URL in `songURLStrings`. Missing songs are silently excluded.

### New Behavior

After scanning, compare all stored `songURLStrings` against the scanned file URLs. Produce two outputs:

1. **Matched songs** — songs that were found, as today
2. **Missing entries** — a `[Int: String]` dictionary mapping each missing song's index (position in `songURLStrings`) to its original URL string

Return both to the caller so the view layer can display warnings and offer replacements.

## UI

### Banner Warning

When one or more tracks are missing, display an orange/yellow warning banner above the song table:

> **"N of M tracks are missing.** These files may have been renamed or deleted. Replace them to keep your bingo cards complete."

- Appears only when there are missing tracks
- Disappears once all missing tracks are replaced

### Inline Row Warning

Missing tracks appear in their correct index position within the song table:

- Warning icon and visually distinct row styling (muted or highlighted)
- Display the original filename extracted from the stored URL string
- A "Replace" button in the row

### Replacement Sheet

Clicking "Replace" on a missing track row opens a custom sheet showing:

- All audio files in the source folder that are **not already in `songURLStrings`** (prevents duplicates)
- Each file displayed with its embedded metadata: title, artist, duration
- Artwork thumbnail if available
- Selecting a file confirms the replacement

## Replacement Logic

When the user selects a replacement track:

1. **Swap the URL** — Replace the old URL string at the missing index in `songURLStrings` with the new file's `URL.absoluteString`
2. **Delete old SongMetadataOverride** — Remove any `SongMetadataOverride` record keyed to the old URL string
3. **Delete old SoundByte** — Remove any `SoundByte` record keyed to the old URL string
4. **Reload** — The new track loads with its own embedded metadata
5. **Cards untouched** — Bingo card grids use indices, so they remain valid. The index now points to the replacement song.

## Persistence

The replacement is persisted by updating `Playlist.songURLStrings` in SwiftData. No migration is needed — the array is the same size, just with a different URL at that index.

## Scope Boundaries

- **No auto-detection of renames** — Renames are treated as "missing + new unassigned file." The user manually replaces.
- **No cross-folder browsing** — Replacement tracks must come from the same source folder.
- **No bulk replace** — Each missing track is replaced individually via its inline button.
- **No bingo card regeneration** — Cards are stable; only the URL mapping changes.

## Affected Files

### Models
- No model changes needed. `Playlist.songURLStrings` is already a mutable array.

### Services
- **PlaylistService** — Modify `loadSongs()` to return missing track info alongside loaded songs. Add a `replaceTrack(in:atIndex:with:)` method that swaps the URL and cleans up old overrides/SoundBytes.

### Views
- **PlaylistDetailView** — Add banner warning, modify song table to show missing track rows with replace buttons, add replacement sheet presentation.
- **New: TrackReplacementSheet** — A sheet view listing available unassigned audio files from the source folder for selection.
