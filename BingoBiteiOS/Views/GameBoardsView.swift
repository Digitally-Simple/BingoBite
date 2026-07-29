import SwiftUI

/// Live scoring for every generated card, as a grid of boards or a sortable
/// leaderboard.
struct GameBoardsView: View {
    var game: BingoGame
    var songLookup: SongIndex

    private enum Mode: String, CaseIterable, Identifiable {
        case boards = "Boards"
        case leaderboard = "Leaderboard"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .boards

    private var cards: [BingoCard] {
        CardGenerator.decode(from: game.cardsData).enumerated().map { BingoCard(id: $0.offset + 1, grid: $0.element) }
    }

    private var playedURLs: Set<String> {
        BingoGameService.playedSongURLs(
            shuffledSongs: game.shuffledSongURLStrings,
            currentIndex: game.currentIndex
        )
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 18)]

    var body: some View {
        Group {
            if game.currentIndex < 0 {
                ContentUnavailableView {
                    Label("No Songs Played", systemImage: "square.grid.3x3")
                } description: {
                    Text("Boards light up as each song is revealed.")
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 10)

                    switch mode {
                    case .boards: boardGrid
                    case .leaderboard: GameLeaderboardView(game: game)
                    }
                }
            }
        }
    }

    private var boardGrid: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(cards) { card in
                        GameCardView(
                            card: card,
                            scoredMatrix: BingoGameService.scoreCard(
                                card: card,
                                songURLStrings: game.songURLStrings,
                                playedSongURLs: playedURLs,
                                hasFreeSpace: game.hasFreeSpace
                            ),
                            songURLStrings: game.songURLStrings,
                            shuffledSongs: game.shuffledSongURLStrings,
                            currentIndex: game.currentIndex,
                            songLookup: songLookup
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - Single card

struct GameCardView: View {
    var card: BingoCard
    var scoredMatrix: [[BingoGameService.CellState]]
    var songURLStrings: [String]
    var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: SongIndex

    @State private var inspectedCell: Int?

    private let headers = ["B", "I", "N", "G", "O"]

    private var hasBingo: Bool {
        scoredMatrix.contains { $0.contains(.bingo) }
    }

    /// Maps a card's 1-based song index to its position in the play order.
    private func callNumber(for songIndex: Int) -> Int? {
        guard songIndex > 0, songIndex <= songURLStrings.count else { return nil }
        guard let position = shuffledSongs.firstIndex(of: songURLStrings[songIndex - 1]) else { return nil }
        return position + 1
    }

    /// Squares marked, free space excluded — the same count the leaderboard
    /// meters, shown here so a board reads at a glance in the grid.
    private var hits: Int {
        var count = 0
        for row in 0..<5 {
            for column in 0..<5 where card.grid[row][column] != 0 {
                if scoredMatrix[row][column] != .unplayed { count += 1 }
            }
        }
        return count
    }

    private var tint: Color {
        hasBingo ? BingoActivityTheme.gold : .accentColor
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Text("Card #\(card.id)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if hasBingo {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(BingoActivityTheme.gold)
                }
            }

            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<5, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { column in
                            cell(row: row, column: column)
                        }
                    }
                }
            }

            SegmentedMeter(
                filled: hits,
                total: 24,
                tint: tint,
                height: 5,
                trackColor: .primary.opacity(0.12)
            )
            .padding(.top, 1)
        }
        .padding(12)
        .glassCard(corner: Glassware.tileCorner, tint: hasBingo ? BingoActivityTheme.gold : nil)
    }

    private func cell(row: Int, column: Int) -> some View {
        let value = card.grid[row][column]
        let state = scoredMatrix[row][column]
        let cellID = row * 5 + column

        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color(for: state))

            // A bingo cell is a marked cell wearing a ring. Distinguishing the
            // two by outline rather than by a second hue keeps the board to one
            // accent while still making a win unmistakable at a glance.
            if state == .bingo {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary, lineWidth: 1.5)
            }

            if value == 0 {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(ink(for: state))
            } else {
                Text("\(callNumber(for: value) ?? value)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink(for: state))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            guard value != 0 else { return }
            inspectedCell = (inspectedCell == cellID) ? nil : cellID
        }
        .popover(isPresented: Binding(
            get: { inspectedCell == cellID },
            set: { if !$0 { inspectedCell = nil } }
        )) {
            CellDetailPopover(
                songIndex: value,
                songURLStrings: songURLStrings,
                shuffledSongs: shuffledSongs,
                currentIndex: currentIndex,
                songLookup: songLookup
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Gold is bright enough that white numerals disappear on it, so a bingo
    /// square inverts to dark ink.
    private func ink(for state: BingoGameService.CellState) -> AnyShapeStyle {
        switch state {
        case .unplayed: AnyShapeStyle(.secondary)
        case .played:   AnyShapeStyle(.white)
        case .bingo:    AnyShapeStyle(BingoActivityTheme.card)
        }
    }

    private func color(for state: BingoGameService.CellState) -> Color {
        switch state {
        case .unplayed: Color.primary.opacity(0.08)
        case .played: Color.accentColor.opacity(0.80)
        // A completed line is the one thing worth gold on the board, matching
        // the badge in the header and the meter on the Lock Screen.
        case .bingo: BingoActivityTheme.gold
        }
    }
}

// MARK: - Cell popover

struct CellDetailPopover: View {
    var songIndex: Int
    var songURLStrings: [String]
    var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: SongIndex

    private var songURL: String? {
        guard songIndex > 0, songIndex <= songURLStrings.count else { return nil }
        return songURLStrings[songIndex - 1]
    }

    private var song: Song? {
        songURL.flatMap { songLookup.song(for: $0) }
    }

    /// 0-based position of this song in the play order.
    private var roundIndex: Int? {
        songURL.flatMap { shuffledSongs.firstIndex(of: $0) }
    }

    private var timing: (text: String, icon: String, color: Color) {
        guard let roundIndex else { return ("Not in the play order", "questionmark.circle.fill", .secondary) }
        guard currentIndex >= 0 else { return ("Plays in round \(roundIndex + 1)", "clock.fill", .secondary) }

        let delta = roundIndex - currentIndex
        if delta == 0 { return ("Playing now", "speaker.wave.2.fill", .accentColor) }
        if delta < 0 {
            let ago = abs(delta)
            return (ago == 1 ? "Played last round" : "Played \(ago) rounds ago", "checkmark.circle.fill", .secondary)
        }
        return (delta == 1 ? "Plays next round" : "Plays in \(delta) rounds", "clock.fill", .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ArtworkView(data: song?.artworkData, corner: 10)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 3) {
                    Text(song?.displayTitle ?? "Unknown Song")
                        .font(.headline)
                        .lineLimit(2)
                    if let artist = song?.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let album = song?.album, !album.isEmpty {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let roundIndex {
                    Label("Round \(roundIndex + 1) of \(shuffledSongs.count)", systemImage: "number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label(timing.text, systemImage: timing.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timing.color)
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}
