import SwiftUI
import SwiftData

struct SongListView: View {
    var songs: [Song]
    var isLoading: Bool
    var errorMessage: String?
    @Binding var selection: Song.ID?
    @Binding var searchText: String
    var onPlay: (Song) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var sortOrder = [KeyPathComparator(\Song.displayTitle)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title, artist, or album", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            Group {
                if isLoading {
                    ProgressView("Scanning for songs...")
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if songs.isEmpty {
                    ContentUnavailableView(
                        "No Songs",
                        systemImage: "music.note",
                        description: Text("Select a music folder in Settings to get started.")
                    )
                } else {
                    Table(sortedSongs, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("") { song in
                            if let image = song.artworkImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.quaternary)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 24, height: 24)
                            }
                        }
                        .width(32)
                        TableColumn("Title", value: \.displayTitle)
                        TableColumn("Artist") { song in
                            Text(song.artist ?? "Unknown Artist")
                        }
                        TableColumn("Album") { song in
                            Text(song.album ?? "Unknown Album")
                        }
                        TableColumn("Duration") { song in
                            Text(song.formattedDuration)
                                .monospacedDigit()
                        }
                        .width(ideal: 70)
                        TableColumn("Start") { song in
                            Text(formattedSoundByteTime(for: song, keyPath: \.startTime))
                                .monospacedDigit()
                        }
                        .width(ideal: 70)
                        TableColumn("Stop") { song in
                            Text(formattedSoundByteTime(for: song, keyPath: \.endTime))
                                .monospacedDigit()
                        }
                        .width(ideal: 70)
                        TableColumn("Clip Length") { song in
                            Text(formattedClipLength(for: song))
                                .monospacedDigit()
                        }
                        .width(ideal: 80)
                        TableColumn("Size") { song in
                            Text(song.formattedFileSize)
                                .monospacedDigit()
                        }
                        .width(ideal: 80)
                    }
                    .contextMenu(forSelectionType: Song.ID.self) { _ in
                    } primaryAction: { selectedIDs in
                        guard let id = selectedIDs.first,
                              let song = songs.first(where: { $0.id == id }) else { return }
                        onPlay(song)
                    }
                }
            }
        }
    }

    private var sortedSongs: [Song] {
        songs.sorted(using: sortOrder)
    }

    private func soundByte(for song: Song) -> SoundByte? {
        SoundByteService.fetch(for: song, in: modelContext)
    }

    private func formattedSoundByteTime(for song: Song, keyPath: KeyPath<SoundByte, TimeInterval>) -> String {
        guard let sb = soundByte(for: song) else { return "--:--" }
        let time = sb[keyPath: keyPath]
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedClipLength(for song: Song) -> String {
        guard let sb = soundByte(for: song) else { return "--:--" }
        let duration = sb.clipDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
