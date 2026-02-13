import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case songs
    case allPlaylists
    case playlist(PersistentIdentifier)
    case allBingoSets
    case bingoSet(PersistentIdentifier)
    case allBingoGames
    case bingoGame(PersistentIdentifier)

    enum Kind { case songs, playlist, bingoSet, bingoGame }
    var kind: Kind {
        switch self {
        case .songs: return .songs
        case .allPlaylists, .playlist: return .playlist
        case .allBingoSets, .bingoSet: return .bingoSet
        case .allBingoGames, .bingoGame: return .bingoGame
        }
    }
}

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarSelection?
    var songs: [Song]

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoSet.name) private var bingoSets: [BingoSet]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    @State private var showBingoSetCreateSheet = false
    @State private var showBingoGameCreateSheet = false

    var body: some View {
        List(selection: $selection) {
            // MARK: - Library
            Section("Library") {
                Label("Songs", systemImage: "music.note.list")
                    .tag(SidebarSelection.songs)
            }

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
                            .disabled(BingoSetService.isPlaylistLocked(playlist, in: modelContext))
                        }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        let newPlaylist = PlaylistService.create(in: modelContext)
                        selection = .playlist(newPlaylist.persistentModelID)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // MARK: - Bingo Sets
            Section {
                Label("All Bingo Sets", systemImage: "square.grid.3x3.fill")
                    .tag(SidebarSelection.allBingoSets)
                ForEach(bingoSets) { bingoSet in
                    Label(bingoSet.name, systemImage: "square.grid.3x3")
                        .tag(SidebarSelection.bingoSet(bingoSet.persistentModelID))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if case .bingoSet(let id) = selection, id == bingoSet.persistentModelID {
                                    selection = .allBingoSets
                                }
                                BingoSetService.delete(bingoSet, in: modelContext)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Bingo Sets")
                    Spacer()
                    Button {
                        showBingoSetCreateSheet = true
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
        .navigationTitle("BingoByte")
        .sheet(isPresented: $showBingoSetCreateSheet) {
            BingoSetCreateSheet(songs: songs)
        }
        .sheet(isPresented: $showBingoGameCreateSheet) {
            BingoGameCreateSheet { game in
                selection = .bingoGame(game.persistentModelID)
            }
        }
    }
}
