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

/// The ambient wash that colours a surface by state.
///
/// Light spills in from the top edge and fades out — one direction, never
/// brightening again. An earlier version peaked in the middle, which on a short
/// wide banner read as a smear floating across the card rather than as the
/// surface being lit. Clipped to the card's own shape so the wash can't square
/// off the corners it sits behind.
struct StatusGlow: View {
    var tint: Color
    var strength: Double = 0.18
    var corner: CGFloat = Glassware.panelCorner

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(strength), location: 0),
                .init(color: tint.opacity(strength * 0.5), location: 0.4),
                .init(color: tint.opacity(strength * 0.16), location: 0.72),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
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
    private var total: Int { game.shuffledSongKeys.count }
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

// MARK: - Analytics

/// The analytics tab, drawn in the visual language of Bevel's health
/// dashboards: quiet cards on a grouped canvas, one gray icon-and-title header
/// per card, big semibold numbers with gray units, and charts where color is
/// reserved for the data itself — a value-tinted line, a pale range band, and
/// a single glowing "now" dot.
struct GameAnalyticsView: View {
    var game: BingoGame

    @State private var chartSeries: BevelForecastSeries = .cards

    var body: some View {
        let analytics = BingoPredictionAnalytics(game: game)
        ScrollView {
            VStack(spacing: 14) {
                BevelForecastHero(analytics: analytics)

                HStack(alignment: .top, spacing: 14) {
                    BevelMetricCard.bingosPresent(analytics: analytics)
                    BevelMetricCard.linesLive(analytics: analytics)
                }

                BevelQuickStats(analytics: analytics)

                BevelForecastChartCard(analytics: analytics, series: $chartSeries)

                HStack(alignment: .top, spacing: 14) {
                    BevelWaveWaffle(analytics: analytics)
                    BevelUpcomingWavesTable(analytics: analytics)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(BevelTheme.canvas)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct BingoPredictionAnalytics {
    struct RoundSnapshot: Identifiable {
        var id: Int { round }
        let round: Int
        let cardsOnBingo: Int
        let bingoLines: Int
    }

    let totalRounds: Int
    let cardCount: Int
    let currentRound: Int
    let calledThroughRound: Int
    let snapshots: [RoundSnapshot]

    init(game: BingoGame) {
        let cards = CardGenerator.decode(from: game.cardsData)
            .enumerated()
            .map { BingoCard(id: $0.offset + 1, grid: $0.element) }
        totalRounds = game.shuffledSongKeys.count
        cardCount = cards.count
        currentRound = max(0, game.currentIndex + 1)
        calledThroughRound = max(0, min(max(game.currentIndex, game.highestPlayedIndex) + 1, game.shuffledSongKeys.count))

        var nextSnapshots: [RoundSnapshot] = []
        var played = Set<String>()

        for round in 0...game.shuffledSongKeys.count {
            if round > 0 {
                played.insert(game.shuffledSongKeys[round - 1])
            }

            var cardsOnBingo = 0
            var bingoLines = 0
            for card in cards {
                let stats = BingoGameService.cardStats(
                    card: card,
                    songKeys: game.songKeys,
                    playedSongURLs: played,
                    hasFreeSpace: game.hasFreeSpace
                )
                if stats.bingoCount > 0 { cardsOnBingo += 1 }
                bingoLines += stats.bingoCount
            }

            nextSnapshots.append(
                RoundSnapshot(round: round, cardsOnBingo: cardsOnBingo, bingoLines: bingoLines)
            )
        }

        snapshots = nextSnapshots
    }

    var currentRoundLabel: String {
        currentRound == 0 ? "Ready" : "R\(currentRound)"
    }

    var calledThroughLabel: String {
        calledThroughRound == 0 ? "0" : "R\(calledThroughRound)"
    }

    var remainingRounds: Int {
        max(0, totalRounds - calledThroughRound)
    }

    var currentSnapshot: RoundSnapshot {
        snapshots[safe: calledThroughRound] ?? RoundSnapshot(round: 0, cardsOnBingo: 0, bingoLines: 0)
    }

    var currentCardsOnBingo: Int {
        currentSnapshot.cardsOnBingo
    }

    var currentBingoLines: Int {
        currentSnapshot.bingoLines
    }

    var finalCardsOnBingo: Int {
        snapshots.last?.cardsOnBingo ?? 0
    }

    var finalBingoLines: Int {
        snapshots.last?.bingoLines ?? 0
    }

    var firstBingoRound: Int? {
        snapshots.first(where: { $0.round > 0 && $0.cardsOnBingo > 0 })?.round
    }

    var nextBingoRound: Int? {
        snapshots.first {
            $0.round > calledThroughRound && $0.cardsOnBingo > currentCardsOnBingo
        }?.round
    }

    var firstBingoETA: String {
        guard let firstBingoRound else { return "No hit" }
        if firstBingoRound <= calledThroughRound { return "Hit R\(firstBingoRound)" }
        let delta = firstBingoRound - calledThroughRound
        return delta == 1 ? "1 round" : "\(delta) rounds"
    }

    var nextBingoETA: String {
        guard let nextBingoRound else { return "No new wave" }
        let delta = nextBingoRound - calledThroughRound
        return delta == 1 ? "Next round" : "In \(delta) rounds"
    }

    var topWave: RoundSnapshot? {
        zip(snapshots, snapshots.dropFirst()).map { previous, current in
            RoundSnapshot(
                round: current.round,
                cardsOnBingo: current.cardsOnBingo - previous.cardsOnBingo,
                bingoLines: current.bingoLines - previous.bingoLines
            )
        }
        .max { lhs, rhs in
            if lhs.cardsOnBingo == rhs.cardsOnBingo { return lhs.bingoLines < rhs.bingoLines }
            return lhs.cardsOnBingo < rhs.cardsOnBingo
        }
    }

    var upcomingWaves: [RoundSnapshot] {
        zip(snapshots, snapshots.dropFirst()).compactMap { previous, current in
            let cardDelta = current.cardsOnBingo - previous.cardsOnBingo
            let lineDelta = current.bingoLines - previous.bingoLines
            guard current.round > calledThroughRound, (cardDelta > 0 || lineDelta > 0) else { return nil }
            return RoundSnapshot(round: current.round, cardsOnBingo: cardDelta, bingoLines: lineDelta)
        }
        .prefix(7)
        .map { $0 }
    }
}

// MARK: - Bevel kit

/// The Bevel palette: a grouped canvas, plain white cards, and a small set of
/// saturated-but-soft accents. Color never decorates a container — it belongs
/// to values, status lines, and chart ink.
private enum BevelTheme {
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)

    static let green = Color(red: 0.28, green: 0.78, blue: 0.35)
    static let mint = Color(red: 0.62, green: 0.89, blue: 0.66)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.10)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.10)
    static let red = Color(red: 1.00, green: 0.25, blue: 0.16)
    static let blue = Color(red: 0.30, green: 0.55, blue: 0.95)

    static let corner: CGFloat = 26

    /// The strain-chart ramp: low values are yellow, warm through orange, and
    /// peaks go red. `t` is the value as a fraction of the axis maximum.
    static func heat(_ t: Double) -> Color {
        let clamped = min(max(t, 0), 1)
        if clamped < 0.5 {
            return lerp((1.00, 0.80, 0.10), (1.00, 0.58, 0.10), clamped * 2)
        }
        return lerp((1.00, 0.58, 0.10), (1.00, 0.25, 0.16), (clamped - 0.5) * 2)
    }

    private static func lerp(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double),
        _ t: Double
    ) -> Color {
        Color(
            red: a.0 + (b.0 - a.0) * t,
            green: a.1 + (b.1 - a.1) * t,
            blue: a.2 + (b.2 - a.2) * t
        )
    }
}

private extension View {
    /// A Bevel card: flat fill, big continuous corner, one soft diffuse shadow.
    /// No borders, no gradients, no glass.
    func bevelCard() -> some View {
        background {
            RoundedRectangle(cornerRadius: BevelTheme.corner, style: .continuous)
                .fill(BevelTheme.card)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
        }
    }
}

/// Every Bevel card opens the same way: a small gray symbol and a gray title.
private struct BevelCardHeader: View {
    var symbol: String
    var title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

/// The status line under a big value: a small filled symbol and short phrase,
/// both in the status color ("Normal range", "Above target").
private struct BevelStatusLine: View {
    var symbol: String
    var text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
    }
}

/// The chart endpoint: a white-ringed dot in the line color with a soft halo,
/// marking "now".
private struct BevelGlowDot: View {
    var tint: Color
    var size: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: size * 2.6, height: size * 2.6)
                .blur(radius: 2)
            Circle()
                .fill(BevelTheme.card)
                .frame(width: size + 6, height: size + 6)
                .shadow(color: tint.opacity(0.45), radius: 4)
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Hero

private struct BevelForecastHero: View {
    var analytics: BingoPredictionAnalytics

