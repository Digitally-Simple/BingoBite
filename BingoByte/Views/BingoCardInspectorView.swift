import SwiftUI

struct BingoCardInspectorView: View {
    var card: BingoCard
    var bingoSet: BingoSet
    var songs: [Song]

    private let bingoColumns = ["B", "I", "N", "G", "O"]

    private var songLookup: [String: Song] {
        var lookup: [String: Song] = [:]
        for song in songs {
            lookup[song.id.absoluteString] = song
        }
        return lookup
    }

    private func song(forIndex index: Int) -> Song? {
        guard index > 0, index <= bingoSet.songURLStrings.count else { return nil }
        let urlString = bingoSet.songURLStrings[index - 1]
        return songLookup[urlString]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Card #\(card.id)")
                    .font(.headline)
                    .padding(.top)

                // Column headers
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        ForEach(bingoColumns, id: \.self) { col in
                            Text(col)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // 5x5 grid
                    ForEach(0..<5, id: \.self) { row in
                        GridRow {
                            ForEach(0..<5, id: \.self) { col in
                                let value = card.grid[row][col]
                                cellView(value: value)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)

                Divider()
                    .padding(.horizontal)

                // Song legend
                VStack(alignment: .leading, spacing: 6) {
                    Text("Song Legend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    let uniqueIndices = Set(card.grid.flatMap { $0 }).filter { $0 != 0 }.sorted()
                    ForEach(uniqueIndices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text("\(index)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                            Text(song(forIndex: index)?.displayTitle ?? "Unknown Song")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    // MARK: - Cell View

    @ViewBuilder
    private func cellView(value: Int) -> some View {
        if value == 0 {
            // Free space
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow.opacity(0.3))
                VStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    Text("FREE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        } else if let song = song(forIndex: value) {
            ZStack {
                if let image = song.artworkImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack {
                    Spacer()
                    Text("\(value)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.black.opacity(0.6))
                        .cornerRadius(3)
                }
                .padding(2)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                VStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(value)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}
