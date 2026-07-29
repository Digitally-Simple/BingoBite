import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case allPlaylists
    case playlist(PersistentIdentifier)
    case allGames
    case game(PersistentIdentifier)

    enum Kind { case playlist, game }
    var kind: Kind {
        switch self {
        case .allPlaylists, .playlist: .playlist
        case .allGames, .game: .game
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var games: [BingoGame]

    @State private var selection: SidebarSelection? = .allPlaylists
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSettings = false
    @State private var selectedSong: Song?
    @State private var showSongInspector = false

    @StateObject private var audioPlayer = AudioPlayerService()

    private var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = selection else { return nil }
        return playlists.first { $0.persistentModelID == id }
    }

    private var selectedGame: BingoGame? {
        guard case .game(let id) = selection else { return nil }
        return games.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, onShowSettings: { showSettings = true })
        } detail: {
            NavigationStack {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.accentColor)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showSongInspector) {
            if let song = selectedSong {
                SongInspectorSheet(song: song, audioPlayer: audioPlayer)
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            selectedSong = nil
            if oldValue?.kind != newValue?.kind {
                audioPlayer.stop()
                audioPlayer.clearSkipHandlers()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .allPlaylists, .none:
            PlaylistLibraryView(onOpen: { selection = .playlist($0) })
                .withNowPlayingBar(audioPlayer: audioPlayer, onTapSong: presentInspector)

        case .playlist:
            if let playlist = selectedPlaylist {
                PlaylistDetailView(
                    playlist: playlist,
                    audioPlayer: audioPlayer,
                    selectedSong: $selectedSong,
                    onInspectSong: { song in
                        selectedSong = song
                        showSongInspector = true
                    },
                    onGameStarted: { selection = .game($0.persistentModelID) }
                )
                .withNowPlayingBar(audioPlayer: audioPlayer, onTapSong: presentInspector)
            } else {
                ContentUnavailableView("Playlist Not Found", systemImage: "list.bullet.rectangle")
            }

        case .allGames:
            GameLibraryView(onOpen: { selection = .game($0) })
                .withNowPlayingBar(audioPlayer: audioPlayer, onTapSong: presentInspector)

        case .game:
            if let game = selectedGame {
                GameView(game: game, audioPlayer: audioPlayer)
            } else {
                ContentUnavailableView("Game Not Found", systemImage: "gamecontroller.fill")
            }
        }
    }

    private func presentInspector(_ song: Song) {
        selectedSong = song
        showSongInspector = true
    }
}

// MARK: - Now Playing bar attachment

private struct NowPlayingBarModifier: ViewModifier {
    @ObservedObject var audioPlayer: AudioPlayerService
    var onTapSong: (Song) -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let song = audioPlayer.currentSong {
                NowPlayingBar(song: song, audioPlayer: audioPlayer, onTap: { onTapSong(song) })
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: audioPlayer.currentSong)
    }
}

extension View {
    func withNowPlayingBar(audioPlayer: AudioPlayerService, onTapSong: @escaping (Song) -> Void) -> some View {
        modifier(NowPlayingBarModifier(audioPlayer: audioPlayer, onTapSong: onTapSong))
    }
}