    private var ringProgress: Double {
        guard let first = analytics.firstBingoRound, first > 0 else { return 0 }
        return min(1, max(0, Double(min(analytics.calledThroughRound, first)) / Double(first)))
    }

    private var ringValue: String {
        guard let first = analytics.firstBingoRound else { return "—" }
        return "R\(first)"
    }

    private var headline: String {
        if let first = analytics.firstBingoRound {
            if first <= analytics.calledThroughRound {
                return "The first bingo landed in round \(first)."
            }
            return "First bingo projected in round \(first)."
        }
        return "No card reaches bingo with this song order."
    }

    var body: some View {
        HStack(spacing: 26) {
            BevelRing(
                progress: ringProgress,
                value: ringValue,
                caption: "First bingo",
                tint: ringProgress >= 1 ? BevelTheme.green : BevelTheme.orange
            )
            .frame(width: 164, height: 164)

            VStack(alignment: .leading, spacing: 14) {
                BevelCardHeader(symbol: "sparkles", title: "Bingo Forecast")

                Text(headline)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 0) {
                    BevelHeroStat(value: analytics.nextBingoETA, label: "Next wave", tint: BevelTheme.blue)
                    BevelHeroDivider()
                    BevelHeroStat(
                        value: "\(analytics.finalCardsOnBingo)/\(analytics.cardCount)",
                        label: "Final cards",
                        tint: BevelTheme.green
                    )
                    BevelHeroDivider()
                    BevelHeroStat(value: "\(analytics.finalBingoLines)", label: "Final lines", tint: BevelTheme.orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard()
    }
}

private struct BevelHeroStat: View {
    var value: String
    var label: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BevelHeroDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1, height: 36)
            .padding(.trailing, 16)
    }
}

/// The neumorphic score ring: soft white disc, quiet gray track, one colored
/// arc with rounded caps and a gentle glow, value stacked in the middle.
private struct BevelRing: View {
    var progress: Double
    var value: String
    var caption: String
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(BevelTheme.card)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

