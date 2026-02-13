import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoSet.name) private var bingoSets: [BingoSet]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    @State private var sidebarSelection: SidebarSelection? = .songs
    @State private var showSettings = false
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSongID: Song.ID?
    @State private var showInspector = true
    @State private var accessedFolderURL: URL?
    @State private var searchText = ""
    @State private var selectedCard: BingoCard?

    @StateObject private var audioPlayer = AudioPlayerService()

    private var selectedSong: Song? {
        guard let selectedSongID else { return nil }
        return songs.first { $0.id == selectedSongID }
    }

    private var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = sidebarSelection else { return nil }
        return playlists.first { $0.persistentModelID == id }
    }

    private var selectedBingoSet: BingoSet? {
        guard case .bingoSet(let id) = sidebarSelection else { return nil }
        return bingoSets.first { $0.persistentModelID == id }
    }

    private var selectedBingoGame: BingoGame? {
        guard case .bingoGame(let id) = sidebarSelection else { return nil }
        return bingoGames.first { $0.persistentModelID == id }
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return songs }
        let query = searchText.lowercased()
        return songs.filter { song in
            song.displayTitle.lowercased().contains(query) ||
            (song.artist?.lowercased().contains(query) ?? false) ||
            (song.album?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, songs: songs)
        } detail: {
            switch sidebarSelection {
            case .songs, nil:
                SongListView(
                    songs: filteredSongs,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    selection: $selectedSongID,
                    searchText: $searchText,
                    onPlay: { song in
                        audioPlayer.play(song)
                    }
                )
                .navigationTitle("Songs")
            case .allPlaylists:
                PlaylistListView(
                    onSelect: { id in sidebarSelection = .playlist(id) },
                    songs: songs
                )
            case .playlist:
                if let playlist = selectedPlaylist {
                    PlaylistEditorView(playlist: playlist, songs: songs)
                } else {
                    ContentUnavailableView("Playlist Not Found", systemImage: "list.bullet.rectangle")
                }
            case .allBingoSets:
                BingoSetListView(
                    onSelect: { id in sidebarSelection = .bingoSet(id) },
                    songs: songs
                )
            case .bingoSet:
                if let bingoSet = selectedBingoSet {
                    BingoSetDetailView(bingoSet: bingoSet, selectedCard: $selectedCard)
                } else {
                    ContentUnavailableView("Bingo Set Not Found", systemImage: "square.grid.3x3.fill")
                }
            case .allBingoGames:
                BingoGameListView(
                    onSelect: { id in sidebarSelection = .bingoGame(id) }
                )
            case .bingoGame:
                if let bingoGame = selectedBingoGame {
                    BingoGameView(
                        bingoGame: bingoGame,
                        songs: songs,
                        audioPlayer: audioPlayer
                    )
                } else {
                    ContentUnavailableView("Bingo Game Not Found", systemImage: "gamecontroller.fill")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if case .bingoSet = sidebarSelection, let card = selectedCard, let bingoSet = selectedBingoSet {
                    BingoCardInspectorView(card: card, bingoSet: bingoSet, songs: songs)
                } else if sidebarSelection?.kind == .bingoGame {
                    InspectorPaneView(selectedSong: audioPlayer.currentSong, audioPlayer: audioPlayer)
                } else {
                    InspectorPaneView(selectedSong: selectedSong, audioPlayer: audioPlayer)
                }
            }
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
            SettingsSheet {
                Task { await loadSongs() }
            }
        }
        .task {
            await loadSongs()
        }
        .onDisappear {
            releaseFolder()
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            let oldKind = oldValue?.kind
            let newKind = newValue?.kind
            if oldKind != newKind {
                audioPlayer.stop()
                audioPlayer.clearSkipHandlers()
                selectedCard = nil
            }
        }
        .onChange(of: audioPlayer.currentSong) {
            if sidebarSelection == .songs || sidebarSelection == nil {
                if let current = audioPlayer.currentSong {
                    selectedSongID = current.id
                }
                updateSongsSkipHandlers()
            }
        }
        .onChange(of: searchText) {
            if (sidebarSelection == .songs || sidebarSelection == nil) && audioPlayer.currentSong != nil {
                updateSongsSkipHandlers()
            }
        }
    }

    private func loadSongs() async {
        let settings = settingsItems.first
        guard let bookmarkData = settings?.bookmarkData else {
            songs = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        // Release any previously accessed folder
        releaseFolder()

        do {
            let folderURL = try BookmarkService.resolveBookmark(bookmarkData)
            guard BookmarkService.startAccessing(folderURL) else {
                errorMessage = "Unable to access the selected folder."
                isLoading = false
                return
            }
            accessedFolderURL = folderURL

            songs = try await FolderScannerService.scanForMP3s(in: folderURL)
            settings?.lastScannedDate = Date()
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            songs = []
        }

        isLoading = false
    }

    private func updateSongsSkipHandlers() {
        guard let currentSong = audioPlayer.currentSong else {
            audioPlayer.clearSkipHandlers()
            return
        }
        let songList = filteredSongs
        guard let currentIndex = songList.firstIndex(where: { $0.id == currentSong.id }) else {
            audioPlayer.clearSkipHandlers()
            return
        }

        let canBack = currentIndex > 0
        let canForward = currentIndex < songList.count - 1
        let player = audioPlayer
        let ctx = modelContext

        player.onSkipForward = canForward ? {
            let nextSong = songList[currentIndex + 1]
            if let soundByte = SoundByteService.fetch(for: nextSong, in: ctx) {
                player.play(nextSong, from: soundByte.startTime)
            } else {
                player.play(nextSong)
            }
        } : nil

        player.onSkipBackward = canBack ? {
            let prevSong = songList[currentIndex - 1]
            if let soundByte = SoundByteService.fetch(for: prevSong, in: ctx) {
                player.play(prevSong, from: soundByte.startTime)
            } else {
                player.play(prevSong)
            }
        } : nil

        player.setSkipState(canForward: canForward, canBackward: canBack)
    }

    private func releaseFolder() {
        if let url = accessedFolderURL {
            BookmarkService.stopAccessing(url)
            accessedFolderURL = nil
        }
    }
}
