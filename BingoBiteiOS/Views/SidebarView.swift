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

    var body: some View {
        List(selection: $selection) {
            Section("Playlists") {
                Label("All Playlists", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarSelection.allPlaylists)

                ForEach(playlists) { playlist in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(playlist.name).lineLimit(1)
                            Text("\(playlist.songCount) songs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.list")
                    }
                    .tag(SidebarSelection.playlist(playlist.persistentModelID))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            playlistPendingDeletion = playlist
                        }
                    }
                }
            }

            Section("Bingo Games") {
                Label("All Games", systemImage: "gamecontroller.fill")
                    .tag(SidebarSelection.allGames)

                ForEach(activeGames) { game in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(game.name).lineLimit(1)
                            Text(game.progress)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                    }
                    .tag(SidebarSelection.game(game.persistentModelID))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            gamePendingDeletion = game
                        }
                    }
                }
            }
        }
        .navigationTitle("BingoBite")
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
