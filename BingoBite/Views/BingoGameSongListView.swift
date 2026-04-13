import SwiftUI

struct BingoGameSongListView: View {
    @Binding var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: [String: Song]

    var body: some View {
        List {
            ForEach(Array(shuffledSongs.enumerated()), id: \.element) { index, urlString in
                let song = songLookup[urlString]
                songRow(index: index, song: song, urlString: urlString)
                    .moveDisabled(index <= currentIndex)
            }
            .onMove { source, destination in
                let lockedBoundary = currentIndex + 1
                // Prevent moving into the played/current zone
                let clampedDestination = max(destination, lockedBoundary)
                shuffledSongs.move(fromOffsets: source, toOffset: clampedDestination)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func songRow(index: Int, song: Song?, urlString: String) -> some View {
        HStack(spacing: 12) {
            // Song number
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(rowForegroundStyle(for: index))
                .frame(width: 28, alignment: .trailing)

            // Artwork
            if let song, let image = song.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
            }

            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(song?.displayTitle ?? "Unknown Song")
                    .font(.body)
                    .lineLimit(1)
                Text(song?.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status icon
            statusIcon(for: index)
        }
        .opacity(rowOpacity(for: index))
        .listRowBackground(index == currentIndex ? Color.accentColor.opacity(0.1) : nil)
    }

    @ViewBuilder
    private func statusIcon(for index: Int) -> some View {
        if index < currentIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        } else if index == currentIndex {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Color.accentColor)
                .font(.body)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.body)
        }
    }

    private func rowOpacity(for index: Int) -> Double {
        if index < currentIndex { return 0.5 }
        if index == currentIndex { return 1.0 }
        return 0.7
    }

    private func rowForegroundStyle(for index: Int) -> Color {
        if index == currentIndex { return .primary }
        return .secondary
    }
}
