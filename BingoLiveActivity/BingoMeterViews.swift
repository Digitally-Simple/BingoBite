import SwiftUI

// MARK: - Meters

/// A straight run of ticks, one per round or per card — a call board rather
/// than a progress bar. Past a threshold the ticks would be thinner than the
/// gaps between them, so it falls back to a solid bar.
///
/// Shared by the Live Activity and the app, so a meter means the same thing on
/// the Lock Screen as it does on the game screen.
struct SegmentedMeter: View {
    var filled: Int
    var total: Int
    var tint: Color
    var height: CGFloat = 6
    var trackColor: Color = BingoActivityTheme.faint
    /// A tick narrower than this stops reading as a tick and starts reading as
    /// noise, so instead of shrinking forever, long games bucket several rounds
    /// into each tick.
    var minTickWidth: CGFloat = 4
    /// Without a ceiling, a ten-card lane stretched to the same width as a
    /// hundred-round lane turns into slabs. Capping the tick and spending the
    /// slack on the gaps keeps both lanes full width and the same family.
    var maxTickWidth: CGFloat = 14
    var gap: CGFloat = 2

    /// Rounds-per-tick candidates. Bucketing to one of these keeps a tick
    /// meaning something a host can hold in their head — "two rounds a tick" —
    /// instead of an arbitrary 1.63.
    private static let steps = [1, 2, 5, 10, 20, 25, 50, 100]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let step = roundsPerTick(for: width)
            let ticks = max(1, Int(ceil(Double(max(total, 1)) / Double(step))))
            let tickWidth = tickWidth(for: width, ticks: ticks)
            let spacing = ticks > 1
                ? max(gap, (width - CGFloat(ticks) * tickWidth) / CGFloat(ticks - 1))
                : 0

            HStack(spacing: spacing) {
                ForEach(0..<ticks, id: \.self) { index in
                    // The tick covering the current round fills partially, so a
                    // 100-round game still visibly moves every single round
                    // rather than jumping once every other one.
                    let consumed = Double(filled) - Double(index * step)
                    MeterTick(
                        fill: min(1, max(0, consumed / Double(step))),
                        tint: tint,
                        trackColor: trackColor
                    )
                    .frame(width: tickWidth)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.3), value: filled)
    }

    private func tickWidth(for width: CGFloat, ticks: Int) -> CGFloat {
        guard ticks > 0, width > 0 else { return minTickWidth }
        let even = (width - CGFloat(max(ticks - 1, 0)) * gap) / CGFloat(ticks)
        return min(maxTickWidth, max(minTickWidth, even))
    }

    /// One tick per round whenever they fit; otherwise the smallest bucket that
    /// does. Shrinking the ticks instead would turn a long game into a dotted
    /// line — legible as a bar, but no longer a call board.
    private func roundsPerTick(for width: CGFloat) -> Int {
        guard total > 0, width > 0 else { return 1 }
        let capacity = max(1, Int((width + gap) / (minTickWidth + gap)))
        for step in Self.steps where Int(ceil(Double(total) / Double(step))) <= capacity {
            return step
        }
        return Int(ceil(Double(total) / Double(capacity)))
    }
}

/// One tick: a track that fills from the leading edge. Whole ticks look binary,
/// which is what makes the strip read as a call board rather than a bar.
private struct MeterTick: View {
    var fill: Double
    var tint: Color
    var trackColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(trackColor)

                if fill > 0 {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        // Never let a just-started tick vanish to a hairline.
                        .frame(width: max(geo.size.width * fill, 1.5))
                }
            }
        }
    }
}

/// One labelled meter: a caps title on the left, the count on the right in the
/// lane's own colour, and the ticks underneath.
struct MeterLane: View {
    var title: String
    var filled: Int
    var total: Int
    var tint: Color
    /// Zero-state counts read as noise in full colour, so they stay grey.
    var isMuted: Bool = false
    var height: CGFloat = 6
    var labelColor: Color = BingoActivityTheme.dim
    var trackColor: Color = BingoActivityTheme.faint

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.9)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(filled) / \(total)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isMuted ? labelColor : tint)
            }

            SegmentedMeter(filled: filled, total: total, tint: tint, height: height, trackColor: trackColor)
        }
    }
}

/// The two things a host is tracking: how far through the play order the room
/// is, and how many cards are already live. Stacking them makes the race
/// between the two legible at a glance.
struct BingoMeters: View {
    var state: BingoGameActivityAttributes.ContentState
    var compact = false
    var height: CGFloat = 6
    var labelColor: Color = BingoActivityTheme.dim
    var trackColor: Color = BingoActivityTheme.faint

    var body: some View {
        VStack(spacing: compact ? 5 : 7) {
            MeterLane(
                title: "ROUNDS CALLED",
                filled: max(0, state.round),
                total: state.totalRounds,
                tint: state.tint,
                isMuted: state.round <= 0,
                height: height,
                labelColor: labelColor,
                trackColor: trackColor
            )

            MeterLane(
                title: "CARDS ON BINGO",
                filled: state.bingoCount,
                total: state.cardCount,
                tint: BingoActivityTheme.gold,
                isMuted: state.bingoCount == 0,
                height: height,
                labelColor: labelColor,
                trackColor: trackColor
            )
        }
    }
}

// MARK: - Badges

/// The one high-attention element on a card. A bingo is the thing a host needs
/// to spot without reading, so it gets the gold pill; with none yet the slot
/// stays empty and the gold meter carries the zero.
struct BingoBadge: View {
    var bingoCount: Int
    var label: String
    var compact = false

    var body: some View {
        if bingoCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 7 : 8, weight: .black))
                Text(compact ? "\(bingoCount)" : label)
                    .font(.system(size: compact ? 10 : 11, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(BingoActivityTheme.card)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(BingoActivityTheme.gold))
        }
    }
}

extension BingoBadge {
    init(state: BingoGameActivityAttributes.ContentState, compact: Bool = false) {
        self.init(bingoCount: state.bingoCount, label: state.bingoLabel, compact: compact)
    }
}
