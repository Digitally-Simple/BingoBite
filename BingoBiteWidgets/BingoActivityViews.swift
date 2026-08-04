import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Controls

/// Transport for the Lock Screen. Previous and play/pause stay quiet; Next is
/// the filled call to action, because it's the button that actually moves the
/// game and rescores every board.
struct BingoActivityControls: View {
    var state: BingoGameActivityAttributes.ContentState
    var compact = false
    /// Tap targets stay 28pt across both presentations; the Lock Screen card's
    /// height budget can't afford more and the Island's is tighter still.
    var height: CGFloat = 28

    var body: some View {
        if state.isCompleted {
            Label("Complete", systemImage: "flag.checkered")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BingoActivityTheme.dim)
        } else {
            HStack(spacing: 8) {
                Button(intent: BingoPreviousRoundIntent()) {
                    glyph("backward.fill")
                }
                .disabled(!state.canGoBack)
                .opacity(state.canGoBack ? 1 : 0.35)

                Button(intent: BingoTogglePlaybackIntent()) {
                    glyph(state.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(state.round <= 0)
                .opacity(state.round > 0 ? 1 : 0.35)

                Button(intent: BingoNextRoundIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11, weight: .bold))
                        if !compact {
                            Text("Next")
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                                // Without this the call-to-action is the first
                                // thing the row compresses, and "Next" becomes
                                // "N…" while the status line keeps its width.
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(BingoActivityTheme.card)
                    .padding(.horizontal, compact ? 10 : 12)
                    .frame(height: height)
                    .background(Capsule().fill(BingoActivityTheme.gold))
                }
                .disabled(!state.canGoForward)
                .opacity(state.canGoForward ? 1 : 0.35)
            }
            .buttonStyle(.plain)
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: height, height: height)
            .background(Circle().fill(BingoActivityTheme.control))
    }
}

// MARK: - Lock Screen card

/// The system caps this card at roughly 160pt and clips whatever doesn't fit —
/// silently, from both edges at once, so an overlong layout loses the top of
/// the header and the bottom of the transport rather than scrolling or
/// shrinking. Every size here is chosen against that budget: the meters run
/// side by side instead of stacked, and the bingo pill rides the footer with
/// the status rather than costing the hero a second line.
struct BingoLockScreenView: View {
    var attributes: BingoGameActivityAttributes
    var state: BingoGameActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                header
                hero
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            BingoMeters(state: state, height: 5, isSideBySide: true, labelSpacing: 2)
                .padding(.horizontal, 16)
                .padding(.top, 9)

            footer
                .padding(.horizontal, 16)
                .padding(.top, 9)
                .padding(.bottom, 10)
        }
        // The status colour bleeds through the identity half and dies out
        // across the track, so the card reads as one surface with weather in
        // it rather than two stacked bands.
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: state.tint.opacity(0.20), location: 0.46),
                    .init(color: state.tint.opacity(0.05), location: 0.66),
                    .init(color: .clear, location: 0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(BingoActivityTheme.card)
                .frame(width: 15, height: 15)
                .background(Circle().fill(state.tint))

            Text(attributes.gameName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BingoActivityTheme.dim)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("BINGOBITE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.34))
        }
    }

    /// Round and total bookend the row the way origin and destination do,
    /// with the song carrying the accent colour in between.
    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(state.roundLabel)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(state.headline)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(state.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(state.credit)
                    .font(.system(size: 11))
                    .foregroundStyle(BingoActivityTheme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !state.remainingLabel.isEmpty {
                    Text(state.remainingLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.tint)
                        .lineLimit(1)
                }

                if !state.totalLabel.isEmpty {
                    Text(state.totalLabel)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.statusHeadline)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !state.statusDetail.isEmpty {
                    Text(state.statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(BingoActivityTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            // The bingo pill sits with the status rather than under the round
            // count: the footer's height is set by the transport buttons, so a
            // pill costs nothing here and a whole line there.
            BingoBadge(state: state)

            Spacer(minLength: 8)

            BingoActivityControls(state: state)
        }
    }
}

// MARK: - Dynamic Island

/// The progress ring used in the compact and minimal presentations — the
/// equivalent of Flighty's plane inside its ring.
struct BingoIslandRing: View {
    var state: BingoGameActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .stroke(BingoActivityTheme.faint, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, state.progress))
                .stroke(state.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: state.isCompleted ? "flag.checkered" : "music.note")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(state.tint)
        }
        .frame(width: 20, height: 20)
    }
}
