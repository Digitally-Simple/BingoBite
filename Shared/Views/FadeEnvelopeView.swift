import SwiftUI

/// Draws the volume envelope a clip will actually play at.
///
/// Samples the same `FadeEnvelope` maths the player uses, so this isn't an
/// illustration of the curve — it's the curve.
struct FadeEnvelopeView: View {
    var envelope: FadeEnvelope
    /// Clip length the envelope is drawn against. Fades are clamped to fit it,
    /// so a 3s fade on a 4s clip shows the compression rather than hiding it.
    var clipDuration: TimeInterval
    var accent: Color = .accentColor

    private var resolved: (fadeIn: TimeInterval, fadeOut: TimeInterval) {
        envelope.resolvedDurations(clipDuration: clipDuration)
    }

    /// True when the requested fades didn't fit and had to be scaled down.
    var isCompressed: Bool {
        envelope.fadeInDuration + envelope.fadeOutDuration > clipDuration && clipDuration > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    grid(in: geo.size)
                    fadeRegions(in: geo.size)
                    curve(in: geo.size)
                }
            }
            .frame(height: 110)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )

            axisLabels
        }
    }

    // MARK: - Layers

    private func grid(in size: CGSize) -> some View {
        Path { path in
            // Quarter lines give the eye something to judge the curve against.
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * (1 - fraction)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(.quaternary, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    /// Tints the fade-in and fade-out spans so their length is readable
    /// without counting gridlines.
    private func fadeRegions(in size: CGSize) -> some View {
        let total = max(clipDuration, 0.001)
        let inWidth = size.width * (resolved.fadeIn / total)
        let outWidth = size.width * (resolved.fadeOut / total)

        return ZStack(alignment: .leading) {
            if inWidth > 0 {
                Rectangle()
                    .fill(accent.opacity(0.12))
                    .frame(width: inWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if outWidth > 0 {
                Rectangle()
                    .fill(accent.opacity(0.12))
                    .frame(width: outWidth)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func curve(in size: CGSize) -> some View {
        let samples = envelope.samples(clipDuration: max(clipDuration, 0.001))
        let total = max(clipDuration, 0.001)

        func point(_ sample: (time: TimeInterval, gain: Double)) -> CGPoint {
            CGPoint(
                x: size.width * (sample.time / total),
                y: size.height * (1 - sample.gain)
            )
        }

        return ZStack {
            // Filled area first so the stroke reads on top of it.
            Path { path in
                guard let first = samples.first else { return }
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: point(first))
                for sample in samples.dropFirst() { path.addLine(to: point(sample)) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Path { path in
                guard let first = samples.first else { return }
                path.move(to: point(first))
                for sample in samples.dropFirst() { path.addLine(to: point(sample)) }
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    private var axisLabels: some View {
        HStack {
            Text(resolved.fadeIn > 0 ? "In \(Self.format(resolved.fadeIn))" : "No fade in")
            Spacer()
            Text(Self.format(clipDuration))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(resolved.fadeOut > 0 ? "Out \(Self.format(resolved.fadeOut))" : "No fade out")
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    static func format(_ seconds: TimeInterval) -> String {
        seconds < 10
            ? String(format: "%.1fs", seconds)
            : String(format: "%.0fs", seconds)
    }
}
