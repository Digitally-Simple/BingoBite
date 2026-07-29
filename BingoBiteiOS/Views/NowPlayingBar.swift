import SwiftUI

/// Floating glass transport pinned above the bottom safe area. Tapping the
/// track opens the full song inspector.
struct NowPlayingBar: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayerService
    var onTap: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        ArtworkView(data: song.artworkData, corner: 10)
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(song.displayArtist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if audioPlayer.isPreviewing {
                            Label("Clip", systemImage: "scissors")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        }

                        Text("\(audioPlayer.formattedCurrentTime) / \(audioPlayer.formattedDuration)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                transportControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(alignment: .bottom) { progressLine }
            .interactiveGlassCard(corner: 28)
            .glassEffectID("now-playing", in: glassNamespace)
        }
        .frame(maxWidth: 760)
    }

    private var transportControls: some View {
        HStack(spacing: 6) {
            Button("Previous", systemImage: "backward.fill") {
                audioPlayer.skipBackward()
            }
            .disabled(!audioPlayer.canSkipBackward)

            Button(
                audioPlayer.isPlaying ? "Pause" : "Play",
                systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill"
            ) {
                audioPlayer.togglePlayPause()
            }
            .font(.title3)

            Button("Next", systemImage: "forward.fill") {
                audioPlayer.skipForward()
            }
            .disabled(!audioPlayer.canSkipForward)

            Button("Stop", systemImage: "xmark") {
                audioPlayer.stop()
            }
            .font(.subheadline)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    /// Thin progress hairline along the bottom edge of the bar.
    private var progressLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * audioPlayer.progress, height: 3)
                .animation(.linear(duration: 0.25), value: audioPlayer.progress)
        }
        .frame(height: 3)
        .padding(.horizontal, 18)
    }
}
