import SwiftUI
import SwiftData
import AppKit

struct PlaylistDetailView: View {
    var playlist: Playlist
    @ObservedObject var audioPlayer: AudioPlayerService
    @Binding var selectedSong: Song?
    var onGameCreated: (BingoGame) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext

    @Query private var allSoundBytes: [SoundByte]

    @State private var songs: [Song] = []
    @State private var tableSelection: Song.ID?
    @State private var accessedURL: URL?
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var showCardDesigner: Bool = false
    @State private var songToEdit: Song?
    @State private var sortOrder: [KeyPathComparator<Song>] = [KeyPathComparator(\Song.displayTitle)]
    @State private var searchText: String = ""
    @State private var missingTracks: [PlaylistService.MissingTrack] = []
    @State private var trackToReplace: PlaylistService.MissingTrack?
    @State private var allScannedSongs: [Song] = []

    private var uniqueArtistCount: Int {
        Set(songs.compactMap { $0.artist }).count
    }

    private var totalPlaytime: TimeInterval {
        songs.compactMap { $0.duration }.reduce(0, +)
    }

    private var soundByteLookup: [String: SoundByte] {
        Dictionary(uniqueKeysWithValues: allSoundBytes.map { ($0.songKey, $0) })
    }

    private var displayedSongs: [Song] {
        let filtered = searchText.isEmpty ? songs : songs.filter { song in
            song.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            song.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            song.displayAlbum.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }

    /// All songs found in the source folder that are NOT already in the playlist's songKeys.
    private var availableReplacementSongs: [Song] {
        let usedURLs = Set(playlist.songKeys)
        return allScannedSongs.filter { !usedURLs.contains($0.id.absoluteString) }
    }

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

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            coverView
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                if !playlist.descriptionText.isEmpty {
                    Text(playlist.descriptionText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("Created \(playlist.creationDate, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button {
                        startNewGame()
                    } label: {
                        Label("Start New Game", systemImage: "play.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(playlist.songCount < (playlist.hasFreeSpace ? 24 : 25) || loadError != nil)

                    Button {
                        showCardDesigner = true
                    } label: {
                        Label("Design & Print Cards", systemImage: "printer")
                    }
                    .disabled(playlist.songCount < (playlist.hasFreeSpace ? 24 : 25) || loadError != nil)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var coverView: some View {
        Group {
            if let data = playlist.coverArtData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(label: "Songs", value: "\(playlist.songCount)")
            statItem(label: "Artists", value: "\(uniqueArtistCount)")
            statItem(label: "Total Time", value: formatDuration(totalPlaytime))
            statItem(label: "Cards", value: "\(playlist.numberOfCards)")
            statItem(label: "Free Space", value: playlist.hasFreeSpace ? "Yes" : "No")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Source Folder Bar

    private var sourceFolderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(playlist.folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(playlist.folderPath)
            Spacer()
            if let accessedURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([accessedURL])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                ProgressView()
                Text("Loading songs…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Source Folder Unavailable")
                    .font(.headline)
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("This playlist's source folder may have been moved, renamed, or deleted.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Delete Playlist", role: .destructive) {
                    PlaylistService.delete(playlist, in: modelContext)
                }
                .padding(.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            VStack(spacing: 0) {
                songsTable
                if !missingTracks.isEmpty {
                    Divider()
                    missingTracksList
                }
            }
        }
    }

    private var songsTable: some View {
        Table(displayedSongs, selection: $tableSelection, sortOrder: $sortOrder) {
            TableColumn("") { (song: Song) in
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
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .width(30)
            TableColumn("") { (song: Song) in
                Button {
                    audioPlayer.play(song)
                } label: {
                    Image(systemName: audioPlayer.currentSong == song && audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundStyle(tableSelection == song.id ? .white : Color.accentColor)
                }
                .buttonStyle(.borderless)
            }
            .width(30)
            TableColumn("Title", value: \.displayTitle)
            TableColumn("Artist", value: \.displayArtist)
            TableColumn("Album", value: \.displayAlbum)
            TableColumn("Duration", value: \.sortableDuration) { (song: Song) in
                Text(song.formattedDuration)
                    .monospacedDigit()
            }
            .width(ideal: 70)
            TableColumn("Start") { (song: Song) in
                let sb = soundByteLookup[song.stableKey]
                Text(sb != nil ? Self.formatTime(sb!.startTime) : "--:--")
                    .monospacedDigit()
                    .foregroundStyle(sb != nil ? .primary : .tertiary)
            }
            .width(ideal: 60)
            TableColumn("Stop") { (song: Song) in
                let sb = soundByteLookup[song.stableKey]
                Text(sb != nil ? Self.formatTime(sb!.endTime) : "--:--")
                    .monospacedDigit()
                    .foregroundStyle(sb != nil ? .primary : .tertiary)
            }
            .width(ideal: 60)
            TableColumn("Clip") { (song: Song) in
                let sb = soundByteLookup[song.stableKey]
                Text(sb != nil ? Self.formatTime(sb!.clipDuration) : "--:--")
                    .monospacedDigit()
                    .foregroundStyle(sb != nil ? .primary : .tertiary)
            }
            .width(ideal: 60)
        }
        .contextMenu(forSelectionType: Song.ID.self) { items in
            if let id = items.first, let song = songs.first(where: { $0.id == id }) {
                Button("Edit Metadata\u{2026}") {
                    songToEdit = song
                }
            }
        }
        .onChange(of: tableSelection) {
            selectedSong = songs.first { $0.id == tableSelection }
        }
    }

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

    // MARK: - Loading

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

    private func applyMetadataOverrides() {
        let overrides = SongMetadataService.fetchAll(in: modelContext)
        for i in songs.indices {
            if let override = overrides[songs[i].stableKey] {
                songs[i] = songs[i].applying(override: override)
            }
        }
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }

    // MARK: - Game

    private func startNewGame() {
        let game = BingoGameService.create(name: "", playlist: playlist, in: modelContext)
        onGameCreated(game)
    }

    // MARK: - Helpers

    private static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
