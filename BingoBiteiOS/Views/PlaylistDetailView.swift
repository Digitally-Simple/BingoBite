import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    var playlist: Playlist
    @ObservedObject var audioPlayer: AudioPlayerService
    @Binding var selectedSong: Song?
    var onInspectSong: (Song) -> Void
    var onGameStarted: (BingoGame) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allSoundBytes: [SoundByte]

    @State private var songs: [Song] = []
    @State private var allScannedSongs: [Song] = []
    @State private var missingTracks: [PlaylistService.MissingTrack] = []
    @State private var accessedURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var showCardDesigner = false
    @State private var songToEdit: Song?
    @State private var trackToReplace: PlaylistService.MissingTrack?

    private var requiredSongs: Int { playlist.hasFreeSpace ? 24 : 25 }
    private var canStart: Bool { playlist.songCount >= requiredSongs && loadError == nil }

    private var soundByteLookup: [String: SoundByte] {
        Dictionary(allSoundBytes.map { ($0.songURLString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var displayedSongs: [Song] {
        guard !searchText.isEmpty else { return songs }
        return songs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            $0.displayAlbum.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var availableReplacements: [Song] {
        let used = Set(playlist.songURLStrings)
        return allScannedSongs.filter { !used.contains($0.id.absoluteString) }
    }

    private var totalPlaytime: TimeInterval {
        songs.compactMap(\.duration).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if !missingTracks.isEmpty { missingBanner }
                content
            }
            .padding(24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search songs")
        .task(id: playlist.uuid) { await loadSongs() }
        .onDisappear { releaseAccess() }
        // Full screen: the designer is a two-pane workspace and a form sheet
        // squeezes the page preview down to an unusable size.
        .fullScreenCover(isPresented: $showCardDesigner) {
            CardDesignerSheet(playlist: playlist, songs: songs)
        }
        .sheet(item: $songToEdit) { song in
            SongMetadataEditorSheet(
                song: song,
                onSave: { updated in
                    if let index = songs.firstIndex(where: { $0.id == updated.id }) {
                        songs[index] = updated
                    }
                    if selectedSong?.id == updated.id { selectedSong = updated }
                },
                onRevert: { Task { await loadSongs() } }
            )
        }
        .sheet(item: $trackToReplace) { missing in
            TrackReplacementSheet(
                missingTrack: missing,
                availableSongs: availableReplacements,
                onReplace: { newSong in
                    PlaylistService.replaceTrack(in: playlist, atIndex: missing.index, with: newSong, in: modelContext)
                    Task { await loadSongs() }
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    cover
                    identity
                }
                VStack(spacing: 16) {
                    cover
                    identity
                }
            }

            statsRow
            actionRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: Glassware.panelCorner)
    }

    private var cover: some View {
        ArtworkView(data: playlist.coverArtData, corner: Glassware.tileCorner, placeholderScale: 0.3)
            .frame(width: 148, height: 148)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(playlist.name)
                .font(.largeTitle.bold())
                .lineLimit(2)

            if !playlist.descriptionText.isEmpty {
                Text(playlist.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Label(SongsFolderService.displayPath(for: URL(fileURLWithPath: playlist.folderPath)), systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Created \(playlist.creationDate, style: .date)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("Songs", "\(playlist.songCount)", "music.note")
            stat("Artists", "\(Set(songs.compactMap(\.artist)).count)", "person.2")
            stat("Runtime", Format.time(totalPlaytime), "clock")
            stat("Cards", "\(playlist.numberOfCards)", "square.grid.3x3")
            stat("Free Space", playlist.hasFreeSpace ? "Yes" : "No", "star")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(corner: 14)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Start New Game", systemImage: "play.fill") {
                onGameStarted(BingoGameService.create(name: "", playlist: playlist, in: modelContext))
            }
            .buttonStyle(.glassProminent)
            .disabled(!canStart)

            Button("Design & Print Cards", systemImage: "printer") {
                showCardDesigner = true
            }
            .buttonStyle(.glass)
            .disabled(!canStart)

            Spacer()
        }
        .controlSize(.large)
    }

    // MARK: - Missing tracks

    private var missingBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "\(missingTracks.count) of \(playlist.songCount) tracks are missing",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text("These files were renamed, moved, or deleted. Replace them to keep the printed cards accurate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(missingTracks) { missing in
                HStack {
                    Text(missing.originalFileName)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Replace…") { trackToReplace = missing }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: Glassware.panelCorner, tint: .orange)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading songs…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if let loadError {
            unavailableState(loadError)
        } else if displayedSongs.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(minHeight: 240)
        } else {
            songList
        }
    }

    private func unavailableState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Source Folder Unavailable")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("The folder this playlist was built from may have moved or been removed from Files.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                PlaylistService.delete(playlist, in: modelContext)
            }
            .buttonStyle(.glass)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassCard(corner: Glassware.panelCorner)
    }

    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song)
                if index < displayedSongs.count - 1 {
                    Divider().padding(.leading, 78)
                }
            }
        }
        .glassCard(corner: Glassware.panelCorner)
    }

    private func songRow(_ song: Song) -> some View {
        let isCurrent = audioPlayer.currentSong == song
        let clip = soundByteLookup[song.id.absoluteString]

        return HStack(spacing: 14) {
            Button {
                if isCurrent {
                    audioPlayer.togglePlayPause()
                } else if let clip {
                    audioPlayer.preview(song, startTime: clip.startTime, endTime: clip.endTime)
                } else {
                    audioPlayer.play(song)
                }
            } label: {
                ZStack {
                    ArtworkView(data: song.artworkData, corner: 8)
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.45))
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text("\(song.displayArtist) · \(song.displayAlbum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let clip {
                Label(Format.time(clip.clipDuration), systemImage: "scissors")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }

            Text(song.formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Menu {
                Button("Song Details", systemImage: "info.circle") { onInspectSong(song) }
                Button("Edit Metadata", systemImage: "pencil") { songToEdit = song }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onInspectSong(song) }
    }

    // MARK: - Loading

    @MainActor
    private func loadSongs() async {
        isLoading = true
        loadError = nil
        missingTracks = []
        releaseAccess()
        do {
            let (loaded, missing, scanned, url) = try await PlaylistService.loadSongs(for: playlist, in: modelContext)
            songs = loaded
            missingTracks = missing
            allScannedSongs = scanned
            accessedURL = url
            applyOverrides()
        } catch {
            loadError = error.localizedDescription
            songs = []
            allScannedSongs = []
        }
        isLoading = false
    }

    private func applyOverrides() {
        let overrides = SongMetadataService.fetchAll(in: modelContext)
        for index in songs.indices {
            if let override = overrides[songs[index].id.absoluteString] {
                songs[index] = songs[index].applying(override: override)
            }
        }
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }
}
