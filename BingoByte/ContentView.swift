import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]

    @State private var sidebarSelection: SidebarItem? = .songs
    @State private var showSettings = false
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSongID: Song.ID?
    @State private var showInspector = true
    @State private var accessedFolderURL: URL?
    @State private var searchText = ""
    @State private var selectedPlaylist: Playlist?
    @State private var selectedBingoSet: BingoSet?
    @State private var selectedCard: BingoCard?

    @StateObject private var audioPlayer = AudioPlayerService()

    private var selectedSong: Song? {
        guard let selectedSongID else { return nil }
        return songs.first { $0.id == selectedSongID }
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
            SidebarView(selection: $sidebarSelection)
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
            case .playlists:
                if let playlist = selectedPlaylist {
                    PlaylistEditorView(
                        playlist: playlist,
                        songs: songs,
                        onBack: { selectedPlaylist = nil }
                    )
                } else {
                    PlaylistListView(selectedPlaylist: $selectedPlaylist, songs: songs)
                }
            case .bingoSets:
                if let bingoSet = selectedBingoSet {
                    BingoSetDetailView(
                        bingoSet: bingoSet,
                        onBack: {
                            selectedBingoSet = nil
                            selectedCard = nil
                        },
                        selectedCard: $selectedCard
                    )
                } else {
                    BingoSetListView(selectedBingoSet: $selectedBingoSet, songs: songs)
                }
            case .bingoGames:
                BingoGameView(songs: songs, audioPlayer: audioPlayer)
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if sidebarSelection == .bingoSets, let card = selectedCard, let bingoSet = selectedBingoSet {
                    BingoCardInspectorView(card: card, bingoSet: bingoSet, songs: songs)
                } else if sidebarSelection == .bingoGames {
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
        .onChange(of: sidebarSelection) {
            audioPlayer.stop()
            selectedPlaylist = nil
            selectedBingoSet = nil
            selectedCard = nil
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

    private func releaseFolder() {
        if let url = accessedFolderURL {
            BookmarkService.stopAccessing(url)
            accessedFolderURL = nil
        }
    }
}
