# Missing Track Detection & Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect when playlist tracks have been renamed or deleted from the source folder, warn the user in the playlist view, and let them replace each missing track with another file from the same folder.

**Architecture:** Modify `PlaylistService.loadSongs()` to return missing track info alongside loaded songs. Add a banner and inline row warnings to `PlaylistDetailView`. Create a new `TrackReplacementSheet` view for selecting replacement files. Add a `replaceTrack` method to `PlaylistService` that swaps the URL and cleans up stale overrides/SoundBytes.

**Tech Stack:** SwiftUI, SwiftData, AVFoundation (existing stack)

---

### Task 1: Update `PlaylistService.loadSongs()` to Report Missing Tracks

**Files:**
- Modify: `BingoBite/Services/PlaylistService.swift`

- [ ] **Step 1: Add a `MissingTrack` struct and update the return type**

In `PlaylistService.swift`, add a struct to represent a missing track and change the `loadSongs` return type:

```swift
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
```

Add this inside the `PlaylistService` enum, before the `// MARK: - Fetch` line.

- [ ] **Step 2: Modify `loadSongs` to compute and return missing tracks and all scanned songs**

Replace the existing `loadSongs(for:)` method with:

```swift
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
```

- [ ] **Step 3: Build and verify compilation**

Run: `xcodebuild -project BingoBite.xcodeproj -scheme BingoBite build 2>&1 | tail -20`

Expected: Build will fail because `PlaylistDetailView` and any other callers still expect the old 2-tuple return. That's expected — we fix those in the next tasks.

- [ ] **Step 4: Commit**

```bash
git add BingoBite/Services/PlaylistService.swift
git commit -m "feat: update PlaylistService.loadSongs to report missing tracks"
```

---

### Task 2: Add `replaceTrack` and Cleanup Methods to `PlaylistService`

**Files:**
- Modify: `BingoBite/Services/PlaylistService.swift`

- [ ] **Step 1: Add `replaceTrack` method**

Add this method to the `PlaylistService` enum, after the `loadSongs` method:

```swift
// MARK: - Track replacement

/// Replaces a missing track's URL at the given index in the playlist's songURLStrings.
/// Deletes any SongMetadataOverride and SoundByte associated with the old URL.
@MainActor
static func replaceTrack(
    in playlist: Playlist,
    atIndex index: Int,
    with newSong: Song,
    in context: ModelContext
) {
    let oldURLString = playlist.songURLStrings[index]

    // Swap the URL
    playlist.songURLStrings[index] = newSong.id.absoluteString

    // Delete old SongMetadataOverride
    let overrideDescriptor = FetchDescriptor<SongMetadataOverride>(
        predicate: #Predicate { $0.songURLString == oldURLString }
    )
    if let oldOverride = try? context.fetch(overrideDescriptor).first {
        context.delete(oldOverride)
    }

    // Delete old SoundByte
    let soundByteDescriptor = FetchDescriptor<SoundByte>(
        predicate: #Predicate { $0.songURLString == oldURLString }
    )
    if let oldSoundByte = try? context.fetch(soundByteDescriptor).first {
        context.delete(oldSoundByte)
    }

    try? context.save()
}
```

- [ ] **Step 2: Build and verify compilation**

Run: `xcodebuild -project BingoBite.xcodeproj -scheme BingoBite build 2>&1 | tail -20`

Expected: Still fails due to `PlaylistDetailView` — that's fine, fixed in Task 3.

- [ ] **Step 3: Commit**

```bash
git add BingoBite/Services/PlaylistService.swift
git commit -m "feat: add replaceTrack method for missing track replacement"
```

---

### Task 3: Update `PlaylistDetailView` to Handle Missing Tracks

**Files:**
- Modify: `BingoBite/Views/PlaylistDetailView.swift`

- [ ] **Step 1: Add state properties for missing tracks**

Add these `@State` properties alongside the existing ones (after the `@State private var searchText` line):

```swift
@State private var missingTracks: [PlaylistService.MissingTrack] = []
@State private var trackToReplace: PlaylistService.MissingTrack?
```

- [ ] **Step 2: Update `loadSongs()` to capture missing tracks and all scanned songs**

Replace the existing `loadSongs()` method with:

