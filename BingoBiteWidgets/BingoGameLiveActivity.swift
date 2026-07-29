import ActivityKit
import SwiftUI
import WidgetKit

/// The live game, everywhere the host isn't looking at the app: Lock Screen,
/// Dynamic Island, StandBy.
struct BingoGameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BingoGameActivityAttributes.self) { context in
            BingoLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(BingoActivityTheme.card)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.roundLabel)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("OF \(state.totalRounds)")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(BingoActivityTheme.dim)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(state.remainingLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state.tint)
                        BingoBadge(state: state)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(state.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(state.credit)
                            .font(.system(size: 11))
                            .foregroundStyle(BingoActivityTheme.dim)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        BingoMeters(state: state, compact: true)

                        HStack {
                            Text(state.statusHeadline)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(state.tint)
                            Spacer(minLength: 8)
                            BingoActivityControls(state: state, compact: true)
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                BingoIslandRing(state: state)
            } compactTrailing: {
                Text("\(max(0, state.round))/\(state.totalRounds)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(state.tint)
            } minimal: {
                BingoIslandRing(state: state)
            }
            .keylineTint(state.tint)
        }
    }
}

// MARK: - Previews

extension BingoGameActivityAttributes {
    fileprivate static var preview: BingoGameActivityAttributes {
        BingoGameActivityAttributes(gameName: "Friday Night Bingo", gameID: "preview")
    }
}

extension BingoGameActivityAttributes.ContentState {
    fileprivate static var playing: Self {
        .init(
            round: 7,
            totalRounds: 25,
            songTitle: "Bohemian Rhapsody",
            songArtist: "Queen",
            songAlbum: "A Night at the Opera",
            isPlaying: true,
            isCompleted: false,
            bingoCount: 3,
            cardCount: 12,
            canGoBack: true,
            canGoForward: true
        )
    }

    fileprivate static var paused: Self {
        var state = Self.playing
        state.isPlaying = false
        state.bingoCount = 0
        state.round = 2
        state.songTitle = "Don't Stop Me Now"
        return state
    }
}

#Preview("Lock Screen", as: .content, using: BingoGameActivityAttributes.preview) {
    BingoGameLiveActivity()
} contentStates: {
    BingoGameActivityAttributes.ContentState.playing
    BingoGameActivityAttributes.ContentState.paused
}
