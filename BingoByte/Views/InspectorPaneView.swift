import SwiftUI
import SwiftData

struct InspectorPaneView: View {
    var selectedSong: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    @Environment(\.modelContext) private var modelContext

    @State private var editingStartTime: TimeInterval = 0
    @State private var editingEndTime: TimeInterval = 0
    @State private var hasSoundByte: Bool = false

    var body: some View {
        Group {
            if let song = selectedSong {
                songDetail(song)
            } else {
                ContentUnavailableView("No Selection", systemImage: "music.note", description: Text("Select a song to view its details."))
            }
        }
        .onAppear { loadSoundByte() }
        .onChange(of: selectedSong) { loadSoundByte() }
    }

    @ViewBuilder
    private func songDetail(_ song: Song) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                nowPlayingSection(song)
                    .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal)

                soundByteSection(song)

                Divider()
                    .padding(.horizontal)

                metadataSection(song)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Now Playing / Artwork Section

    @ViewBuilder
    private func nowPlayingSection(_ song: Song) -> some View {
        VStack(spacing: 12) {
            // Album Artwork
            artworkView(song)
                .padding(.horizontal, 24)

            // Song Title & Artist
            VStack(spacing: 4) {
                Text(song.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(song.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(song.album ?? "Unknown Album")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal)

            // Playback controls (only when this song is playing)
            if audioPlayer.currentSong == song {
                playbackControls
                    .padding(.horizontal, 24)
            }
        }
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
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 4) {
            // Progress bar with sound byte markers
            ZStack {
                Slider(
                    value: Binding(
                        get: { audioPlayer.progress },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                // Sound byte overlay markers
                if hasSoundByte && audioPlayer.duration > 0 {
                    GeometryReader { geo in
                        let startFraction = editingStartTime / audioPlayer.duration
                        let endFraction = editingEndTime / audioPlayer.duration

                        // Highlighted region between markers
                        Rectangle()
                            .fill(Color.green.opacity(0.15))
                            .frame(
                                width: max(0, CGFloat(endFraction - startFraction) * geo.size.width),
                                height: geo.size.height
                            )
                            .offset(x: CGFloat(startFraction) * geo.size.width)

                        // Start marker (green)
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(startFraction) * geo.size.width - 1)

                        // End marker (red)
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(endFraction) * geo.size.width - 1)
                    }
                    .allowsHitTesting(false)
                }
            }

            // Time labels
            HStack {
                Text(audioPlayer.formattedCurrentTime)
                Spacer()
                Text(audioPlayer.formattedDuration)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            // Transport controls
            HStack(spacing: 24) {
                Button {
                    audioPlayer.seek(to: 0)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Restart")

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.borderless)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Stop")
            }
            .padding(.top, 4)
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
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(spacing: 8) {
                // Start time row
                HStack {
                    Text("Start")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    Text(Self.formatTime(editingStartTime))
                        .monospacedDigit()
                    Spacer()
                    Button("Set to Now") {
                        editingStartTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)

                // End time row
                HStack {
                    Text("End")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    Text(Self.formatTime(editingEndTime))
                        .monospacedDigit()
                    Spacer()
                    Button("Set to Now") {
                        editingEndTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)

                // Action buttons
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

                    Spacer()
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .padding(.horizontal)
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
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(spacing: 0) {
                metadataRow(label: "Title", value: song.displayTitle)
                Divider().padding(.leading)
                metadataRow(label: "Artist", value: song.artist ?? "Unknown Artist")
                Divider().padding(.leading)
                metadataRow(label: "Album", value: song.album ?? "Unknown Album")
                Divider().padding(.leading)
                metadataRow(label: "Duration", value: song.formattedDuration)
                Divider().padding(.leading)
                metadataRow(label: "Size", value: song.formattedFileSize)
                Divider().padding(.leading)
                metadataRow(label: "File", value: song.fileName)

                if hasSoundByte {
                    Divider().padding(.leading)
                    metadataRow(label: "Clip Start", value: Self.formatTime(editingStartTime))
                    Divider().padding(.leading)
                    metadataRow(label: "Clip End", value: Self.formatTime(editingEndTime))
                    Divider().padding(.leading)
                    metadataRow(label: "Clip Len", value: Self.formatTime(editingEndTime - editingStartTime))
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func loadSoundByte() {
        guard let song = selectedSong else {
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
