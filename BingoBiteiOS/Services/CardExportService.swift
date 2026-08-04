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
        songKeys: [String],
        settings: CardDesignSettings,
        setID: String = ""
    ) -> Data? {
        guard !cards.isEmpty else { return nil }

        let pageSize = settings.pageSize
        let cardsPerPage = max(settings.cardsPerPage, 1)
        let pageCount = (cards.count + cardsPerPage - 1) / cardsPerPage

        // Render each card once at a fixed reference size so font sizes stay
        // proportional regardless of how many cards share a page. The aspect
        // must match the slot it will be drawn into, or the card is stretched.
        let referenceWidth = CardDesignSettings.cardReferenceWidth
        let referenceHeight = CardDesignSettings.cardReferenceSize.height

        var renderedCards: [Int: UIImage] = [:]
        for card in cards {
            let cardView = CardWithOverlaysView(
                card: card,
                songs: songs,
                songKeys: songKeys,
                settings: settings,
                setID: setID
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
                    image.draw(in: settings.cardRect(forSlot: slotIndex))
                }
            }
        }
    }

    /// Writes the PDF to a temporary file so it can be shared or previewed.
    @MainActor
    static func writeTemporaryPDF(
        cards: [BingoCard],
        songs: [Song],
        songKeys: [String],
        settings: CardDesignSettings,
        setID: String = "",
        defaultName: String
    ) -> URL? {
        guard let data = generatePDF(
            cards: cards,
            songs: songs,
            songKeys: songKeys,
            settings: settings,
            setID: setID
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