            Circle()
                .stroke(.primary.opacity(0.06), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .padding(13)

            if progress > 0.001 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [tint.opacity(0.45), tint]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(max(40, 360 * min(1, progress)))
                        ),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.4), radius: 6)
                    .padding(13)
            }

            Circle()
                .fill(BevelTheme.card)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .padding(27)

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(34)
        }
    }
}

// MARK: - Metric cards

/// A Bevel metric card: gray header, big value with gray unit, colored status
/// line, and a sparkline with a pale range band and a glowing endpoint.
private struct BevelMetricCard: View {
    var symbol: String
    var title: String
    var value: String
    var unit: String
    var statusSymbol: String
    var statusText: String
    var statusTint: Color
    var projection: [Double]
    var playedCount: Int

    static func bingosPresent(analytics: BingoPredictionAnalytics) -> BevelMetricCard {
        let current = analytics.currentCardsOnBingo
        let final = analytics.finalCardsOnBingo
        let status: (String, String, Color)
        if final == 0 {
            status = ("minus.circle.fill", "None projected", Color.secondary)
        } else if current >= final {
            status = ("checkmark.circle.fill", "All waves in", BevelTheme.green)
        } else if current > 0 {
            status = ("arrow.up.circle.fill", "+\(final - current) coming", BevelTheme.blue)
        } else {
            status = ("arrow.up.circle.fill", "First at R\(analytics.firstBingoRound ?? 0)", BevelTheme.blue)
        }
        return BevelMetricCard(
            symbol: "star",
            title: "Bingos Present",
            value: "\(current)",
            unit: "of \(analytics.cardCount) cards",
            statusSymbol: status.0,
            statusText: status.1,
            statusTint: status.2,
            projection: analytics.snapshots.map { Double($0.cardsOnBingo) },
            playedCount: analytics.calledThroughRound + 1
        )
    }

