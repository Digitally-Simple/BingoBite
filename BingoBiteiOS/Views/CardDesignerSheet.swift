import SwiftUI
import SwiftData
import PhotosUI

/// Live card designer: controls on the left, a page-accurate preview on the
/// right, then export to PDF or AirPrint.
struct CardDesignerSheet: View {
    var playlist: Playlist
    var songs: [Song]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var settings: CardDesignSettings
    @State private var selectedOverlayID: String?
    @State private var exportedPDF: URL?
    @State private var showShareSheet = false
    @State private var isExporting = false
    /// Edited here rather than read straight off the playlist so a cancelled
    /// edit doesn't leave a half-typed code on the model.
    @State private var setID: String

    init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs
        _settings = State(initialValue: CardDesignSettings.decode(from: playlist.cardDesignData))
        _setID = State(initialValue: playlist.setID)
    }

    private var cards: [BingoCard] {
        CardGenerator.decode(from: playlist.cardsData).enumerated().map { BingoCard(id: $0.offset + 1, grid: $0.element) }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                CardDesignControlsView(
                    settings: $settings,
                    selectedOverlayID: $selectedOverlayID,
                    setID: $setID
                )
                .frame(width: 380)

                Divider()

                CardDesignPreviewView(
                    cards: cards,
                    songs: songs,
                    songKeys: playlist.songKeys,
                    settings: $settings,
                    selectedOverlayID: $selectedOverlayID,
                    setID: setID
                )
                .frame(maxWidth: .infinity)
            }
            .appSurface()
            .navigationTitle("Design & Print Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        settings = CardDesignSettings()
                        selectedOverlayID = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Print", systemImage: "printer") { export(andPrint: true) }
                        .buttonStyle(.glass)
                        .disabled(cards.isEmpty || isExporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export PDF", systemImage: "square.and.arrow.up") { export(andPrint: false) }
                        .buttonStyle(.glassProminent)
                        .disabled(cards.isEmpty || isExporting)
                }
            }
            .overlay {
                if isExporting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Rendering \(cards.count) cards…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .glassCard(corner: Glassware.panelCorner)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportedPDF {
                    ShareSheet(items: [exportedPDF])
                }
            }
        }
        .onDisappear { save() }
    }

    private func save() {
        playlist.cardDesignData = settings.encode()
        playlist.setID = setID
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        try? modelContext.save()
    }

    private func export(andPrint: Bool) {
        save()
        isExporting = true

        // Hop off this run loop so the progress overlay paints before the
        // (synchronous, potentially slow) render begins.
        Task { @MainActor in
            defer { isExporting = false }
            guard let url = CardExportService.writeTemporaryPDF(
                cards: cards,
                songs: songs,
                songKeys: playlist.songKeys,
                settings: settings,
                setID: playlist.setID,
                defaultName: playlist.name
            ) else { return }

            exportedPDF = url
            if andPrint {
                CardExportService.printCards(
                    pdfURL: url,
                    jobName: "\(playlist.name) — Bingo Cards",
                    orientation: settings.pageOrientation
                )
            } else {
                showShareSheet = true
            }
        }
    }
}

// MARK: - Preview pane

struct CardDesignPreviewView: View {
    var cards: [BingoCard]
    var songs: [Song]
    var songKeys: [String]
    @Binding var settings: CardDesignSettings
    @Binding var selectedOverlayID: String?
    /// The deck's set code, printed alongside each card number.
    var setID: String = ""

    @State private var selectedCardIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var draggingOverlayID: String?

    /// Matches the PDF's 36pt margin on a 612pt-wide page.
    private let pageMarginFraction: CGFloat = 36.0 / 612.0
    private let pageWidth: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            if cards.count > 1 {
                HStack {
                    Text("Preview")
                        .sectionHeadingStyle()
                    Spacer()
                    Picker("Card", selection: $selectedCardIndex) {
                        ForEach(cards.indices, id: \.self) { index in
                            Text("Card #\(cards[index].id)").tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            ScrollView {
                if cards.indices.contains(selectedCardIndex) {
                    page
                        .padding(28)
                } else {
                    ContentUnavailableView("No Cards", systemImage: "square.grid.3x3")
                        .padding(40)
                }
            }
        }
        .background(.quaternary.opacity(0.4))
        .onChange(of: cards.count) {
            if selectedCardIndex >= cards.count { selectedCardIndex = 0 }
        }
    }

    /// The printed sheet, laid out by the same geometry the PDF exporter uses,
    /// so what's on screen is what comes out of the printer.
    ///
    /// Cards after the first are filled with the following cards in the deck,
    /// which is what actually gets printed on that sheet.
    private var page: some View {
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
        .frame(maxWidth: pageWidth)
        .animation(.easeInOut(duration: 0.2), value: settings.pageOrientation)
        .animation(.easeInOut(duration: 0.2), value: settings.cardsPerPage)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    /// One card on the sheet. The slot shows the card that would actually be
    /// printed there — the selected card first, then the ones following it.
    ///
    /// Overlays are only draggable on the first slot; the rest are there to
    /// show the arrangement, and having four live drag targets for the same
    /// overlay would be ambiguous.
    @ViewBuilder
    private func cardSlot(slot: Int, canvas: CGSize) -> some View {
        let cardIndex = (selectedCardIndex + slot) % max(cards.count, 1)

        if cards.indices.contains(cardIndex) {
            ZStack {
                // Composed at the exporter's reference width and scaled down,
                // rather than laid out directly into a small frame. Font sizes
                // are absolute points, so composing straight into a 4-up slot
                // collapses the grid.
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
                .scaleEffect(
                    canvas.width / CardDesignSettings.cardReferenceWidth,
                    anchor: .center
                )
                .frame(width: canvas.width, height: canvas.height)
                .clipped()

                if slot == 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selectedOverlayID = nil }

                    ForEach(Array(settings.imageOverlays.enumerated()), id: \.element.id) { index, overlay in
                        overlayHandle(index: index, overlay: overlay, canvas: canvas)
                    }
                }
            }
        }
    }

    /// Invisible drag target sitting over each overlay in the preview.
    private func overlayHandle(index: Int, overlay: ImageOverlay, canvas: CGSize) -> some View {
        let aspect = overlay.cachedImage.map { $0.size.width / max($0.size.height, 1) } ?? 1
        let width = canvas.width * overlay.normalizedScale
        let height = width / max(aspect, 0.01)
        let isSelected = selectedOverlayID == overlay.id
        let isDragging = draggingOverlayID == overlay.id

        let x = overlay.normalizedX * canvas.width + (isDragging ? dragOffset.width : 0)
        let y = overlay.normalizedY * canvas.height + (isDragging ? dragOffset.height : 0)

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: width, height: height)
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        .foregroundStyle(.tint)
                }
            }
            .position(x: x, y: y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        draggingOverlayID = overlay.id
                        selectedOverlayID = overlay.id
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard settings.imageOverlays.indices.contains(index) else { return }
                        let finalX = (overlay.normalizedX * canvas.width + value.translation.width) / canvas.width
                        let finalY = (overlay.normalizedY * canvas.height + value.translation.height) / canvas.height
                        settings.imageOverlays[index].normalizedX = min(max(finalX, 0), 1)
                        settings.imageOverlays[index].normalizedY = min(max(finalY, 0), 1)
                        dragOffset = .zero
                        draggingOverlayID = nil
                    }
            )
            .onTapGesture { selectedOverlayID = overlay.id }
    }
}
