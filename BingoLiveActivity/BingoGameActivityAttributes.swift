import ActivityKit
import Foundation

/// The shape of a live bingo game as it appears *outside* the app — Lock
/// Screen, Dynamic Island, StandBy.
///
/// Compiled into both the iPad app and the widget extension, so it can hold
/// nothing but plain values: no SwiftData, no file access, no artwork blobs
/// (ActivityKit budgets the whole payload at a few kilobytes).
struct BingoGameActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 1-based round. `0` means the host hasn't revealed a song yet.
        var round: Int
        var totalRounds: Int
        var songTitle: String
        var songArtist: String
        var songAlbum: String
        var isPlaying: Bool
        var isCompleted: Bool
        /// Cards holding at least one completed line.
        var bingoCount: Int
        var cardCount: Int
        var canGoBack: Bool
        var canGoForward: Bool
    }

    /// Fixed for the life of the activity — the game this card is tracking.
    var gameName: String
    var gameID: String
}

// MARK: - Display

extension BingoGameActivityAttributes.ContentState {

    /// What the card is saying at a glance. Drives colour everywhere, the same
    /// way a flight's on-time/late state does.
    enum Phase {
        case ready      // no song revealed yet
        case playing
        case paused
        case completed
    }

    var phase: Phase {
        if isCompleted { return .completed }
        if round <= 0 { return .ready }
        return isPlaying ? .playing : .paused
    }

    /// Rounds still to be called.
    var remaining: Int {
        max(0, totalRounds - max(0, round))
    }

    /// 0…1 across the play order, used for the round track.
    var progress: Double {
        guard totalRounds > 0 else { return 0 }
        return min(1, max(0, Double(max(0, round)) / Double(totalRounds)))
    }

    /// Airport-code equivalent for where the game is: `R7`.
    var roundLabel: String {
        round <= 0 ? "R–" : "R\(round)"
    }

    /// …and where it's headed. Dropped at the end, where it would just repeat
    /// the round the game finished on.
    var totalLabel: String {
        isCompleted ? "" : "R\(totalRounds)"
    }

    /// Empty once the game is over — the total alone says it.
    var remainingLabel: String {
        switch phase {
        case .completed: return ""
        case .ready:     return "\(totalRounds) to call"
        default:         return remaining == 1 ? "1 left" : "\(remaining) left"
        }
    }

    /// The headline — the song the room is listening to.
    var headline: String {
        switch phase {
        case .ready:     return "Ready to start"
        case .completed: return songTitle.isEmpty ? "Game complete" : songTitle
        default:         return songTitle.isEmpty ? "Round \(round)" : songTitle
        }
    }

    /// Artist and album together, the way the host reads them out.
    var credit: String {
        switch phase {
        case .ready:
            return "\(totalRounds) songs in the play order"
        default:
            if songArtist.isEmpty { return songAlbum }
            if songAlbum.isEmpty { return songArtist }
            return "\(songArtist) · \(songAlbum)"
        }
    }

    /// Bottom-bar headline — the equivalent of "Gate Departure in 1h 1m".
    var statusHeadline: String {
        switch phase {
        case .ready:     return "Ready to Start"
        case .playing:   return "Now Playing"
        case .paused:    return "Paused"
        case .completed: return "Game Complete"
        }
    }

    /// Empty while the game is running — the meters carry the numbers, so a
    /// second line here would only repeat them. Reserved for the two states
    /// the meters can't explain on their own.
    var statusDetail: String {
        switch phase {
        case .ready:     return "Tap Next to reveal round 1"
        case .completed: return "Final boards saved"
        default:         return ""
        }
    }

    var bingoLabel: String {
        bingoCount == 1 ? "1 BINGO" : "\(bingoCount) BINGOS"
    }
}
