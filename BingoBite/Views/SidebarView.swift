import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case allPlaylists
    case playlist(PersistentIdentifier)
    case allBingoGames
    case bingoGame(PersistentIdentifier)

    enum Kind { case playlist, bingoGame }
    var kind: Kind {
        switch self {
        case .allPlaylists, .playlist: return .playlist
        case .allBingoGames, .bingoGame: return .bingoGame
        }
    }
}

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarSelection?

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    @State private var showPlaylistCreateSheet = false
    @State private var showBingoGameCreateSheet = false

    var body: some View {
        List(selection: $selection) {
            // MARK: - Playlists
            Section {
                Label("All Playlists", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.allPlaylists)
                ForEach(playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarSelection.playlist(playlist.persistentModelID))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if case .playlist(let id) = selection, id == playlist.persistentModelID {
                                    selection = .allPlaylists
                                }
                                PlaylistService.delete(playlist, in: modelContext)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        showPlaylistCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // MARK: - Bingo Games
            Section {
                Label("All Bingo Games", systemImage: "gamecontroller.fill")
                    .tag(SidebarSelection.allBingoGames)
                ForEach(bingoGames) { bingoGame in
                    Label(bingoGame.name, systemImage: "gamecontroller")
                        .tag(SidebarSelection.bingoGame(bingoGame.persistentModelID))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if case .bingoGame(let id) = selection, id == bingoGame.persistentModelID {
                                    selection = .allBingoGames
                                }
                                BingoGameService.delete(bingoGame, in: modelContext)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Bingo Games")
                    Spacer()
                    Button {
                        showBingoGameCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BingoBite")
        .sheet(isPresented: $showPlaylistCreateSheet) {
            PlaylistCreateSheet(onCreated: { playlist in
                selection = .playlist(playlist.persistentModelID)
            })
        }
        .sheet(isPresented: $showBingoGameCreateSheet) {
            BingoGameCreateSheet { game in
                selection = .bingoGame(game.persistentModelID)
            }
        }
    }
}