```swift
@MainActor
private func loadSongs() async {
    isLoading = true
    loadError = nil
    missingTracks = []
    releaseAccess()
    do {
        let (loaded, missing, scanned, url) = try await PlaylistService.loadSongs(for: playlist)
        songs = loaded
        missingTracks = missing
        allScannedSongs = scanned
        accessedURL = url
        applyMetadataOverrides()
    } catch {
        loadError = error.localizedDescription
        songs = []
        missingTracks = []
        allScannedSongs = []
    }
    isLoading = false
}
```

- [ ] **Step 3: Add the missing tracks banner**

Add a `missingTracksBanner` computed property after the `sourceFolderBar` property:

```swift
// MARK: - Missing Tracks Banner

@ViewBuilder
private var missingTracksBanner: some View {
    if !missingTracks.isEmpty {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("**\(missingTracks.count) of \(playlist.songCount) tracks missing.** These files may have been renamed or deleted. Replace them to keep your bingo cards complete.")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}
```

- [ ] **Step 4: Insert the banner into the body layout**

Replace the `body` VStack content:

```swift
var body: some View {
    VStack(spacing: 0) {
        headerSection
        Divider()
        statsBar
        Divider()
        sourceFolderBar
        Divider()
        missingTracksBanner
        content
    }
    .navigationTitle(playlist.name)
    .searchable(text: $searchText, prompt: "Search songs")
    .task(id: playlist.uuid) {
        await loadSongs()
    }
    .onDisappear {
        releaseAccess()
    }
    .sheet(isPresented: $showCardDesigner) {
        CardDesignerSheet(playlist: playlist, songs: songs)
    }
    .sheet(item: $songToEdit) { song in
        SongMetadataEditorSheet(
            song: song,
            onSave: { updatedSong in
                if let idx = songs.firstIndex(where: { $0.id == updatedSong.id }) {
                    songs[idx] = updatedSong
                    if selectedSong?.id == updatedSong.id {
                        selectedSong = updatedSong
                    }
                }
            },
            onRevert: {
                Task { await loadSongs() }
            }
        )
    }
    .sheet(item: $trackToReplace) { missing in
        TrackReplacementSheet(
            missingTrack: missing,
            playlist: playlist,
            availableSongs: availableReplacementSongs,
            onReplace: { newSong in
                PlaylistService.replaceTrack(
                    in: playlist,
                    atIndex: missing.index,
                    with: newSong,
                    in: modelContext
                )
                Task { await loadSongs() }
            }
        )
    }
}
```

- [ ] **Step 5: Add `allScannedSongs` state and `availableReplacementSongs` computed property**

Add a new state property alongside the other `@State` properties (after `allScannedSongs` is needed by `availableReplacementSongs`):

```swift
@State private var allScannedSongs: [Song] = []
```

Then add the computed property after the `displayedSongs` computed property:

```swift
/// All songs found in the source folder that are NOT already in the playlist's songURLStrings.
private var availableReplacementSongs: [Song] {
    let usedURLs = Set(playlist.songURLStrings)
    return allScannedSongs.filter { !usedURLs.contains($0.id.absoluteString) }
}
```

Note: `allScannedSongs` is already populated in the `loadSongs()` method updated in Step 2, which destructures the 4-tuple from `PlaylistService.loadSongs` (updated in Task 1 to return all scanned songs).

- [ ] **Step 6: Add missing track rows below the songs table**

Replace the `content` section to include missing track rows after the table. Modify the `content` property — in the `else` branch (after the loading/error states), replace `songsTable` with:

```swift
} else {
    VStack(spacing: 0) {
        songsTable
        if !missingTracks.isEmpty {
            Divider()
            missingTracksList
        }
    }
}
```

Then add the `missingTracksList` computed property:

```swift
// MARK: - Missing Tracks List

private var missingTracksList: some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(missingTracks) { missing in
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(missing.originalFileName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Text("Track \(missing.index + 1) — File missing")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("Replace\u{2026}") {
                    trackToReplace = missing
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.05))
            Divider()
        }
    }
}
```

- [ ] **Step 7: Build and verify compilation**

Run: `xcodebuild -project BingoBite.xcodeproj -scheme BingoBite build 2>&1 | tail -20`

Expected: Build fails because `TrackReplacementSheet` doesn't exist yet. That's expected — created in Task 4.

- [ ] **Step 8: Commit**

```bash
git add BingoBite/Views/PlaylistDetailView.swift BingoBite/Services/PlaylistService.swift
git commit -m "feat: add missing track banner and inline warnings to PlaylistDetailView"
```

---

