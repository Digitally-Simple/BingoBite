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
    var trialDaysRemaining: Int?
    var onShowSettings: (() -> Void)?

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

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
                Text("Playlists")
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
                Text("Bingo Games")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BingoBite")
        .safeAreaInset(edge: .bottom) {
            if let days = trialDaysRemaining {
                Button {
                    onShowSettings?()
                } label: {
                    Label("Trial: \(days) \(days == 1 ? "day" : "days") remaining", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
