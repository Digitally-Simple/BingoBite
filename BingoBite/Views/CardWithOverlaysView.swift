import SwiftUI

struct CardWithOverlaysView: View {
    var card: BingoCard
    var songs: [Song]
    var songURLStrings: [String]
    var settings: CardDesignSettings

    var body: some View {
        PrintableBingoCardView(
            card: card,
            songs: songs,
            songURLStrings: songURLStrings,
            settings: settings
        )
        .overlay {
            GeometryReader { geo in
                ForEach(settings.imageOverlays) { overlay in
                    if let nsImage = overlay.cachedImage {
                        let imageAspect = nsImage.size.width / max(nsImage.size.height, 1)
                        let imageWidth = geo.size.width * overlay.normalizedScale
                        let imageHeight = imageWidth / max(imageAspect, 0.01)

                        Image(nsImage: nsImage)
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
