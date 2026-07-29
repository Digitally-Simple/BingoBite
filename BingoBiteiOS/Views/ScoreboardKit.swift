import SwiftUI

/// The scoreboard vocabulary, borrowed wholesale from the Live Activity.
///
/// The Lock Screen card turned out to be the clearest view of a game the app
/// has, so the same pieces run inside the app: one colour carries the state, a
/// gold pill is the only high-attention element, counts are set as call-board
/// ticks rather than smooth bars, and every label is a caps micro-title.
///
/// `BingoActivityTheme` and the meter views live in the shared
/// `BingoLiveActivity` folder, so these are literally the same components the
/// widget draws — not a restyled copy that can drift.
enum Scoreboard {

    /// Where a game is, and what colour it should be wearing.
    enum Status {
        case ready
        case live
        case paused
        case complete

        var tint: Color {
            switch self {
            case .ready:    BingoActivityTheme.dim
            case .live:     BingoActivityTheme.live
            case .paused:   BingoActivityTheme.paused
            case .complete: BingoActivityTheme.done
            }
        }

        var label: String {
            switch self {
            case .ready:    "Ready"
            case .live:     "Now Playing"
            case .paused:   "Paused"
            case .complete: "Complete"
            }
        }

        var symbol: String {
            switch self {
            case .ready:    "circle.dotted"
            case .live:     "waveform"
            case .paused:   "pause.fill"
            case .complete: "flag.checkered"
            }
        }

        /// The library shows games that aren't the one being played, so it only
        /// distinguishes started from finished.
        static func resting(for game: BingoGame) -> Status {
            if game.isCompleted { return .complete }
            return game.currentIndex < 0 ? .ready : .live
        }

        static func playing(for game: BingoGame, isPlaying: Bool) -> Status {
            if game.isCompleted { return .complete }
            if game.currentIndex < 0 { return .ready }
            return isPlaying ? .live : .paused
        }
    }
}

// MARK: - Atoms

/// The round marker: `R7`, set heavy and rounded so a number the host is
/// calling out loud reads from across a table.
struct RoundChip: View {
    var round: Int
    var size: CGFloat = 21
    var tint: Color = .primary

    var body: some View {
        Text(round <= 0 ? "R–" : "R\(round)")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}

/// Caps micro-title. Used anywhere a label would otherwise compete with the
/// number it's labelling.
struct CapsLabel: View {
    var text: String
    var size: CGFloat = 9
    var color: Color = .secondary

    init(_ text: String, size: CGFloat = 9, color: Color = .secondary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .tracking(0.9)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Status in a word, with its colour — the in-app twin of the Live Activity's
/// footer headline.
struct StatusPill: View {
    var status: Scoreboard.Status
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(status.label.uppercased())
                .font(.system(size: compact ? 9 : 10, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.tint.opacity(0.16)))
    }
}

/// The ambient wash the Live Activity uses to colour a surface by state without
/// painting a band across it.
struct StatusGlow: View {
    var tint: Color
    var strength: Double = 0.18

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: tint.opacity(strength), location: 0.52),
                .init(color: tint.opacity(strength * 0.25), location: 0.72),
                .init(color: .clear, location: 0.9),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Game banner

/// The game screen's answer to the Lock Screen card: round, song, the two
/// meters, and the status — everything the host needs without looking at the
/// deck. Sits above the tab content so it's true on every tab.
struct ScoreboardBanner: View {
    var game: BingoGame
    var song: Song?
    var isPlaying: Bool
    var bingoCount: Int

    private var status: Scoreboard.Status {
        Scoreboard.Status.playing(for: game, isPlaying: isPlaying)
    }

    private var round: Int { game.currentIndex + 1 }
    private var total: Int { game.shuffledSongURLStrings.count }
    private var remaining: Int { max(0, total - max(0, round)) }

    private var headline: String {
        if game.isCompleted { return song?.displayTitle ?? "Game complete" }
        if round <= 0 { return "Ready to start" }
        return song?.displayTitle ?? "Round \(round)"
    }

    private var credit: String {
        guard round > 0, let song else {
            return "\(total) songs · \(game.numberOfCards) cards"
        }
        let album = song.displayAlbum
        return album.isEmpty ? song.displayArtist : "\(song.displayArtist) · \(album)"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RoundChip(round: round, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(status.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(credit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if !game.isCompleted {
                            Text(remaining == 1 ? "1 left" : "\(remaining) left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(status.tint)
                            Text("R\(total)")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    HStack(spacing: 8) {
                        BingoBadge(
                            bingoCount: bingoCount,
                            label: bingoCount == 1 ? "1 BINGO" : "\(bingoCount) BINGOS"
                        )
                        StatusPill(status: status)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 18) {
                MeterLane(
                    title: "ROUNDS CALLED",
                    filled: max(0, round),
                    total: total,
                    tint: status.tint,
                    isMuted: round <= 0,
                    height: 7,
                    labelColor: .secondary,
                    trackColor: .primary.opacity(0.12)
                )

                MeterLane(
                    title: "CARDS ON BINGO",
                    filled: bingoCount,
                    total: game.numberOfCards,
                    tint: BingoActivityTheme.gold,
                    isMuted: bingoCount == 0,
                    height: 7,
                    labelColor: .secondary,
                    trackColor: .primary.opacity(0.12)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            StatusGlow(tint: status.tint, strength: 0.16)
        }
        .glassCard(corner: Glassware.panelCorner)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}
