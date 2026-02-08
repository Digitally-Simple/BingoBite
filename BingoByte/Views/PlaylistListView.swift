import SwiftUI
import SwiftData

struct PlaylistListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.creationDate) private var playlists: [Playlist]
    @Binding var selectedPlaylist: Playlist?
    var songs: [Song]

    @State private var tableSelection: PersistentIdentifier?
    @State private var sortOrder = [KeyPathComparator(\Playlist.name)]
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name or description", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a playlist to get started.")
                    )
                } else {
                    Table(sortedPlaylists, selection: $tableSelection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Songs") { playlist in
                            Text("\(playlist.songCount)")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Artists") { playlist in
                            Text("\(uniqueArtistCount(for: playlist))")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Duration") { playlist in
                            Text(totalDuration(for: playlist))
                                .monospacedDigit()
                        }
                        .width(ideal: 80)
                        TableColumn("Clip Time") { playlist in
                            Text(totalClipTime(for: playlist))
                                .monospacedDigit()
                        }
                        .width(ideal: 80)
                        TableColumn("Created") { playlist in
                            Text(playlist.creationDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        .width(ideal: 100)
                    }
                    .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                        if let id = ids.first,
                           let playlist = playlists.first(where: { $0.persistentModelID == id }) {
                            Button("Delete", role: .destructive) {
                                if selectedPlaylist?.persistentModelID == playlist.persistentModelID {
                                    selectedPlaylist = nil
                                }
                                tableSelection = nil
                                PlaylistService.delete(playlist, in: modelContext)
                            }
                            .disabled(BingoSetService.isPlaylistLocked(playlist, in: modelContext))
                        }
                    } primaryAction: { ids in
                        guard let id = ids.first,
                              let playlist = playlists.first(where: { $0.persistentModelID == id }) else { return }
                        selectedPlaylist = playlist
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let newPlaylist = PlaylistService.create(in: modelContext)
                    selectedPlaylist = newPlaylist
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Playlist")
            }
        }
    }

    // MARK: - Filtered & Sorted

    private var filteredPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return playlists }
        let query = searchText.lowercased()
        return playlists.filter {
            $0.name.lowercased().contains(query) ||
            $0.descriptionText.lowercased().contains(query)
        }
    }

    private var sortedPlaylists: [Playlist] {
        filteredPlaylists.sorted(using: sortOrder)
    }

    // MARK: - Helpers

    private func playlistSongs(for playlist: Playlist) -> [Song] {
        let urlStrings = Set(playlist.songURLStrings)
        return songs.filter { urlStrings.contains($0.id.absoluteString) }
    }

    private func uniqueArtistCount(for playlist: Playlist) -> Int {
        Set(playlistSongs(for: playlist).compactMap { $0.artist }).count
    }

    private func totalDuration(for playlist: Playlist) -> String {
        let matched = playlistSongs(for: playlist)
        let total = matched.compactMap(\.duration).reduce(0, +)
        return formatDuration(total)
    }

    private func totalClipTime(for playlist: Playlist) -> String {
        let matched = playlistSongs(for: playlist)
        var total: TimeInterval = 0
        for song in matched {
            if let sb = SoundByteService.fetch(for: song, in: modelContext) {
                total += sb.clipDuration
            }
        }
        return formatDuration(total)
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