    static func linesLive(analytics: BingoPredictionAnalytics) -> BevelMetricCard {
        let current = analytics.currentBingoLines
        let final = analytics.finalBingoLines
        let status: (String, String, Color)
        if final == 0 {
            status = ("minus.circle.fill", "None projected", Color.secondary)
        } else if current >= final {
            status = ("checkmark.circle.fill", "All lines in", BevelTheme.green)
        } else {
            status = ("arrow.up.circle.fill", "+\(final - current) coming", BevelTheme.blue)
        }
        return BevelMetricCard(
            symbol: "line.3.horizontal",
            title: "Lines Live",
            value: "\(current)",
            unit: "of \(final) total",
            statusSymbol: status.0,
            statusText: status.1,
            statusTint: status.2,
            projection: analytics.snapshots.map { Double($0.bingoLines) },
            playedCount: analytics.calledThroughRound + 1
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                BevelCardHeader(symbol: symbol, title: title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                BevelStatusLine(symbol: statusSymbol, text: statusText, tint: statusTint)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            BevelSparkline(values: projection, playedCount: playedCount, tint: BevelTheme.green)
                .frame(minWidth: 70, maxWidth: 180)
                .frame(height: 84)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard()
    }
}

/// The little metric chart: the whole game as a faint gray line, the called
/// portion drawn over it in green, and a glowing dot at now.
private struct BevelSparkline: View {
    var values: [Double]
    var playedCount: Int
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = self.points(in: size)
            let played = min(max(playedCount, 1), points.count)

            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        Color.primary.opacity(0.13),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }

                if played > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.prefix(played).dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                if points.indices.contains(played - 1) {
                    BevelGlowDot(tint: tint, size: 8)
                        .position(points[played - 1])
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else {
            return [CGPoint(x: 6, y: y(for: values.first ?? 0, in: size))]
        }
        let step = (size.width - 16) / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: 6 + CGFloat(index) * step, y: y(for: value, in: size))
        }
    }

    private func y(for value: Double, in size: CGSize) -> CGFloat {
        let axisMax = max(values.max() ?? 1, 1)
        let ratio = value / axisMax
        return size.height - 10 - CGFloat(ratio) * (size.height - 20)
    }
}

// MARK: - Quick stats

/// The screen-wide stat strip: quiet labels over big values, split by
/// hairlines — Bevel's activity-detail grid.
private struct BevelQuickStats: View {
    var analytics: BingoPredictionAnalytics

    var body: some View {
        HStack(spacing: 0) {
            stat(label: "Current round", value: analytics.currentRoundLabel)
            divider
            stat(label: "Called through", value: analytics.calledThroughLabel)
            divider
            stat(label: "Remaining", value: "\(analytics.remainingRounds)")
            divider
            stat(label: "First bingo", value: analytics.firstBingoETA)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .bevelCard()
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1, height: 44)
    }
}

// MARK: - Forecast chart

private enum BevelForecastSeries: String, CaseIterable, Identifiable {
    case cards = "Cards on bingo"
    case lines = "Total lines"

    var id: String { rawValue }
}

/// The big detail chart, Bevel-style: heat-tinted line for called rounds, a
/// dashed gray continuation for the projection, faint gridlines with right-
/// side labels, a dotted "final" rule with a pill, and a coverage strip under
/// the axis.
private struct BevelForecastChartCard: View {
    var analytics: BingoPredictionAnalytics
    @Binding var series: BevelForecastSeries

    private var values: [Double] {
        switch series {
        case .cards: analytics.snapshots.map { Double($0.cardsOnBingo) }
        case .lines: analytics.snapshots.map { Double($0.bingoLines) }
        }
    }

    private var axisMax: Double {
        switch series {
        case .cards: Double(max(analytics.cardCount, analytics.snapshots.map(\.cardsOnBingo).max() ?? 1, 1))
        case .lines: Double(max(analytics.snapshots.map(\.bingoLines).max() ?? 1, 1))
        }
    }

