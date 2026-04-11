import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    @State private var sidebarSelection: SidebarSelection? = .allPlaylists
    @State private var showSettings = false
    @State private var showInspector = true
    @State private var selectedSong: Song?

    @StateObject private var audioPlayer = AudioPlayerService()

    private var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = sidebarSelection else { return nil }
        return playlists.first { $0.persistentModelID == id }
    }

    private var selectedBingoGame: BingoGame? {
        guard case .bingoGame(let id) = sidebarSelection else { return nil }
        return bingoGames.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            switch sidebarSelection {
            case .allPlaylists, .none:
                PlaylistListView(
                    onSelect: { id in sidebarSelection = .playlist(id) }
                )
            case .playlist:
                if let playlist = selectedPlaylist {
                    PlaylistDetailView(
                        playlist: playlist,
                        audioPlayer: audioPlayer,
                        selectedSong: $selectedSong,
                        onGameCreated: { game in
                            sidebarSelection = .bingoGame(game.persistentModelID)
                        }
                    )
                } else {
                    ContentUnavailableView("Playlist Not Found", systemImage: "list.bullet.rectangle")
                }
            case .allBingoGames:
                BingoGameListView(
                    onSelect: { id in sidebarSelection = .bingoGame(id) }
                )
            case .bingoGame:
                if let bingoGame = selectedBingoGame {
                    BingoGameView(
                        bingoGame: bingoGame,
                        audioPlayer: audioPlayer
                    )
                } else {
                    ContentUnavailableView("Bingo Game Not Found", systemImage: "gamecontroller.fill")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorPaneView(selectedSong: selectedSong ?? audioPlayer.currentSong, audioPlayer: audioPlayer)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Toggle Inspector")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                onLicenseDeactivated: {
                    NotificationCenter.default.post(name: .licenseDeactivated, object: nil)
                }
            )
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            selectedSong = nil
            let oldKind = oldValue?.kind
            let newKind = newValue?.kind
            if oldKind != newKind {
                audioPlayer.stop()
                audioPlayer.clearSkipHandlers()
            }
        }
    }
}
