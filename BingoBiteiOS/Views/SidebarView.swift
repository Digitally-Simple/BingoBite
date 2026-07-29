import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarSelection?
    var onShowSettings: () -> Void

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var games: [BingoGame]

    @State private var playlistPendingDeletion: Playlist?
    @State private var gamePendingDeletion: BingoGame?

    private var activeGames: [BingoGame] { games.filter { !$0.isCompleted } }

    /// One row shape for every entry. Rows with and without a subtitle share a
    /// minimum height and a single gutter, so the column reads as one column
    /// rather than two sizes of row stacked together.
    private func row(title: String, subtitle: String? = nil, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        // Vertical breathing room only — the horizontal gutter is left to the
        // sidebar list style so rows line up with the section headers and the
        // navigation title instead of sitting at their own inset.
        .padding(.vertical, 5)
        .frame(minHeight: 34)
    }

    /// Games get the scoreboard treatment instead of a plain "18 / 28": the
    /// tick strip shows how far in the game is without needing to be read.
    private func gameRow(_ game: BingoGame) -> some View {
        let total = max(game.shuffledSongURLStrings.count, 1)
        let round = max(game.currentIndex + 1, 0)
        let status = Scoreboard.Status.resting(for: game)

        return Label {
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    SegmentedMeter(
                        filled: round,
                        total: total,
                        tint: status.tint,
                        height: 4,
                        trackColor: .primary.opacity(0.14)
                    )
                    Text("\(round)/\(total)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(status.tint)
                }
            }
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
        }
        .padding(.vertical, 5)
        .frame(minHeight: 34)
    }

    var body: some View {
        List(selection: $selection) {
            Section("Playlists") {
                row(title: "All Playlists", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarSelection.allPlaylists)

                ForEach(playlists) { playlist in
                    row(
                        title: playlist.name,
                        subtitle: "\(playlist.songCount) songs",
                        systemImage: "music.note.list"
                    )
                    .tag(SidebarSelection.playlist(playlist.persistentModelID))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            playlistPendingDeletion = playlist
                        }
                    }
                }
            }

            Section("Bingo Games") {
                row(title: "All Games", systemImage: "gamecontroller.fill")
                    .tag(SidebarSelection.allGames)

                ForEach(activeGames) { game in
                    gameRow(game)
                    .tag(SidebarSelection.game(game.persistentModelID))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            gamePendingDeletion = game
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .listSectionSpacing(22)
        .scrollContentBackground(.hidden)
        // Keeps the first section off the navigation title rather than butting
        // straight up against it.
        .contentMargins(.top, 10, for: .scrollContent)
        .appSurface()
        .navigationTitle("BingoBite")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    onShowSettings()
                }
            }
        }
        .confirmationDialog(
            "Delete “\(playlistPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { playlistPendingDeletion != nil },
                set: { if !$0 { playlistPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                guard let playlist = playlistPendingDeletion else { return }
                if case .playlist(let id) = selection, id == playlist.persistentModelID {
                    selection = .allPlaylists
                }
                PlaylistService.delete(playlist, in: modelContext)
                playlistPendingDeletion = nil
            }
        } message: {
            Text("Your audio files are not affected — only the playlist and its cards are removed.")
        }
        .confirmationDialog(
            "Delete “\(gamePendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { gamePendingDeletion != nil },
                set: { if !$0 { gamePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Game", role: .destructive) {
                guard let game = gamePendingDeletion else { return }
                if case .game(let id) = selection, id == game.persistentModelID {
                    selection = .allGames
                }
                BingoGameService.delete(game, in: modelContext)
                gamePendingDeletion = nil
            }
        }
    }
}
