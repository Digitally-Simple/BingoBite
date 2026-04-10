import SwiftUI
import SwiftData
import AppKit

struct PlaylistDetailView: View {
    var playlist: Playlist
    @ObservedObject var audioPlayer: AudioPlayerService
    var onGameCreated: (BingoGame) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext

    @State private var songs: [Song] = []
    @State private var accessedURL: URL?
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    private var uniqueArtistCount: Int {
        Set(songs.compactMap { $0.artist }).count
    }

    private var totalPlaytime: TimeInterval {
        songs.compactMap { $0.duration }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            statsBar
            Divider()
            sourceFolderBar
            Divider()
            content
        }
        .navigationTitle(playlist.name)
        .task(id: playlist.uuid) {
            await loadSongs()
        }
        .onDisappear {
            releaseAccess()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            coverView
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                if !playlist.descriptionText.isEmpty {
                    Text(playlist.descriptionText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("Created \(playlist.creationDate, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button {
                        startNewGame()
                    } label: {
                        Label("Start New Game", systemImage: "play.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(playlist.songCount < (playlist.hasFreeSpace ? 24 : 25) || loadError != nil)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var coverView: some View {
        Group {
            if let data = playlist.coverArtData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(label: "Songs", value: "\(playlist.songCount)")
            statItem(label: "Artists", value: "\(uniqueArtistCount)")
            statItem(label: "Total Time", value: formatDuration(totalPlaytime))
            statItem(label: "Cards", value: "\(playlist.numberOfCards)")
            statItem(label: "Free Space", value: playlist.hasFreeSpace ? "Yes" : "No")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Source Folder Bar

    private var sourceFolderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(playlist.folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(playlist.folderPath)
            Spacer()
            if let accessedURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([accessedURL])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                ProgressView()
                Text("Loading songs…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Source Folder Unavailable")
                    .font(.headline)
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("This playlist's source folder may have been moved, renamed, or deleted.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Delete Playlist", role: .destructive) {
                    PlaylistService.delete(playlist, in: modelContext)
                }
                .padding(.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            songsTable
        }
    }

    private var songsTable: some View {
        Table(songs) {
            TableColumn("") { (song: Song) in
                Button {
                    audioPlayer.play(song)
                } label: {
                    Image(systemName: audioPlayer.currentSong == song && audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
            }
            .width(30)
            TableColumn("Title", value: \.displayTitle)
            TableColumn("Artist") { (song: Song) in
                Text(song.artist ?? "Unknown Artist")
            }
            TableColumn("Album") { (song: Song) in
                Text(song.album ?? "Unknown Album")
            }
            TableColumn("Duration") { (song: Song) in
                Text(song.formattedDuration)
                    .monospacedDigit()
            }
            .width(ideal: 70)
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadSongs() async {
        isLoading = true
        loadError = nil
        releaseAccess()
        do {
            let (loaded, url) = try await PlaylistService.loadSongs(for: playlist)
            songs = loaded
            accessedURL = url
        } catch {
            loadError = error.localizedDescription
            songs = []
        }
        isLoading = false
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }

    // MARK: - Game

    private func startNewGame() {
        let game = BingoGameService.create(name: "", playlist: playlist, in: modelContext)
        onGameCreated(game)
    }

    // MARK: - Helpers

    private func formatDuration(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
