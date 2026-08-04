import SwiftUI

/// One song in the library list.
///
/// Laid out as a table row rather than a phone-style list row: at iPad width a
/// two-element HStack leaves ~1000pt of dead space in the middle, so the album
/// takes its own column and the duration is pinned to a fixed trailing gutter.
/// The album column drops away in compact width, where there's no room for it.
///
/// Renders entirely from the cached index row — no disk access — so scrolling a
/// large library never touches the filesystem.
struct SongsLibraryRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Whether the list is in multi-select mode, and if so whether this row is
    /// picked. Kept as one value so the row never renders a checkbox outside
    /// select mode.
    enum SelectionState {
        case notSelecting
        case unselected
        case selected
    }

    let entry: LibraryIndexEntry
    let libraryURL: URL
    var selectionState: SelectionState = .notSelecting
    let onPlay: () -> Void

    /// `CardSurface` is only a fill and a stroke, so the row owns its own
    /// insets. Without these the artwork sits flush against the card edge.
    private static let horizontalInset: CGFloat = 14
    private static let albumColumnWidth: CGFloat = 260
    private static let durationColumnWidth: CGFloat = 56

    private var showsAlbumColumn: Bool { sizeClass == .regular }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                if selectionState != .notSelecting {
                    Image(systemName: selectionState == .selected
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.title3)
                        .foregroundStyle(selectionState == .selected
                                         ? AnyShapeStyle(.tint)
                                         : AnyShapeStyle(.tertiary))
                }

                artwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .lineLimit(1)
                        .foregroundStyle(entry.isMissing ? .secondary : .primary)
                    Text(entry.isMissing ? "Missing from the Library folder" : entry.displayArtist)
                        .font(.caption)
                        .foregroundStyle(entry.isMissing ? .orange : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsAlbumColumn {
                    Text(entry.album.isEmpty ? "—" : entry.album)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(width: Self.albumColumnWidth, alignment: .leading)
                }

                Text(entry.duration > 0 ? Format.time(entry.duration) : "—")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.durationColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .interactiveGlassCard(tint: selectionState == .selected ? .accentColor : nil)
    }

    private var artwork: some View {
        ZStack {
            ArtworkView(data: entry.thumbnailData, corner: 6)
                .frame(width: 40, height: 40)
                .opacity(entry.isMissing ? 0.35 : 1)
            if entry.isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Column headings above the song list, so the columns read as a table rather
/// than as rows that happen to have gaps in them.
struct SongsLibraryHeader: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 14) {
            // Matches the artwork column so the headings line up with content.
            Color.clear.frame(width: 40, height: 1)

            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)

            if sizeClass == .regular {
                Text("Album")
                    .frame(width: 260, alignment: .leading)
            }

            Text("Time")
                .frame(width: 56, alignment: .trailing)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
