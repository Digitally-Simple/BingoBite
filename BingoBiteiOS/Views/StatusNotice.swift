import SwiftUI

/// The transient notice iPadOS puts up for volume or the ring switch.
///
/// Nothing to confirm and nothing to dismiss: the host has already made the
/// change, and this only tells them it landed — big enough to read from across
/// the table, gone before it's in the way.
struct StatusNotice: Identifiable, Equatable {
    /// A fresh id on every post, so hitting the same toggle twice restarts the
    /// timer instead of the second one being swallowed as "no change".
    let id = UUID()
    var symbol: String
    var title: String
    var detail: String?
    /// Tints the symbol: on is the accent, off is quiet.
    var isOn: Bool

    static func autoplay(isOn: Bool, gap: TimeInterval) -> StatusNotice {
        StatusNotice(
            symbol: isOn ? "play.square.stack.fill" : "play.square.stack",
            title: isOn ? "Autoplay On" : "Autoplay Off",
            detail: isOn ? "\(format(gap)) between songs" : "You're calling each round",
            isOn: isOn
        )
    }

    static func playedRounds(isLocked: Bool) -> StatusNotice {
        StatusNotice(
            symbol: isLocked ? "lock.fill" : "lock.open.fill",
            title: isLocked ? "Played Rounds Locked" : "Played Rounds Unlocked",
            detail: isLocked
                ? "Shuffle leaves called songs alone"
                : "Shuffle can move called songs",
            isOn: isLocked
        )
    }

    /// Whole seconds where the gap is whole, which is nearly always — "5s"
    /// rather than "5.0s" for a number the host set on a half-second slider.
    private static func format(_ seconds: TimeInterval) -> String {
        seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }
}

extension View {
    /// Shows `notice` in the middle of this view and clears it on its own.
    func statusNotice(_ notice: Binding<StatusNotice?>) -> some View {
        modifier(StatusNoticeOverlay(notice: notice))
    }
}

private struct StatusNoticeOverlay: ViewModifier {
    @Binding var notice: StatusNotice?

    /// Long enough to read two short lines, short enough that it's gone before
    /// the host looks back down at the boards.
    private static let visibleDuration: Duration = .milliseconds(1400)

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if let notice {
                        StatusNoticeCard(notice: notice)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.25), value: notice?.id)
                // It floats over the transport, so it must never eat a tap
                // meant for Next Song.
                .allowsHitTesting(false)
                // The control that triggered this already announces its own
                // state, and a floating element that vanishes mid-swipe is
                // worse than nothing for VoiceOver.
                .accessibilityHidden(true)
            }
            .sensoryFeedback(.selection, trigger: notice?.id)
            .task(id: notice?.id) {
                guard notice != nil else { return }
                try? await Task.sleep(for: Self.visibleDuration)
                guard !Task.isCancelled else { return }
                notice = nil
            }
    }
}

private struct StatusNoticeCard: View {
    var notice: StatusNotice

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: notice.symbol)
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    notice.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
                )
                .frame(height: 44)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 3) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))

                if let detail = notice.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(minWidth: 200)
        .glassDeck(corner: Glassware.panelCorner)
    }
}
