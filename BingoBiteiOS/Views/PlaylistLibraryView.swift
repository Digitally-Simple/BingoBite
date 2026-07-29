import SwiftUI
import SwiftData

/// Grid of playlist cards — the landing screen.
struct PlaylistLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.creationDate, order: .reverse) private var playlists: [Playlist]
    var onOpen: (PersistentIdentifier) -> Void

    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var pendingDeletion: Playlist?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 20)]

    private var filtered: [Playlist] {
        guard !searchText.isEmpty else { return playlists }
        return playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.descriptionText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if playlists.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                grid
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Playlist", systemImage: "plus") {
                    showCreateSheet = true
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PlaylistCreateSheet { playlist in
                onOpen(playlist.persistentModelID)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                if let playlist = pendingDeletion {
                    PlaylistService.delete(playlist, in: modelContext)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Your audio files are not affected — only the playlist and its cards are removed.")
        }
    }

    private var grid: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filtered) { playlist in
                        PlaylistTile(playlist: playlist)
                            .onTapGesture { onOpen(playlist.persistentModelID) }
                            .contextMenu {
                                Button("Open", systemImage: "arrow.up.forward") {
                                    onOpen(playlist.persistentModelID)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = playlist
                                }
                            }
                    }
                }
                .padding(24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Playlists Yet", systemImage: "music.note.list")
        } description: {
            Text("Point BingoBite at a folder of songs in Files and it will build your bingo cards.")
        } actions: {
            Button("Create Playlist", systemImage: "plus") {
                showCreateSheet = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Tile

struct PlaylistTile: View {
    let playlist: Playlist

    private var requiredSongs: Int { playlist.hasFreeSpace ? 24 : 25 }
    private var isPlayable: Bool { playlist.songCount >= requiredSongs }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(data: playlist.coverArtData, corner: Glassware.tileCorner, placeholderScale: 0.28)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if !isPlayable {
                        Label("\(requiredSongs) needed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .glassCard(corner: 10, tint: .orange)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)

                if !playlist.descriptionText.isEmpty {
                    Text(playlist.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Label("\(playlist.songCount)", systemImage: "music.note")
                    Label("\(playlist.numberOfCards)", systemImage: "square.grid.3x3")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .interactiveGlassCard()
    }
}
