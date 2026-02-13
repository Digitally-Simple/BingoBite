import SwiftUI
import SwiftData

struct BingoGameInfoView: View {
    var song: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]

    @State private var editingStartTime: TimeInterval = 0
    @State private var editingEndTime: TimeInterval = 0
    @State private var hasSoundByte: Bool = false

    private var geniusAPIKey: String {
        settingsItems.first?.geniusAPIKey ?? ""
    }

    var body: some View {
        Group {
            if let song {
                songDetail(song)
            } else {
                ContentUnavailableView("No Song Playing", systemImage: "music.note", description: Text("Start playing a song to view its details."))
            }
        }
        .onAppear { loadSoundByte() }
        .onChange(of: song) { loadSoundByte() }
    }

    // MARK: - Song Detail

    @ViewBuilder
    private func songDetail(_ song: Song) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection(song)
                    .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 24)

                soundByteSection(song)

                Divider()
                    .padding(.horizontal, 24)

                metadataSection(song)

                Divider()
                    .padding(.horizontal, 24)

                SongTidbitsView(song: song, apiKey: geniusAPIKey)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private func heroSection(_ song: Song) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Artwork
            artworkView(song)
                .frame(width: 300, height: 300)

            // Title, artist, and playback controls
            VStack(alignment: .leading, spacing: 8) {
                Text(song.displayTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(3)

                Text(song.artist ?? "Unknown Artist")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(song.album ?? "Unknown Album")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                if audioPlayer.currentSong == song {
                    playbackControls(song)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func artworkView(_ song: Song) -> some View {
        Group {
            if let image = song.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Slider(
                    value: Binding(
                        get: { audioPlayer.progress },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                if hasSoundByte && audioPlayer.duration > 0 {
                    GeometryReader { geo in
                        let startFraction = editingStartTime / audioPlayer.duration
                        let endFraction = editingEndTime / audioPlayer.duration

                        Rectangle()
                            .fill(Color.green.opacity(0.15))
                            .frame(
                                width: max(0, CGFloat(endFraction - startFraction) * geo.size.width),
                                height: geo.size.height
                            )
                            .offset(x: CGFloat(startFraction) * geo.size.width)

                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(startFraction) * geo.size.width - 1)

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(endFraction) * geo.size.width - 1)
                    }
                    .allowsHitTesting(false)
                }
            }

            HStack {
                Text(audioPlayer.formattedCurrentTime)
                Spacer()
                Text(audioPlayer.formattedDuration)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button {
                    audioPlayer.skipBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.canSkipBackward)
                .help("Previous")

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.borderless)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.canSkipForward)
                .help("Next")
            }
            .padding(.top, 4)

            Button {
                audioPlayer.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Stop")
            .padding(.top, 2)
        }
    }

    // MARK: - Sound Byte Section

    @ViewBuilder
    private func soundByteSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound Byte")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Start")
                        .foregroundStyle(.secondary)
                    Text(Self.formatTime(editingStartTime))
                        .monospacedDigit()
                    Button("Set to Now") {
                        editingStartTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }

                GridRow {
                    Text("End")
                        .foregroundStyle(.secondary)
                    Text(Self.formatTime(editingEndTime))
                        .monospacedDigit()
                    Button("Set to Now") {
                        editingEndTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
            }
            .font(.callout)
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Button("Save") {
                    SoundByteService.save(
                        for: song,
                        startTime: editingStartTime,
                        endTime: editingEndTime,
                        in: modelContext
                    )
                    hasSoundByte = true
                }
                .disabled(editingEndTime <= editingStartTime)

                Button("Preview") {
                    audioPlayer.preview(song, startTime: editingStartTime, endTime: editingEndTime)
                }
                .disabled(editingEndTime <= editingStartTime)

                if hasSoundByte {
                    Button("Clear") {
                        SoundByteService.remove(for: song, in: modelContext)
                        editingStartTime = 0
                        editingEndTime = 0
                        hasSoundByte = false
                    }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                metadataGridRow(label: "Title", value: song.displayTitle)
                Divider().padding(.leading, 24)
                metadataGridRow(label: "Artist", value: song.artist ?? "Unknown Artist")
                Divider().padding(.leading, 24)
                metadataGridRow(label: "Album", value: song.album ?? "Unknown Album")
                Divider().padding(.leading, 24)
                metadataGridRow(label: "Duration", value: song.formattedDuration)
                Divider().padding(.leading, 24)
                metadataGridRow(label: "Size", value: song.formattedFileSize)
                Divider().padding(.leading, 24)
                metadataGridRow(label: "File", value: song.fileName)

                if hasSoundByte {
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Clip Start", value: Self.formatTime(editingStartTime))
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Clip End", value: Self.formatTime(editingEndTime))
                    Divider().padding(.leading, 24)
                    metadataGridRow(label: "Clip Length", value: Self.formatTime(editingEndTime - editingStartTime))
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func metadataGridRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func loadSoundByte() {
        guard let song else {
            editingStartTime = 0
            editingEndTime = 0
            hasSoundByte = false
            return
        }
        if let soundByte = SoundByteService.fetch(for: song, in: modelContext) {
            editingStartTime = soundByte.startTime
            editingEndTime = soundByte.endTime
            hasSoundByte = true
        } else {
            editingStartTime = 0
            editingEndTime = 0
            hasSoundByte = false
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
