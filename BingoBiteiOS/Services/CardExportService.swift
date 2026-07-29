import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iPad counterpart to the Mac card exporter. Renders each bingo card with
/// `ImageRenderer` and lays them out on US Letter pages via
/// `UIGraphicsPDFRenderer`, then hands the PDF to the share sheet or AirPrint.
enum CardExportService {

    // MARK: - PDF Generation

    @MainActor
    static func generatePDF(
        cards: [BingoCard],
        songs: [Song],
        songURLStrings: [String],
        settings: CardDesignSettings
    ) -> Data? {
        guard !cards.isEmpty else { return nil }

        let pageSize = settings.pageOrientation == "landscape"
            ? CGSize(width: 792, height: 612)
            : CGSize(width: 612, height: 792)

        let cardsPerPage = max(settings.cardsPerPage, 1)
        let pageCount = (cards.count + cardsPerPage - 1) / cardsPerPage

        // Render each card once at a fixed reference size so font sizes stay
        // proportional regardless of how many cards share a page.
        let referenceWidth: CGFloat = 370
        let referenceHeight = referenceWidth / (8.5 / 11.0)

        var renderedCards: [Int: UIImage] = [:]
        for card in cards {
            let cardView = CardWithOverlaysView(
                card: card,
                songs: songs,
                songURLStrings: songURLStrings,
                settings: settings
            )
            let renderer = ImageRenderer(content: cardView.frame(width: referenceWidth, height: referenceHeight))
            renderer.scale = 3.0
            if let image = renderer.uiImage {
                renderedCards[card.id] = image
            }
        }

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )

        return renderer.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                let startIndex = page * cardsPerPage
                let endIndex = min(startIndex + cardsPerPage, cards.count)

                for (slotIndex, card) in cards[startIndex..<endIndex].enumerated() {
                    guard let image = renderedCards[card.id] else { continue }
                    let rect = cardRect(for: slotIndex, cardsPerPage: cardsPerPage, pageSize: pageSize)
                    image.draw(in: rect)
                }
            }
        }
    }

    /// Writes the PDF to a temporary file so it can be shared or previewed.
    @MainActor
    static func writeTemporaryPDF(
        cards: [BingoCard],
        songs: [Song],
        songURLStrings: [String],
        settings: CardDesignSettings,
        defaultName: String
    ) -> URL? {
        guard let data = generatePDF(
            cards: cards,
            songs: songs,
            songURLStrings: songURLStrings,
            settings: settings
        ) else { return nil }

        let safeName = defaultName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName) - Bingo Cards.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("CardExportService: failed to write PDF — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Print

    @MainActor
    static func printCards(pdfURL: URL, jobName: String, orientation: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        info.orientation = orientation == "landscape" ? .landscape : .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdfURL
        controller.present(animated: true)
    }

    // MARK: - Layout Helpers

    /// Fits a card with an 8.5:11 aspect ratio into its slot on the page.
    /// Coordinates are top-left origin (UIKit), unlike the Mac implementation.
    private static func cardRect(
        for slot: Int,
        cardsPerPage: Int,
        pageSize: CGSize
    ) -> CGRect {
        let margin: CGFloat = 36
        let usableWidth = pageSize.width - (margin * 2)
        let usableHeight = pageSize.height - (margin * 2)
        let cardRatio: CGFloat = 8.5 / 11.0

        switch cardsPerPage {
        case 1:
            let (w, h) = fitSize(ratio: cardRatio, maxWidth: usableWidth, maxHeight: usableHeight)
            return CGRect(
                x: (pageSize.width - w) / 2,
                y: (pageSize.height - h) / 2,
                width: w,
                height: h
            )
        case 2:
            let spacing: CGFloat = 12
            let slotHeight = (usableHeight - spacing) / 2
            let (w, h) = fitSize(ratio: cardRatio, maxWidth: usableWidth, maxHeight: slotHeight)
            let totalHeight = h * 2 + spacing
            let topY = (pageSize.height - totalHeight) / 2
            return CGRect(
                x: (pageSize.width - w) / 2,
                y: topY + CGFloat(slot) * (h + spacing),
                width: w,
                height: h
            )
        case 4:
            let spacing: CGFloat = 12
            let slotWidth = (usableWidth - spacing) / 2
            let slotHeight = (usableHeight - spacing) / 2
            let (w, h) = fitSize(ratio: cardRatio, maxWidth: slotWidth, maxHeight: slotHeight)
            let col = slot % 2
            let row = slot / 2
            let totalWidth = w * 2 + spacing
            let totalHeight = h * 2 + spacing
            return CGRect(
                x: (pageSize.width - totalWidth) / 2 + CGFloat(col) * (w + spacing),
                y: (pageSize.height - totalHeight) / 2 + CGFloat(row) * (h + spacing),
                width: w,
                height: h
            )
        default:
            return .zero
        }
    }

    /// Largest (width, height) fitting inside the bounds at the given ratio.
    private static func fitSize(ratio: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> (CGFloat, CGFloat) {
        let w = min(maxWidth, maxHeight * ratio)
        let h = w / ratio
        return (w, h)
    }
}

// MARK: - Share sheet

/// Wraps `UIActivityViewController` so exported PDFs can be shared, saved back
/// to Files, or sent to another app.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
