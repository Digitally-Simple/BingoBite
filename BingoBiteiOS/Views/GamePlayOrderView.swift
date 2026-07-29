import SwiftUI

/// The shuffled play order. Upcoming songs can be dragged to reorder; anything
/// already played is locked so the boards stay accurate.
struct GamePlayOrderView: View {
    @Binding var shuffledSongs: [String]
    var currentIndex: Int
    var songLookup: SongIndex
    var isCompleted: Bool

    var body: some View {
        List {
            ForEach(Array(shuffledSongs.enumerated()), id: \.element) { index, urlString in
                row(index: index, song: songLookup.song(for: urlString))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(
                        index == currentIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                    .moveDisabled(index <= currentIndex || isCompleted)
            }
            .onMove { source, destination in
                // Never let a drag land inside the already-played region.
                let boundary = currentIndex + 1
                shuffledSongs.move(fromOffsets: source, toOffset: max(destination, boundary))
            }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaPadding(.bottom, 96)
    }

    private func row(index: Int, song: Song?) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(index == currentIndex ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 34, alignment: .trailing)

            ArtworkView(data: song?.artworkData, corner: 8)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song?.displayTitle ?? "Unknown Song")
                    .font(.body.weight(index == currentIndex ? .semibold : .regular))
                    .lineLimit(1)
                Text(song?.displayArtist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            status(for: index)
        }
        .padding(.vertical, 4)
        .opacity(index < currentIndex ? 0.5 : 1)
    }

    @ViewBuilder
    private func status(for index: Int) -> some View {
        if index < currentIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if index == currentIndex {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative)
        } else {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.quaternary)
        }
    }
}
