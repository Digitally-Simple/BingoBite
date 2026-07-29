import AppIntents
import Foundation

/// Routes a button press on the Lock Screen back into the running game.
///
/// `LiveActivityIntent` runs inside the *app's* process, so the handler the
/// game screen installs here can drive the real transport directly. If the
/// system wakes the app just to service a press and the game screen hasn't
/// registered yet, the command waits rather than being dropped.
@MainActor
final class BingoLiveActivityCommandBus {
    static let shared = BingoLiveActivityCommandBus()

    enum Command: String {
        case nextRound
        case previousRound
        case togglePlayback
    }

    private var handler: ((Command) -> Void)?
    private var pending: [Command] = []

    private init() {}

    func setHandler(_ handler: ((Command) -> Void)?) {
        self.handler = handler
        guard let handler, !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        queued.forEach(handler)
    }

    func send(_ command: Command) {
        if let handler {
            handler(command)
        } else {
            pending.append(command)
        }
    }
}

// MARK: - Intents

/// Advances the game a round: the primary action, and the only one that changes
/// what's on every player's card.
struct BingoNextRoundIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Song"
    static var description = IntentDescription("Reveals the next song in the play order.")
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        BingoLiveActivityCommandBus.shared.send(.nextRound)
        return .result()
    }
}

struct BingoPreviousRoundIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Round"
    static var description = IntentDescription("Steps the game back one round.")
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        BingoLiveActivityCommandBus.shared.send(.previousRound)
        return .result()
    }
}

struct BingoTogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Pauses or resumes the current song.")
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        BingoLiveActivityCommandBus.shared.send(.togglePlayback)
        return .result()
    }
}
