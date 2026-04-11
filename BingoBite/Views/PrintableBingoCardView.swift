import SwiftUI

struct PrintableBingoCardView: View {
    var card: BingoCard
    var songs: [Song]
    var songURLStrings: [String]
    var settings: CardDesignSettings

    private let bingoColumns = ["B", "I", "N", "G", "O"]
    private let cardAspectRatio: CGFloat = 8.5 / 11.0

    private func song(for gridValue: Int) -> Song? {
        guard gridValue > 0, gridValue <= songURLStrings.count else { return nil }
        let urlString = songURLStrings[gridValue - 1]
        return songs.first { $0.id.absoluteString == urlString }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Card title
            HStack(spacing: 4) {
                Text(settings.cardTitle)
                    .font(settings.font(size: settings.cardTitleFontSize))
                    .fontWeight(settings.resolvedFontWeight)
                    .foregroundStyle(Color(hex: settings.cardTitleColorHex))

                if settings.showCardNumbers {
                    Text("#\(card.id)")
                        .font(settings.font(size: settings.cardTitleFontSize * 0.5))
                        .foregroundStyle(Color(hex: settings.cardTitleColorHex).opacity(0.6))
                }
            }
            .padding(.bottom, 8)

            // Grid with headers and cells
            VStack(spacing: 0) {
                // BINGO column headers
                HStack(spacing: 0) {
                    ForEach(bingoColumns, id: \.self) { col in
                        Text(col)
                            .font(settings.font(size: settings.cardTitleFontSize * 0.6))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(hex: settings.headerTextColorHex))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color(hex: settings.headerBackgroundHex))

                // 5x5 grid
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { col in
                                let value = card.grid[row][col]
                                cellView(value: value)
                                    .border(Color(hex: settings.borderColorHex), width: settings.borderWidth * 0.5)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: settings.borderColorHex), lineWidth: settings.borderWidth)
            )

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(hex: settings.cardBackgroundHex))
        .aspectRatio(cardAspectRatio, contentMode: .fit)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(value: Int) -> some View {
        if value == 0 {
            freeSpaceCell
        } else {
            songCell(value: value)
        }
    }

    private var freeSpaceCell: some View {
        VStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
            Text(settings.freeSpaceText)
                .font(settings.font(size: settings.trackNameFontSize))
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(hex: settings.freeSpaceColorHex))
    }

    private func songCell(value: Int) -> some View {
        let matchedSong = song(for: value)

        return VStack(spacing: 1) {
            if settings.showArtwork && !settings.useArtworkAsBackground, let image = matchedSong?.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            if settings.showTrackName {
                cellText(
                    matchedSong?.displayTitle ?? "Track \(value)",
                    fontSize: settings.trackNameFontSize,
                    weight: settings.resolvedFontWeight,
                    opacity: 1.0
                )
            }

            if settings.showArtistName {
                cellText(
                    matchedSong?.artist ?? "Unknown Artist",
                    fontSize: settings.artistNameFontSize,
                    opacity: 0.7
                )
            }

            if settings.showAlbumName {
                cellText(
                    matchedSong?.album ?? "Unknown Album",
                    fontSize: settings.albumNameFontSize,
                    opacity: 0.5
                )
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background {
            if settings.useArtworkAsBackground, let image = matchedSong?.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(settings.artworkBackgroundOpacity)
            } else {
                Color(hex: settings.cellBackgroundHex)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func cellText(
        _ text: String,
        fontSize: CGFloat,
        weight: Font.Weight = .regular,
        opacity: Double
    ) -> some View {
        if settings.shrinkTextToFit {
            Text(text)
                .font(settings.font(size: fontSize))
                .fontWeight(weight)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(3)
                .foregroundStyle(Color(hex: settings.cellTextColorHex).opacity(opacity))
        } else {
            Text(text)
                .font(settings.font(size: fontSize))
                .fontWeight(weight)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(Color(hex: settings.cellTextColorHex).opacity(opacity))
        }
    }
}