### Task 4: Create `TrackReplacementSheet`

**Files:**
- Create: `BingoBite/Views/TrackReplacementSheet.swift`

- [ ] **Step 1: Create the replacement sheet view**

Create `BingoBite/Views/TrackReplacementSheet.swift`:

```swift
import SwiftUI

struct TrackReplacementSheet: View {
    let missingTrack: PlaylistService.MissingTrack
    let playlist: Playlist
    let availableSongs: [Song]
    let onReplace: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedSongID: Song.ID?

    private var filteredSongs: [Song] {
        if searchText.isEmpty { return availableSongs }
        return availableSongs.filter { song in
            song.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            song.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            song.fileName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            songList
            Divider()
            footer
        }
        .frame(width: 500, height: 450)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Replace Missing Track")
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(missingTrack.originalFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Select a replacement from the source folder. Only tracks not already in the playlist are shown.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Search songs\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Song List

    private var songList: some View {
        List(filteredSongs, selection: $selectedSongID) { song in
            HStack(spacing: 10) {
                Group {
                    if let image = song.artworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.body)
                        .lineLimit(1)
                    Text(song.displayArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(song.formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if availableSongs.isEmpty {
                Text("No unassigned tracks in the source folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(filteredSongs.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Replace") {
                if let id = selectedSongID,
                   let song = availableSongs.first(where: { $0.id == id }) {
                    onReplace(song)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedSongID == nil)
        }
        .padding()
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

The file needs to be added to the Xcode project. Since the project uses a file-system based structure, adding the file to the correct directory should be sufficient. If the build doesn't pick it up, add it manually via Xcode or by editing `project.pbxproj`.

- [ ] **Step 3: Build and verify compilation**

Run: `xcodebuild -project BingoBite.xcodeproj -scheme BingoBite build 2>&1 | tail -20`

Expected: Build succeeds. All callers of `loadSongs` now use the updated return type, and `TrackReplacementSheet` exists.

- [ ] **Step 4: Commit**

```bash
git add BingoBite/Views/TrackReplacementSheet.swift
git commit -m "feat: add TrackReplacementSheet for replacing missing playlist tracks"
```

---

### Task 5: Fix Any Other Callers of `loadSongs`

**Files:**
- Potentially modify: any file that calls `PlaylistService.loadSongs`

- [ ] **Step 1: Search for all callers of `PlaylistService.loadSongs`**

Run: `grep -rn "PlaylistService.loadSongs" BingoBite/`

Check every call site. Each must destructure the new 4-tuple `(songs, missingTracks, allScanned, accessedURL)`. `PlaylistDetailView` is already updated. Any other callers (e.g., `BingoGameView`) need to be updated — they can ignore the `missingTracks` and `allScanned` values:

```swift
let (loaded, _, _, url) = try await PlaylistService.loadSongs(for: playlist)
```

- [ ] **Step 2: Build and verify full compilation**

Run: `xcodebuild -project BingoBite.xcodeproj -scheme BingoBite build 2>&1 | tail -20`

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit (if changes were needed)**

```bash
git add -A
git commit -m "fix: update remaining PlaylistService.loadSongs callers for new return type"
```

---

### Task 6: Manual Testing & Polish

- [ ] **Step 1: Test happy path — no missing tracks**

1. Open a playlist where all tracks exist
2. Verify no banner appears
3. Verify all songs display normally in the table

- [ ] **Step 2: Test missing track detection**

1. Rename or delete a track file from a playlist's source folder
2. Open the playlist
3. Verify the orange banner appears with correct count (e.g., "1 of 25 tracks missing")
4. Verify the missing track row appears below the table with the original filename and a "Replace…" button

- [ ] **Step 3: Test replacement flow**

1. Click "Replace…" on a missing track row
2. Verify the sheet opens showing only tracks NOT already in the playlist
3. Select a replacement track and click "Replace"
4. Verify the missing track row disappears, the banner updates (or disappears if all replaced)
5. Verify the replacement song now appears in the main song table

- [ ] **Step 4: Test cleanup of old data**

1. Before replacing, create a SoundByte and metadata override for a track
2. Delete/rename that track file
3. Replace it
4. Verify the old SoundByte and metadata override were cleaned up (new track should show its own embedded metadata, no clip times)

- [ ] **Step 5: Commit any polish fixes**

```bash
git add -A
git commit -m "fix: polish missing track detection and replacement UI"
```