    private var currentValue: Int {
        switch series {
        case .cards: analytics.currentCardsOnBingo
        case .lines: analytics.currentBingoLines
        }
    }

    private var finalValue: Int {
        switch series {
        case .cards: analytics.finalCardsOnBingo
        case .lines: analytics.finalBingoLines
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    BevelCardHeader(symbol: "chart.xyaxis.line", title: "Bingo Forecast by Round")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(currentValue)")
                            .font(.system(size: 36, weight: .semibold))
                            .monospacedDigit()
                        Text(series == .cards ? "cards now" : "lines now")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(analytics.calledThroughRound == 0
                         ? "Ready to start · \(analytics.totalRounds) rounds"
                         : "Round \(analytics.calledThroughRound) of \(analytics.totalRounds)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Projected finish")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    BevelStatusLine(
                        symbol: "arrow.up.circle.fill",
                        text: series == .cards
                            ? "\(finalValue) of \(analytics.cardCount) cards"
                            : "\(finalValue) lines",
                        tint: BevelTheme.green
                    )
                }
            }

            HStack(spacing: 10) {
                ForEach(BevelForecastSeries.allCases) { option in
                    BevelChip(title: option.rawValue, isSelected: option == series) {
                        series = option
                    }
                }
                Spacer()
            }

            BevelForecastPlot(
                values: values,
                axisMax: axisMax,
                currentIndex: min(analytics.calledThroughRound, max(values.count - 1, 0)),
                finalValue: Double(finalValue),
                firstBingoIndex: analytics.firstBingoRound
            )
            .frame(height: 250)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard()
    }
}

private struct BevelChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(BevelTheme.card) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? Color.primary : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct BevelForecastPlot: View {
    var values: [Double]
    var axisMax: Double
    var currentIndex: Int
    var finalValue: Double
    var firstBingoIndex: Int?

    private let rightGutter: CGFloat = 36
    private let bottomGutter: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let plot = CGSize(width: geo.size.width - rightGutter, height: geo.size.height - bottomGutter)
            let points = self.points(in: plot)
            let current = min(max(currentIndex, 0), max(points.count - 1, 0))
            let gridValues = self.gridValues

