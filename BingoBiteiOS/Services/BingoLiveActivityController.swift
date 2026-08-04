import ActivityKit
import Foundation

/// Keeps a single Live Activity in step with the game that's currently open.
///
/// One activity at a time, by design: a host runs one room. Opening a second
/// game retires the first card rather than stacking two on the Lock Screen.
@MainActor
enum BingoLiveActivityController {
    private static var activity: Activity<BingoGameActivityAttributes>?

    private static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Starts the card for this game, or updates it if it's already running.
    /// Also adopts an activity left behind by a previous launch so a relaunch
    /// doesn't strand one on the Lock Screen.
    static func sync(game: BingoGame, state: BingoGameActivityAttributes.ContentState) {
        guard isAvailable else { return }

        // Creation date rather than the persistent ID: it survives a relaunch,
        // which is what lets a leftover card be adopted instead of duplicated.
        let gameID = String(Int(game.creationDate.timeIntervalSince1970))

        if activity == nil {
            activity = Activity<BingoGameActivityAttributes>.activities
                .first { $0.attributes.gameID == gameID }
        }

        if let activity, activity.attributes.gameID == gameID {
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) }
            return
        }

        // A different game (or a leftover from a previous run) — retire it.
        endAll()

        let attributes = BingoGameActivityAttributes(gameName: game.name, gameID: gameID)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("BingoLiveActivityController: could not start activity — \(error.localizedDescription)")
        }
    }

    /// Leaves the finished card up briefly so the room can see the final
    /// board count, then lets the system clear it.
    static func finish(state: BingoGameActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(15 * 60)))
        }
    }

    /// Pulls the card immediately — the game screen was closed.
    static func stop() {
        activity = nil
        endAll()
    }

    private static func endAll() {
        for running in Activity<BingoGameActivityAttributes>.activities {
            Task { await running.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: - State

enum BingoLiveActivityState {

    /// Snapshots the game for the Lock Screen. Board scoring runs here rather
    /// than in the extension because the extension never sees the cards.
    static func make(
        game: BingoGame,
        song: Song?,
        isPlaying: Bool
    ) -> BingoGameActivityAttributes.ContentState {
        let cards = CardGenerator.decode(from: game.cardsData)
        let played = BingoGameService.playedSongURLs(
            shuffledSongs: game.shuffledSongKeys,
            currentIndex: max(game.currentIndex, game.highestPlayedIndex)
        )

        var bingoCount = 0
        for (index, grid) in cards.enumerated() {
            let scored = BingoGameService.scoreCard(
                card: BingoCard(id: index + 1, grid: grid),
                songKeys: game.songKeys,
                playedSongURLs: played,
                hasFreeSpace: game.hasFreeSpace
            )
            if scored.contains(where: { $0.contains(.bingo) }) { bingoCount += 1 }
        }

        return BingoGameActivityAttributes.ContentState(
            round: game.currentIndex + 1,
            totalRounds: game.shuffledSongKeys.count,
            songTitle: song?.displayTitle ?? "",
            songArtist: song?.displayArtist ?? "",
            songAlbum: song?.displayAlbum ?? "",
            isPlaying: isPlaying,
            isCompleted: game.isCompleted,
            bingoCount: bingoCount,
            cardCount: cards.count,
            canGoBack: game.currentIndex >= 0,
            canGoForward: game.currentIndex < game.shuffledSongKeys.count - 1
        )
    }
}
