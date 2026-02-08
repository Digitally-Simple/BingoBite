import SwiftUI
import SwiftData

struct PlaylistEditorView: View {
    @Bindable var playlist: Playlist
    var songs: [Song]
    var onBack: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var availableSortOrder = [KeyPathComparator(\Song.displayTitle)]
    @State private var playlistSortOrder = [KeyPathComparator(\Song.displayTitle)]
    @State private var searchText = ""

    private var isLocked: Bool {
        BingoSetService.isPlaylistLocked(playlist, in: modelContext)
    }

    private var playlistSongs: [Song] {
        let urlStrings = Set(playlist.songURLStrings)
        return filteredSongs.filter { urlStrings.contains($0.id.absoluteString) }
    }

    private var availableSongs: [Song] {
        let urlStrings = Set(playlist.songURLStrings)
        return filteredSongs.filter { !urlStrings.contains($0.id.absoluteString) }
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return songs }
        let query = searchText.lowercased()
        return songs.filter { song in
            song.displayTitle.lowercased().contains(query) ||
            (song.artist?.lowercased().contains(query) ?? false) ||
            (song.album?.lowercased().contains(query) ?? false)
        }
    }

    private var sortedAvailableSongs: [Song] {
        availableSongs.sorted(using: availableSortOrder)
    }

    private var sortedPlaylistSongs: [Song] {
        playlistSongs.sorted(using: playlistSortOrder)
    }

    // MARK: - Stats

    private var uniqueArtistCount: Int {
        Set(playlistSongs.compactMap { $0.artist }).count
    }

    private var totalPlaytime: TimeInterval {
        playlistSongs.compactMap { $0.duration }.reduce(0, +)
    }

    private var totalClipPlaytime: TimeInterval {
        playlistSongs.reduce(0) { total, song in
            if let soundByte = SoundByteService.fetch(for: song, in: modelContext) {
                return total + soundByte.clipDuration
            }
            return total + (song.duration ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLocked {
                lockBanner
                Divider()
            }
            headerSection
            Divider()
            statsBar
            Divider()
            searchBar
            Divider()
            tablesSection
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Playlists")
                    }
                }
                .help("Back to Playlists")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Playlist Name", text: $playlist.name)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .disabled(isLocked)
            TextField("Description", text: $playlist.descriptionText)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .disabled(isLocked)
        }
        .padding()
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(label: "Songs", value: "\(playlist.songCount)")
            statItem(label: "Artists", value: "\(uniqueArtistCount)")
            statItem(label: "Total Time", value: formatDuration(totalPlaytime))
            statItem(label: "Clip Time", value: formatDuration(totalClipPlaytime))
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by title, artist, or album", text: $searchText)
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
    }

    // MARK: - Two Tables

    private var tablesSection: some View {
        HSplitView {
            VStack(spacing: 0) {
                Text("Available Songs")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Table(sortedAvailableSongs, sortOrder: $availableSortOrder) {
                    TableColumn("") { song in
                        Button {
                            PlaylistService.addSong(song, to: playlist, in: modelContext)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(isLocked ? .gray : .green)
                        }
                        .buttonStyle(.borderless)
                        .help("Add to playlist")
                        .disabled(isLocked)
                    }
                    .width(30)
                    TableColumn("Title", value: \.displayTitle)
                    TableColumn("Artist") { song in
                        Text(song.artist ?? "Unknown Artist")
                    }
                    TableColumn("Duration") { song in
                        Text(song.formattedDuration)
                            .monospacedDigit()
                    }
                    .width(ideal: 70)
                }
            }

            VStack(spacing: 0) {
                Text("Playlist Songs")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Table(sortedPlaylistSongs, sortOrder: $playlistSortOrder) {
                    TableColumn("") { song in
                        Button {
                            PlaylistService.removeSong(song, from: playlist, in: modelContext)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(isLocked ? .gray : .red)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from playlist")
                        .disabled(isLocked)
                    }
                    .width(30)
                    TableColumn("Title", value: \.displayTitle)
                    TableColumn("Artist") { song in
                        Text(song.artist ?? "Unknown Artist")
                    }
                    TableColumn("Duration") { song in
                        Text(song.formattedDuration)
                            .monospacedDigit()
                    }
                    .width(ideal: 70)
                }
            }
        }
    }

    // MARK: - Lock Banner

    private var lockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            Text("This playlist is locked because it has an associated bingo set.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Helpers

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
