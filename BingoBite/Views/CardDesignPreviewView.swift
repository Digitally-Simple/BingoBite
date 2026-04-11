import SwiftUI

struct CardDesignPreviewView: View {
    var cards: [BingoCard]
    var songs: [Song]
    var songURLStrings: [String]
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?

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

    private var cardPreview: some View {
        // Simulate the PDF page: card inside margins, letter aspect ratio
        ZStack {
            // Page background
            Color.white

            // Card centered within page margins
            ZStack {
                CardWithOverlaysView(
                    card: cards[selectedCardIndex],
                    songs: songs,
                    songURLStrings: songURLStrings,
                    settings: settings
                )

                // Interactive gesture handles (preview only)
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedOverlayID = nil
                        }

                    ForEach(Array(settings.imageOverlays.enumerated()), id: \.element.id) { index, overlay in
                        overlayHandle(index: index, overlay: overlay, geoSize: geo.size)
                    }
                }
            }
            .padding(pageMarginFraction * 420)
        }
        .aspectRatio(8.5 / 11.0, contentMode: .fit)
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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
