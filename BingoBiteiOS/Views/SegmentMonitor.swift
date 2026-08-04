import SwiftUI

/// What the round is doing, right now.
///
/// The fade curve the player is riding, drawn against the trimmed window, with
/// a playhead crossing it and one line saying what happens next. Deliberately
/// two rows and no more: a host glancing down mid-round is reading this from
/// arm's length while someone shouts about a bingo.
struct SegmentMonitor: View {
    @ObservedObject var audioPlayer: AudioPlayerService

    private var timing: AudioPlayerService.SegmentTiming? { audioPlayer.segmentTiming }

    var body: some View {
        if let timing {
            VStack(alignment: .leading, spacing: 8) {
                SegmentTimeline(timing: timing, envelope: audioPlayer.fadeEnvelope)
                    .frame(height: 40)
                transitionLine(timing)
            }
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

/// Height shared by the fader and the meter beside it, so the two read as one
/// instrument rather than two controls that happen to be adjacent.
enum DeckLevelMetrics {
    static let columnHeight: CGFloat = 190
}

/// The live signal, as a pair of channel meters.
///
/// Its own bars rather than a fill inside the fader: a meter drawn inside the
/// control that sets the ceiling makes both harder to read — the level looks
/// like it's lagging the thing you're dragging, when really it's the music.
/// Separated, the fader is a static maximum you set and the meter is the sound
/// arriving under it.
///
/// Observes `AudioLevelMeter` rather than the player, so twenty-four updates a
/// second redraw these two bars and nothing else on the screen.
struct ChannelMeters: View {
    @ObservedObject var levels: AudioLevelMeter

    var body: some View {
        HStack(spacing: 5) {
            bar(level: levels.left)
            bar(level: levels.right)
        }
        .frame(height: DeckLevelMetrics.columnHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output level")
        .accessibilityValue(
            "Left \(Int((levels.left * 100).rounded())) percent, right \(Int((levels.right * 100).rounded())) percent"
        )
    }

    private func bar(level: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(.quaternary.opacity(0.55))

                Capsule()
                    .fill(.tint)
                    .frame(height: geo.size.height * min(max(level, 0), 1))
                    // Matches the feed rate: any slower and the bar smears
                    // through the beat it's supposed to be showing.
                    .animation(.linear(duration: 1.0 / 24.0), value: level)
            }
        }
        .frame(width: 8)
    }
}

/// The master level, as a Control Center–style column.
///
/// A static ceiling: it shows where the host set the maximum and moves only
/// when dragged. What's actually coming out is the meter beside it.
struct VerticalLevelFader: View {
    @Binding var volume: Double
    /// Called when the drag ends, so the level can be saved without writing to
    /// the store on every frame.
    var onCommit: () -> Void

    @State private var isDragging = false
    /// Where the fader was when the finger went down. The drag is relative to
    /// it — an absolute one would snap the level to wherever you happened to
    /// touch, which on a live PA is a jump scare.
    @State private var dragStartVolume: Double = 0

    private var symbol: String {
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int((volume * 100).rounded()))%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            column
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            volume = min(max(volume + (direction == .increment ? 0.05 : -0.05), 0), 1)
            onCommit()
        }
    }

    private var column: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

            ZStack(alignment: .bottom) {
                shape.fill(.quaternary.opacity(0.55))

                Rectangle()
                    .fill(.tint)
                    .frame(height: height * min(max(volume, 0), 1))

                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(.bottom, 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .clipShape(shape)
            .contentShape(shape)
            // High priority, because the expanded deck collapses on a downward
            // swipe — and pulling a fader *down* is half of what a fader is
            // for. Without this, turning the room down shuts the panel.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartVolume = volume
                        }
                        // Up is louder: translation goes positive downward.
                        volume = min(max(dragStartVolume - value.translation.height / height, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onCommit()
                    }
            )
            // Control Center swells the column while it's being held; the
            // width is what gives, so the level it's showing doesn't move.
            .scaleEffect(x: isDragging ? 1.08 : 1, y: 1)
            .animation(.smooth(duration: 0.2), value: isDragging)
        }
        .frame(width: 56, height: DeckLevelMetrics.columnHeight)
    }
}
