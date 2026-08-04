import SwiftUI
import SwiftData

struct GameLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var games: [BingoGame]
    var onOpen: (PersistentIdentifier) -> Void

    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var pendingDeletion: BingoGame?

    private var filtered: [BingoGame] {
        guard !searchText.isEmpty else { return games }
        return games.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.playlistName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var inProgress: [BingoGame] { filtered.filter { !$0.isCompleted } }
    private var completed: [BingoGame] { filtered.filter(\.isCompleted) }

    var body: some View {
        Group {
            if games.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                list
            }
        }
        .navigationTitle("Bingo Games")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search games")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Game", systemImage: "plus") { showCreateSheet = true }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            GameCreateSheet { game in onOpen(game.persistentModelID) }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Game", role: .destructive) {
                if let game = pendingDeletion {
                    BingoGameService.delete(game, in: modelContext)
                }
                pendingDeletion = nil
            }
        }
    }

    private var list: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 24) {
                    if !inProgress.isEmpty {
                        section("In Progress", games: inProgress)
                    }
                    if !completed.isEmpty {
                        section("Completed", games: completed)
                    }
                }
                .padding(24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func section(_ title: String, games: [BingoGame]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title)
            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.persistentModelID) { index, game in
                    row(game)
                    if index < games.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .glassCard(corner: Glassware.panelCorner)
        }
    }

    private func row(_ game: BingoGame) -> some View {
        let total = max(game.shuffledSongKeys.count, 1)
        let round = max(game.currentIndex + 1, 0)
        let status = Scoreboard.Status.resting(for: game)

        return HStack(spacing: 16) {
            // The round replaces the old status glyph: the number is the thing
            // you actually want off a list of half-finished games.
            RoundChip(round: round, size: 19, tint: status.tint)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(game.playlistName) · \(game.numberOfCards) cards · \(game.creationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            StatusPill(status: status, compact: true)

            VStack(alignment: .trailing, spacing: 4) {
                MeterLane(
                    title: "ROUNDS CALLED",
                    filled: round,
                    total: total,
                    tint: status.tint,
                    isMuted: round == 0,
                    height: 6,
                    labelColor: .secondary,
                    trackColor: .primary.opacity(0.12)
                )
            }
            .frame(width: 150)

            Menu {
                Button("Open", systemImage: "arrow.up.forward") { onOpen(game.persistentModelID) }
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = game }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .tint(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(game.persistentModelID) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Bingo Games", systemImage: "gamecontroller.fill")
        } description: {
            Text("Start a game from a playlist to shuffle the songs and score the cards live.")
        } actions: {
            Button("New Game", systemImage: "plus") { showCreateSheet = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Create

struct GameCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.creationDate, order: .reverse) private var playlists: [Playlist]
    var onCreate: (BingoGame) -> Void

    @State private var selectedID: PersistentIdentifier?
    @State private var name = ""

    private var selectedPlaylist: Playlist? {
        playlists.first { $0.persistentModelID == selectedID }
    }

    /// A playlist can only host a game once it has enough songs for a full card.
    private var eligiblePlaylists: [Playlist] {
        playlists.filter { $0.songCount >= ($0.hasFreeSpace ? 24 : 25) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    if eligiblePlaylists.isEmpty {
                        Text("No playlist has enough songs for a bingo card yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(eligiblePlaylists) { playlist in
                        Button {
                            selectedID = playlist.persistentModelID
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(data: playlist.coverArtData, corner: 6)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name).foregroundStyle(.primary)
                                    Text("\(playlist.songCount) songs · \(playlist.numberOfCards) cards")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedID == playlist.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Game name (optional)", text: $name)
                } footer: {
                    Text("Leave blank to name it after the playlist and today's date.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Bingo Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        guard let playlist = selectedPlaylist else { return }
                        let game = BingoGameService.create(name: name, playlist: playlist, in: modelContext)
                        dismiss()
                        onCreate(game)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(selectedPlaylist == nil)
                }
            }
        }
    }
}
