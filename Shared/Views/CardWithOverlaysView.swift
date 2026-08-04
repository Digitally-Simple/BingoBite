import SwiftUI

struct CardWithOverlaysView: View {
    var card: BingoCard
    var songs: [Song]
    var songKeys: [String]
    var settings: CardDesignSettings
    /// The deck's set code, printed with the card number as `AB-1`. Empty
    /// falls back to `Card #1`.
    var setID: String = ""

    var body: some View {
        PrintableBingoCardView(
            card: card,
            songs: songs,
            songKeys: songKeys,
            settings: settings,
            setID: setID
        )
        .overlay {
            GeometryReader { geo in
                ForEach(settings.imageOverlays) { overlay in
                    if let overlayImage = overlay.cachedImage {
                        let imageAspect = overlayImage.size.width / max(overlayImage.size.height, 1)
                        let imageWidth = geo.size.width * overlay.normalizedScale
                        let imageHeight = imageWidth / max(imageAspect, 0.01)

                        Image(platformImage: overlayImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageWidth, height: imageHeight)
                            .opacity(overlay.opacity)
                            .position(
                                x: overlay.normalizedX * geo.size.width,
                                y: overlay.normalizedY * geo.size.height
                            )
                    }
                }
            }
        }
    }
}