            ZStack(alignment: .topLeading) {
                // Gridlines and right-side labels.
                ForEach(gridValues, id: \.self) { value in
                    let lineY = y(for: Double(value), in: plot)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: lineY))
                        path.addLine(to: CGPoint(x: plot.width, y: lineY))
                    }
                    .stroke(.primary.opacity(0.07), lineWidth: 1)

                    Text("\(value)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .position(x: plot.width + rightGutter / 2, y: lineY)
                }

                // Pale fill under the called portion.
                if points.count > 1, current > 0 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: plot.height))
                        for point in points.prefix(current + 1) {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: points[current].x, y: plot.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [BevelTheme.orange.opacity(0.16), BevelTheme.orange.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Dotted rule at the projected final value, with its pill.
                // Skipped when the projection tops out at the axis line it
                // would sit on.
                if finalValue > 0, finalValue < axisMax * 0.96 {
                    let finalY = y(for: finalValue, in: plot)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: finalY))
                        path.addLine(to: CGPoint(x: plot.width, y: finalY))
                    }
                    .stroke(BevelTheme.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

                    Text("Final \(Int(finalValue))")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BevelTheme.orange))
                        .position(x: plot.width * 0.28, y: finalY)
                }

                // The first-bingo annotation: a dotted drop line with an
                // orange pill, Bevel's average-line idiom turned vertical.
                if let firstBingoIndex, points.indices.contains(firstBingoIndex) {
                    let mark = points[firstBingoIndex]
                    let pillX = min(max(mark.x, 34), plot.width - 34)

                    Path { path in
                        path.move(to: CGPoint(x: mark.x, y: 26))
                        path.addLine(to: CGPoint(x: mark.x, y: mark.y - 7))
                    }
                    .stroke(BevelTheme.orange.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

                    Text("1st bingo")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BevelTheme.orange))
                        .position(x: pillX, y: 14)
                }

                // The projection: a dashed quiet line to the end of the game.
                if points.count > current + 1 {
                    Path { path in
                        path.move(to: points[current])
                        for point in points.suffix(from: current + 1) {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        Color.primary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [1.5, 5])
                    )
                }

                // The called portion: heat-tinted by height, like Bevel's
                // strain chart.
                if current > 0 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.prefix(current + 1).dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [BevelTheme.yellow, BevelTheme.orange, BevelTheme.red],
                            startPoint: UnitPoint(x: 0, y: 1),
                            endPoint: UnitPoint(x: 0, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                }

                // Markers on future wave rounds (open, quiet)…
                ForEach(waveIndices.filter { $0 > current }, id: \.self) { index in
                    Circle()
                        .fill(BevelTheme.card)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .position(points[index])
                }

                // …and on called wave rounds (white-filled, heat-ringed).
                ForEach(waveIndices.filter { $0 <= current }, id: \.self) { index in
                    let tint = BevelTheme.heat(values[index] / max(axisMax, 1))
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(points[index])
                }

                // The "now" dot.
                if points.indices.contains(current), current > 0 || values[0] > 0 {
                    BevelGlowDot(
                        tint: BevelTheme.heat(values[current] / max(axisMax, 1)),
                        size: 9
                    )
                    .position(points[current])
                }

                // Axis ticks, coverage strip, and round labels.
                BevelAxisStrip(
                    count: values.count,
                    currentIndex: current,
                    plotWidth: plot.width
                )
                .frame(width: plot.width)
                .offset(y: plot.height + 8)
            }
        }
    }

    private var waveIndices: [Int] {
        guard values.count > 1 else { return [] }
        return (1..<values.count).filter { values[$0] > values[$0 - 1] }
    }

    private var gridValues: [Int] {
        let top = Int(axisMax.rounded())
        let steps = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        var seen = Set<Int>()
        return steps.compactMap { step in
            let value = Int((Double(top) * step).rounded())
            return seen.insert(value).inserted ? value : nil
        }
    }

    private func points(in plot: CGSize) -> [CGPoint] {
        guard values.count > 1 else {
            return [CGPoint(x: 0, y: y(for: values.first ?? 0, in: plot))]
        }
        let step = plot.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: y(for: value, in: plot))
        }
    }

    private func y(for value: Double, in plot: CGSize) -> CGFloat {
        let ratio = axisMax > 0 ? value / axisMax : 0
        return plot.height - 6 - CGFloat(ratio) * (plot.height - 18)
    }
}

/// The strip under the plot: one hairline tick per round, a mint coverage bar
/// over the called portion, and a handful of round labels.
private struct BevelAxisStrip: View {
    var count: Int
    var currentIndex: Int
    var plotWidth: CGFloat

    var body: some View {
        let step = count > 1 ? plotWidth / CGFloat(count - 1) : plotWidth

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for index in 0..<max(count, 1) {
                    let x = CGFloat(index) * step
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 0))
                    tick.addLine(to: CGPoint(x: x, y: 4))
                    context.stroke(tick, with: .color(.primary.opacity(0.14)), lineWidth: 1)
                }
            }
            .frame(height: 4)

            Capsule()
                .fill(.primary.opacity(0.06))
                .frame(width: plotWidth, height: 3)
                .offset(y: 7)

            if currentIndex > 0 {
                Capsule()
                    .fill(BevelTheme.mint)
                    .frame(width: max(6, CGFloat(currentIndex) * step), height: 3)
                    .offset(y: 7)
            }

            ForEach(labelIndices, id: \.self) { index in
                Text("R\(index == 0 ? 1 : index)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                    .position(x: CGFloat(index) * step, y: 20)
            }
        }
    }

    private var labelIndices: [Int] {
        let last = count - 1
        guard last > 0 else { return [] }
        let steps = [0.0, 0.25, 0.5, 0.75, 1.0]
        var seen = Set<Int>()
        return steps.compactMap { step in
            var index = Int((Double(last) * step).rounded())
            // Interior labels snap to round-number rounds (R10, R20, …).
            if step > 0, step < 1, last >= 12 {
                index = min(max(5, Int((Double(index) / 5).rounded()) * 5), last - 3)
            }
            return seen.insert(index).inserted ? index : nil
        }
    }
}

// MARK: - Wave distribution

