import SwiftUI

struct BingoGameCardView: View {
    var card: BingoCard
    var scoredMatrix: [[BingoGameService.CellState]]
    var songURLStrings: [String]
    var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: [String: Song]

    @State private var popoverCellID: Int?

    private let bingoColumns = ["B", "I", "N", "G", "O"]

    private var hasBingo: Bool {
        scoredMatrix.contains { row in row.contains(.bingo) }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Card header
            HStack {
                Text("Card #\(card.id)")
                    .font(.caption)
                    .fontWeight(.semibold)
                if hasBingo {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            // BINGO column headers
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(bingoColumns, id: \.self) { col in
                        Text(col)
                            .font(.system(size: 9, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                }

                // 5x5 grid
                ForEach(0..<5, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { col in
                            let value = card.grid[row][col]
                            let state = scoredMatrix[row][col]
                            let cellID = row * 5 + col
                            cellView(value: value, state: state, cellID: cellID)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasBingo ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(value: Int, state: BingoGameService.CellState, cellID: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor(for: state))

            if value == 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(state == .bingo ? Color.white : Color.yellow)
            } else {
                Text("\(value)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(state == .unplayed ? Color.secondary : Color.white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            if value != 0 {
                popoverCellID = (popoverCellID == cellID) ? nil : cellID
            }
        }
        .popover(isPresented: Binding(
            get: { popoverCellID == cellID },
            set: { if !$0 { popoverCellID = nil } }
        ), arrowEdge: .bottom) {
            if value != 0 {
                BingoCellPopoverView(
                    songIndex: value,
                    songURLStrings: songURLStrings,
                    shuffledSongs: shuffledSongs,
                    currentIndex: currentIndex,
                    songLookup: songLookup
                )
            }
        }
    }

    private func cellColor(for state: BingoGameService.CellState) -> Color {
        switch state {
        case .unplayed: return Color.gray.opacity(0.2)
        case .played: return Color.yellow.opacity(0.8)
        case .bingo: return Color.green.opacity(0.8)
        }
    }
}

// MARK: - Cell Popover

struct BingoCellPopoverView: View {
    var songIndex: Int
    var songURLStrings: [String]
    var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: [String: Song]

    private var songURL: String? {
        guard songIndex > 0, songIndex <= songURLStrings.count else { return nil }
        return songURLStrings[songIndex - 1]
    }

    private var song: Song? {
        guard let url = songURL else { return nil }
        return songLookup[url]
    }

    /// The 0-based index in the shuffled play order where this song appears.
    private var playRoundIndex: Int? {
        guard let url = songURL else { return nil }
        return shuffledSongs.firstIndex(of: url)
    }

    private var roundLabel: String {
        guard let roundIdx = playRoundIndex else { return "Not in play order" }
        return "Round \(roundIdx + 1) of \(shuffledSongs.count)"
    }

    private var roundDifference: String {
        guard let roundIdx = playRoundIndex else { return "" }
        if currentIndex < 0 {
            return "Will play in round \(roundIdx + 1)"
        }
        let diff = roundIdx - currentIndex
        if diff == 0 {
            return "Playing now"
        } else if diff < 0 {
            let ago = abs(diff)
            return ago == 1 ? "Played last round" : "Played \(ago) rounds ago"
        } else {
            return diff == 1 ? "Plays next round" : "Will play in \(diff) rounds"
        }
    }

    private var roundDifferenceColor: Color {
        guard let roundIdx = playRoundIndex else { return .secondary }
        if currentIndex < 0 { return .blue }
        let diff = roundIdx - currentIndex
        if diff == 0 { return .green }
        if diff < 0 { return .secondary }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Artwork + metadata
            HStack(spacing: 12) {
                // Album art
                Group {
                    if let image = song?.artworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Song info
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

            // Round info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "number.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text("Song #\(songIndex)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "forward.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text(roundLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: roundDifferenceIcon)
                        .foregroundStyle(roundDifferenceColor)
                        .font(.subheadline)
                    Text(roundDifference)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(roundDifferenceColor)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var roundDifferenceIcon: String {
        guard let roundIdx = playRoundIndex else { return "questionmark.circle.fill" }
        if currentIndex < 0 { return "clock.fill" }
        let diff = roundIdx - currentIndex
        if diff == 0 { return "speaker.wave.2.fill" }
        if diff < 0 { return "checkmark.circle.fill" }
        return "clock.fill"
    }
}
