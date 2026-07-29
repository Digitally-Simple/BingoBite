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
    /// Drives the inspector as `.sheet(item:)` rather than a separate flag —
    /// an `isPresented` sheet reading `selectedSong` in its builder can present
    /// before the song lands, leaving an empty sheet.
    @State private var inspectorSong: Song?

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
            .appSurface()
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.accentColor)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(item: $inspectorSong) { song in
            SongInspectorSheet(song: song, audioPlayer: audioPlayer)
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
                .withNowPlayingDeck(audioPlayer: audioPlayer, onTapSong: presentInspector)

        case .playlist:
            if let playlist = selectedPlaylist {
                PlaylistDetailView(
                    playlist: playlist,
                    audioPlayer: audioPlayer,
                    selectedSong: $selectedSong,
                    onInspectSong: presentInspector,
                    onGameStarted: { selection = .game($0.persistentModelID) }
                )
                .withNowPlayingDeck(audioPlayer: audioPlayer, onTapSong: presentInspector)
            } else {
                ContentUnavailableView("Playlist Not Found", systemImage: "list.bullet.rectangle")
            }

        case .allGames:
            GameLibraryView(onOpen: { selection = .game($0) })
                .withNowPlayingDeck(audioPlayer: audioPlayer, onTapSong: presentInspector)

        case .game:
            if let game = selectedGame {
                GameView(game: game, audioPlayer: audioPlayer, onInspectSong: presentInspector)
            } else {
                ContentUnavailableView("Game Not Found", systemImage: "gamecontroller.fill")
            }
        }
    }

    private func presentInspector(_ song: Song) {
        selectedSong = song
        inspectorSong = song
    }
}

// MARK: - Deck attachment

/// Floats the deck over the content instead of insetting it, so the backdrop
/// and the scrolling content both run underneath the glass.
struct DeckOverlay<Deck: View>: ViewModifier {
    var isVisible: Bool
    @ViewBuilder var deck: Deck

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, isVisible ? 86 : 0)
            .overlay(alignment: .bottom) {
                if isVisible {
                    deck
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: isVisible)
    }
}

private struct NowPlayingDeckModifier: ViewModifier {
    @ObservedObject var audioPlayer: AudioPlayerService
    var onTapSong: (Song) -> Void

    func body(content: Content) -> some View {
        content.modifier(
            DeckOverlay(isVisible: audioPlayer.currentSong != nil) {
                if let song = audioPlayer.currentSong {
                    NowPlayingDeck(song: song, audioPlayer: audioPlayer, onInspect: { onTapSong(song) })
                }
            }
        )
    }
}

extension View {
    func withNowPlayingDeck(audioPlayer: AudioPlayerService, onTapSong: @escaping (Song) -> Void) -> some View {
        modifier(NowPlayingDeckModifier(audioPlayer: audioPlayer, onTapSong: onTapSong))
    }
}