/// Bevel's waffle: each wave is a little column of dots, one per card, with
/// faint placeholders up to the biggest wave. Green dots have hit; orange
/// dots are still projected.
private struct BevelWaveWaffle: View {
    var analytics: BingoPredictionAnalytics

    private struct Wave: Identifiable {
        var id: Int { round }
        let round: Int
        let gained: Int
        let hasHit: Bool
    }

    private var waves: [Wave] {
        zip(analytics.snapshots, analytics.snapshots.dropFirst()).compactMap { previous, current in
            let gained = current.cardsOnBingo - previous.cardsOnBingo
            guard gained > 0 else { return nil }
            return Wave(
                round: current.round,
                gained: gained,
                hasHit: current.round <= analytics.calledThroughRound
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BevelCardHeader(symbol: "circle.grid.3x3", title: "Wave Distribution")

            if waves.isEmpty {
                Text("No projected bingo waves.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                // A fixed dot grid, Bevel-macro style: faint placeholder dots
                // give every column the same height, filled dots count cards.
                let shown = Array(waves.prefix(8))
                let rows = max(shown.map(\.gained).max() ?? 1, 4)

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(shown) { wave in
                        VStack(spacing: 7) {
                            VStack(spacing: 5) {
                                ForEach(0..<rows, id: \.self) { slot in
                                    let filled = slot >= rows - wave.gained
                                    Circle()
                                        .fill(
                                            filled
                                                ? (wave.hasHit ? BevelTheme.green : BevelTheme.orange)
                                                : Color.primary.opacity(0.07)
                                        )
                                        .frame(width: 11, height: 11)
                                }
                            }
                            Text("R\(wave.round)")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .bottom)

                HStack(spacing: 14) {
                    legend(tint: BevelTheme.green, label: "Hit")
                    legend(tint: BevelTheme.orange, label: "Projected")
                    Spacer()
                    if waves.count > shown.count {
                        Text("+\(waves.count - shown.count) more")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Each dot is one card reaching bingo.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard()
    }

    private func legend(tint: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Upcoming waves

/// Bevel's trends table: Period | Change | Trend, with a colored circle-arrow
/// on the change and a tiny gradient-filled sparkline per row.
private struct BevelUpcomingWavesTable: View {
    var analytics: BingoPredictionAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BevelCardHeader(symbol: "list.bullet", title: "Upcoming Waves")

            if analytics.upcomingWaves.isEmpty {
                Text("No new bingo waves ahead.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Round").frame(width: 64, alignment: .leading)
                        Text("Change").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Trend").frame(width: 72, alignment: .trailing)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                    ForEach(Array(analytics.upcomingWaves.enumerated()), id: \.element.id) { index, wave in
                        if index > 0 {
                            Rectangle()
                                .fill(.primary.opacity(0.07))
                                .frame(height: 0.5)
                        }

                        HStack {
                            Text("R\(wave.round)")
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .leading)

                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(wave.cardsOnBingo > 0 ? BevelTheme.green : BevelTheme.orange)
                                Text(changeText(for: wave))
                                    .font(.system(size: 15, weight: .medium))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            BevelMiniTrend(
                                values: analytics.snapshots.prefix(wave.round + 1).map { Double($0.cardsOnBingo) },
                                tint: BevelTheme.orange
                            )
                            .frame(width: 72, height: 26)
                        }
                        .padding(.vertical, 9)
                    }
                }

                Text("Projected from the locked song order.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard()
    }

    private func changeText(for wave: BingoPredictionAnalytics.RoundSnapshot) -> String {
        if wave.cardsOnBingo > 0 {
            return wave.cardsOnBingo == 1 ? "+1 card" : "+\(wave.cardsOnBingo) cards"
        }
        return wave.bingoLines == 1 ? "+1 line" : "+\(wave.bingoLines) lines"
    }
}

/// The tiny table-cell sparkline: a thin line with a soft gradient pooled
/// underneath, exactly like Bevel's trends column.
private struct BevelMiniTrend: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let maxValue = max(values.max() ?? 1, 1)
            let points: [CGPoint] = values.count > 1
                ? values.enumerated().map { index, value in
                    CGPoint(
                        x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                        y: size.height - 3 - CGFloat(value / maxValue) * (size.height - 6)
                    )
                }
                : []

            if points.count > 1 {
                Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.25), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
