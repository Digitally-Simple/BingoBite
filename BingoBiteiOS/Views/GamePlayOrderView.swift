import SwiftUI

/// The shuffled play order. Upcoming songs can be dragged to reorder; anything
/// already played is locked so the boards stay accurate.
struct GamePlayOrderView: View {
    @Binding var shuffledSongs: [String]
    var currentIndex: Int
    var protectedThroughIndex: Int
    var songLookup: SongIndex
    var isCompleted: Bool

    private var reorderBoundary: Int {
        min(max(protectedThroughIndex + 1, 0), shuffledSongs.count)
    }

    var body: some View {
        List {
            ForEach(Array(shuffledSongs.enumerated()), id: \.element) { index, urlString in
                row(index: index, song: songLookup.song(for: urlString))
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(index < reorderBoundary || isCompleted)
            }
            .onMove { source, destination in
                // Never let a drag land inside the already-played region.
                shuffledSongs.move(fromOffsets: source, toOffset: max(destination, reorderBoundary))
            }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func row(index: Int, song: Song?) -> some View {
        HStack(spacing: 14) {
            RoundChip(
                round: index + 1,
                size: index == currentIndex ? 17 : 15,
                tint: index == currentIndex ? BingoActivityTheme.live : .secondary
            )
            .frame(width: 44, alignment: .trailing)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // The live round gets an inset tinted plate rather than a full-bleed
        // row fill, so it sits on the backdrop like the rest of the surfaces.
        .background {
            if index == currentIndex {
                RoundedRectangle(cornerRadius: Glassware.tileCorner, style: .continuous)
                    .fill(.tint.opacity(0.16))
            }
        }
        .opacity(index < currentIndex ? 0.5 : 1)
    }

    @ViewBuilder
    private func status(for index: Int) -> some View {
        if index < currentIndex {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
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
