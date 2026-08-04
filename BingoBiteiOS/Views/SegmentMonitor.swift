import SwiftUI

/// What the round is doing, right now, in two rows.
///
/// The top row is the segment itself: the fade curve the player is riding,
/// drawn against the trimmed window, with a playhead crossing it and one line
/// saying what happens next. The bottom row is the fader, which doubles as the
/// meter — the fill *is* the level coming out, so during a fade it moves on its
/// own and the host can see the room being taken down before they hear it.
///
/// Deliberately two rows and no more. A host glancing down mid-round is reading
/// this from arm's length while someone shouts about a bingo.
struct SegmentMonitor: View {
    @ObservedObject var audioPlayer: AudioPlayerService
    /// Called when the fader is let go, so the level can be saved without
    /// writing to the store on every frame of the drag.
    var onVolumeCommit: () -> Void

    private var timing: AudioPlayerService.SegmentTiming? { audioPlayer.segmentTiming }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let timing {
                SegmentTimeline(timing: timing, envelope: audioPlayer.fadeEnvelope)
                    .frame(height: 40)
                transitionLine(timing)
            }

            LevelFader(
                volume: $audioPlayer.masterVolume,
                level: audioPlayer.outputLevel,
                isLive: audioPlayer.isPlaying,
                onCommit: onVolumeCommit
            )
        }
    }

    // MARK: - What happens next

    /// Three facts under the curve, laid out where they happen: the fade-in
    /// window on the left, the fade-out window on the right, and in the middle
    /// the only one that moves — what the segment is doing right now.
    private func transitionLine(_ timing: AudioPlayerService.SegmentTiming) -> some View {
        HStack(spacing: 0) {
            Text(
                timing.fadeIn > 0
                    ? "In \(Format.time(timing.start))–\(Format.time(timing.fadeInEndsAt))"
                    : "Starts \(Format.time(timing.start))"
            )
            .foregroundStyle(Color.secondary)

            Spacer(minLength: 8)

            Text(fadePhrase(timing))
                .foregroundStyle(phaseTint(timing))
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(
                timing.fadeOut > 0
                    ? "Out \(Format.time(timing.fadeOutStartsAt))–\(Format.time(timing.end))"
                    : "Ends \(Format.time(timing.end))"
            )
            .foregroundStyle(Color.secondary)
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The one line that changes as the segment plays, so it's worth reading.
    private func fadePhrase(_ timing: AudioPlayerService.SegmentTiming) -> String {
        // Sitting on the out point, faded out, waiting on the host or the gap.
        if timing.remaining <= 0 { return "Segment finished" }
        if timing.isFadingIn {
            return "Fading in · \(Format.time(timing.fadeIn - timing.elapsed)) to full"
        }
        if timing.isFadingOut {
            return "Fading out · \(Format.time(timing.remaining)) left"
        }
        if let until = timing.untilFadeOut {
            return "\(Format.time(timing.remaining)) left · out in \(Format.time(until))"
        }
        return "\(Format.time(timing.remaining)) left"
    }

    private func phaseTint(_ timing: AudioPlayerService.SegmentTiming) -> Color {
        guard timing.remaining > 0 else { return .secondary }
        // The accent is reserved for "something is happening to the volume
        // right now", so it means the same thing here as it does on the curve.
        if timing.isFadingIn || timing.isFadingOut { return .accentColor }
        return .secondary
    }
}

// MARK: - Timeline

/// The fade curve drawn across the trimmed segment, with the playhead on it.
///
/// Same maths as the player: `FadeEnvelope.samples` is what the volume ticker
/// reads, so this is the shape being played rather than a picture of one.
private struct SegmentTimeline: View {
    var timing: AudioPlayerService.SegmentTiming
    var envelope: FadeEnvelope

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.4))

                // The part already played, under the curve, so the segment
                // reads as filling up.
                curve(in: size)
                    .fill(.tint.opacity(0.28))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * timing.progress)
                    }

                curve(in: size)
                    .stroke(.tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                playhead(in: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Segment")
        .accessibilityValue(
            "\(Format.time(timing.remaining)) left, fades in \(Int(timing.fadeIn)) seconds, out \(Int(timing.fadeOut)) seconds"
        )
    }

    /// The envelope as a closed path, sampled the same way the settings
    /// preview samples it.
    private func curve(in size: CGSize) -> Path {
        let duration = max(timing.duration, 0.001)
        let samples = envelope.samples(clipDuration: duration, count: 120)

        func point(_ sample: (time: TimeInterval, gain: Double)) -> CGPoint {
            CGPoint(
                x: size.width * (sample.time / duration),
                // A hair of inset top and bottom so a flat full-level line
                // isn't clipped by the container's edge.
                y: 3 + (size.height - 6) * (1 - sample.gain)
            )
        }

        var path = Path()
        guard let first = samples.first else { return path }
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: point(first))
        for sample in samples.dropFirst() { path.addLine(to: point(sample)) }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func playhead(in size: CGSize) -> some View {
        Capsule()
            .fill(.tint)
            .frame(width: 2.5)
            .offset(x: max(0, min(size.width * timing.progress, size.width - 2.5)))
            .animation(.linear(duration: 0.25), value: timing.progress)
    }
}

// MARK: - Fader

/// The master level, as a control and a meter at once.
///
/// The bright fill is the *output* — the fader scaled by wherever the envelope
/// is — so it dips during a fade without the handle moving. The handle is where
/// the host put it. Dragging anywhere on the track moves it.
private struct LevelFader: View {
    @Binding var volume: Double
    var level: Double
    var isLive: Bool
    var onCommit: () -> Void

    @State private var isDragging = false

    private var symbol: String {
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
                .contentTransition(.symbolEffect(.replace))

            track

            Text("\(Int((volume * 100).rounded()))%")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            volume = min(max(volume + (direction == .increment ? 0.05 : -0.05), 0), 1)
            onCommit()
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height: CGFloat = isDragging ? 12 : 8

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: height)

                // Where the fader sits — the ceiling the meter fills up to.
                Capsule()
                    .fill(.tint.opacity(0.28))
                    .frame(width: width * volume, height: height)

                // What's actually coming out.
                Capsule()
                    .fill(.tint)
                    .frame(width: width * min(level, 1), height: height)
                    .opacity(isLive ? 1 : 0.45)
                    .animation(.linear(duration: 1.0 / 24.0), value: level)

                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 18 : 14, height: isDragging ? 18 : 14)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: width * volume - (isDragging ? 9 : 7))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        volume = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onCommit()
                    }
            )
            .animation(.smooth(duration: 0.18), value: isDragging)
        }
        .frame(height: 22)
    }
}
