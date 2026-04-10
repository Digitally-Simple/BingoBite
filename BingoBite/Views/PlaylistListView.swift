import SwiftUI
import SwiftData

struct PlaylistListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.creationDate) private var playlists: [Playlist]
    var onSelect: (PersistentIdentifier) -> Void

    @State private var tableSelection: PersistentIdentifier?
    @State private var sortOrder = [KeyPathComparator(\Playlist.name)]
    @State private var searchText = ""
    @State private var showPlaylistCreateSheet = false

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
                        description: Text("Create a playlist from a folder to get started.")
                    )
                } else {
                    Table(sortedPlaylists, selection: $tableSelection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Songs") { playlist in
                            Text("\(playlist.songCount)")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Cards") { playlist in
                            Text("\(playlist.numberOfCards)")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Free Space") { playlist in
                            Text(playlist.hasFreeSpace ? "Yes" : "No")
                                .foregroundStyle(.secondary)
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
                                tableSelection = nil
                                PlaylistService.delete(playlist, in: modelContext)
                            }
                        }
                    } primaryAction: { ids in
                        guard let id = ids.first else { return }
                        onSelect(id)
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPlaylistCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Playlist")
            }
        }
        .sheet(isPresented: $showPlaylistCreateSheet) {
            PlaylistCreateSheet(onCreated: { playlist in
                onSelect(playlist.persistentModelID)
            })
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
}
