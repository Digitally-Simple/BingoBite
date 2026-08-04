import SwiftUI

struct CardDesignPreviewView: View {
    var cards: [BingoCard]
    var songs: [Song]
    var songKeys: [String]
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?
    /// The deck's set code, printed alongside each card number.
    var setID: String = ""

    @State private var selectedCardIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var draggingOverlayID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Card selector
            if cards.count > 1 {
                HStack {
                    Text("Preview Card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Card", selection: $selectedCardIndex) {
                        ForEach(0..<cards.count, id: \.self) { index in
                            Text("Card #\(cards[index].id)").tag(index)
                        }
                    }
                    .frame(maxWidth: 140)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }

            // Live preview with interactive overlays
            ScrollView {
                VStack {
                    if selectedCardIndex < cards.count {
                        cardPreview
                    } else {
                        ContentUnavailableView(
                            "No Cards",
                            systemImage: "square.grid.3x3",
                            description: Text("This playlist has no generated cards.")
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(Color.gray.opacity(0.08))
        }
        .onChange(of: cards.count) {
            if selectedCardIndex >= cards.count {
                selectedCardIndex = 0
            }
        }
    }

    // MARK: - Card Preview

    /// Page margin as a fraction of page size (matches PDF: 36pt on 612pt width)
    private let pageMarginFraction: CGFloat = 36.0 / 612.0

    /// The printed sheet, laid out by the same geometry the PDF exporter uses,
    /// so what's on screen is what comes out of the printer.
    private var cardPreview: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.white

                ForEach(0..<max(settings.cardsPerPage, 1), id: \.self) { slot in
                    let rect = settings.cardRect(forSlot: slot, scaledTo: geo.size)
                    cardSlot(slot: slot, canvas: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .aspectRatio(settings.pageAspectRatio, contentMode: .fit)
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.2), value: settings.pageOrientation)
        .animation(.easeInOut(duration: 0.2), value: settings.cardsPerPage)
    }

    /// One card on the sheet, composed at the exporter's reference width and
    /// scaled down. Font sizes are absolute points, so composing straight into
    /// a small 4-up slot collapses the grid.
    ///
    /// Overlays are draggable on the first slot only; the rest show the
    /// arrangement.
    @ViewBuilder
    private func cardSlot(slot: Int, canvas: CGSize) -> some View {
        let cardIndex = (selectedCardIndex + slot) % max(cards.count, 1)

        if cards.indices.contains(cardIndex) {
            ZStack {
                CardWithOverlaysView(
                    card: cards[cardIndex],
                    songs: songs,
                    songKeys: songKeys,
                    settings: settings,
                    setID: setID
                )
                .frame(
                    width: CardDesignSettings.cardReferenceSize.width,
                    height: CardDesignSettings.cardReferenceSize.height
                )
                .scaleEffect(canvas.width / CardDesignSettings.cardReferenceWidth, anchor: .center)
                .frame(width: canvas.width, height: canvas.height)
                .clipped()

                if slot == 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selectedOverlayID = nil }

                    GeometryReader { geo in
                        ForEach(Array(settings.imageOverlays.enumerated()), id: \.element.id) { index, overlay in
                            overlayHandle(index: index, overlay: overlay, geoSize: geo.size)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Overlay Handle

    private func overlayHandle(index: Int, overlay: ImageOverlay, geoSize: CGSize) -> some View {
        let nsImage = overlay.cachedImage
        let imageAspect: CGFloat = {
            guard let img = nsImage else { return 1 }
            return img.size.width / max(img.size.height, 1)
        }()
        let imageWidth = geoSize.width * overlay.normalizedScale
        let imageHeight = imageWidth / max(imageAspect, 0.01)
        let isSelected = selectedOverlayID == overlay.id
        let isDragging = draggingOverlayID == overlay.id

        let baseX = overlay.normalizedX * geoSize.width
        let baseY = overlay.normalizedY * geoSize.height
        let displayX = isDragging ? baseX + dragOffset.width : baseX
        let displayY = isDragging ? baseY + dragOffset.height : baseY

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: imageWidth, height: imageHeight)
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .position(x: displayX, y: displayY)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        draggingOverlayID = overlay.id
                        selectedOverlayID = overlay.id
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard index < settings.imageOverlays.count else { return }
                        let finalX = (overlay.normalizedX * geoSize.width + value.translation.width) / geoSize.width
                        let finalY = (overlay.normalizedY * geoSize.height + value.translation.height) / geoSize.height
                        settings.imageOverlays[index].normalizedX = min(max(finalX, 0), 1)
                        settings.imageOverlays[index].normalizedY = min(max(finalY, 0), 1)
                        dragOffset = .zero
                        draggingOverlayID = nil
                    }
            )
            .onTapGesture {
                selectedOverlayID = overlay.id
            }
    }
}
