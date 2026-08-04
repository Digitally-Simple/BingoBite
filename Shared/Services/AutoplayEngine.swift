import Foundation
import Combine

/// Runs a game hands-free: when a round's segment ends, wait the configured
/// gap, then move to the next one.
///
/// The point is what the host does *while* it runs. They listen for a shout,
/// look down at the boards to see which card numbers hit, and never have to
/// reach for the transport — but they can, at any moment, because arming
/// autoplay changes nothing about how the manual controls behave.
///
/// The engine owns only the waiting. It doesn't know what a round is, what a
/// song is, or how to score a board: `onAdvance` is handed in by the screen
/// that does.
@MainActor
final class AutoplayEngine: ObservableObject {

    /// Armed or not. Turning it off drops a gap already counting down —
    /// pressing the button is how a host stops the show mid-silence.
    @Published var isEnabled = false {
        didSet {
            guard oldValue != isEnabled, !isEnabled else { return }
            cancelPending()
        }
    }

    /// Seconds left in the gap, or nil when nothing is pending. Published so
    /// the screen can count it down where the host can see it.
    @Published private(set) var secondsRemaining: TimeInterval?

    /// True when a segment finished while autoplay was off and nothing has
    /// moved the game since — so arming it now can pick up from there instead
    /// of waiting for a round that already ended to end again.
    @Published private(set) var isAwaitingAdvance = false

    /// Called when the gap runs out. Set by the game screen.
    var onAdvance: (() -> Void)?

    private var timer: Timer?
    private var deadline: Date?

    /// How often the countdown updates. A host reads this as whole seconds, so
    /// anything finer is wasted; anything coarser makes the last second lie.
    private static let tickInterval: TimeInterval = 0.1

    // MARK: - Game events

    /// A round's segment played itself out.
    ///
    /// `canAdvance` is false on the last round, where the right thing is to
    /// stop rather than to sit counting down toward nothing.
    func segmentFinished(gap: TimeInterval, canAdvance: Bool) {
        guard canAdvance else {
            isAwaitingAdvance = false
            isEnabled = false
            return
        }
        guard isEnabled else {
            isAwaitingAdvance = true
            return
        }
        scheduleAdvance(after: gap)
    }

    /// A round started — by hand or by autoplay. Anything pending belonged to
    /// the round before it.
    func roundStarted() {
        isAwaitingAdvance = false
        cancelPending()
    }

    /// Starts the gap. A gap of zero advances on the spot rather than going
    /// through a timer that would fire a frame later.
    func scheduleAdvance(after gap: TimeInterval) {
        cancelPending()
        isAwaitingAdvance = false

        guard gap > 0 else {
            onAdvance?()
            return
        }

        let deadline = Date().addingTimeInterval(gap)
        self.deadline = deadline
        secondsRemaining = gap
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    /// Drops a pending gap without advancing. The host took the wheel.
    func cancelPending() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        secondsRemaining = nil
    }

    // MARK: - Countdown

    private func tick() {
        guard let deadline else {
            cancelPending()
            return
        }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            cancelPending()
            onAdvance?()
            return
        }
        secondsRemaining = remaining
    }

    /// The countdown as whole seconds, rounded up so it reads 3, 2, 1 rather
    /// than spending most of its life on 0.
    var displayedSecondsRemaining: Int? {
        guard let secondsRemaining else { return nil }
        return max(1, Int(secondsRemaining.rounded(.up)))
    }
}
