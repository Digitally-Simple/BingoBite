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
                .padding(.bottom, 110)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Text("Card #\(card.id)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if hasBingo {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
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
        }
        .padding(12)
        .glassCard(corner: Glassware.tileCorner, tint: hasBingo ? .green : nil)
    }

    private func cell(row: Int, column: Int) -> some View {
        let value = card.grid[row][column]
        let state = scoredMatrix[row][column]
        let cellID = row * 5 + column

        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color(for: state))

            if value == 0 {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(state == .bingo ? .white : .yellow)
            } else {
                Text("\(callNumber(for: value) ?? value)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(state == .unplayed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
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

    private func color(for state: BingoGameService.CellState) -> Color {
        switch state {
        case .unplayed: Color.gray.opacity(0.18)
        case .played: Color.orange.opacity(0.85)
        case .bingo: Color.green.opacity(0.9)
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
        guard currentIndex >= 0 else { return ("Plays in round \(roundIndex + 1)", "clock.fill", .blue) }

        let delta = roundIndex - currentIndex
        if delta == 0 { return ("Playing now", "speaker.wave.2.fill", .green) }
        if delta < 0 {
            let ago = abs(delta)
            return (ago == 1 ? "Played last round" : "Played \(ago) rounds ago", "checkmark.circle.fill", .secondary)
        }
        return (delta == 1 ? "Plays next round" : "Plays in \(delta) rounds", "clock.fill", .blue)
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
