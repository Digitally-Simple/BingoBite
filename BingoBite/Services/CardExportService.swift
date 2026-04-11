import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum CardExportService {

    // MARK: - PDF Generation

    @MainActor
    static func generatePDF(
        cards: [BingoCard],
        songs: [Song],
        songURLStrings: [String],
        settings: CardDesignSettings
    ) -> Data? {
        let pageSize = settings.pageOrientation == "landscape"
            ? CGSize(width: 792, height: 612)
            : CGSize(width: 612, height: 792)

        let cardsPerPage = settings.cardsPerPage
        let pageCount = (cards.count + cardsPerPage - 1) / cardsPerPage

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let cgContext = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                        mediaBox: &mediaBox, nil) else {
            return nil
        }

        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)

        for page in 0..<pageCount {
            let startIndex = page * cardsPerPage
            let endIndex = min(startIndex + cardsPerPage, cards.count)
            let pageCards = Array(cards[startIndex..<endIndex])

            cgContext.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            for (slotIndex, card) in pageCards.enumerated() {
                let rect = cardRect(for: slotIndex, cardsPerPage: cardsPerPage, pageSize: pageSize)

                // Render at a fixed reference width matching the preview,
                // so font sizes appear proportionally the same.
                let referenceWidth: CGFloat = 370
                let referenceHeight = referenceWidth / (8.5 / 11.0)

                let cardView = CardWithOverlaysView(
                    card: card,
                    songs: songs,
                    songURLStrings: songURLStrings,
                    settings: settings
                )
                let renderer = ImageRenderer(content: cardView.frame(width: referenceWidth, height: referenceHeight))
                renderer.scale = rect.width / referenceWidth * 2.0

                if let nsImage = renderer.nsImage {
                    nsImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            cgContext.endPDFPage()
        }

        cgContext.closePDF()
        return pdfData as Data
    }

    // MARK: - Export to File

    @MainActor
    static func exportPDF(
        cards: [BingoCard],
        songs: [Song],
        songURLStrings: [String],
        settings: CardDesignSettings,
        defaultName: String
    ) {
        guard let pdfData = generatePDF(
            cards: cards,
            songs: songs,
            songURLStrings: songURLStrings,
            settings: settings
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(defaultName) - Bingo Cards.pdf"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pdfData.write(to: url)
    }

    // MARK: - Print

    @MainActor
    static func printCards(
        cards: [BingoCard],
        songs: [Song],
        songURLStrings: [String],
        settings: CardDesignSettings
    ) {
        guard let pdfData = generatePDF(
            cards: cards,
            songs: songs,
            songURLStrings: songURLStrings,
            settings: settings
        ) else { return }

        guard let pdfDocument = PDFDocument(data: pdfData) else { return }

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.orientation = settings.pageOrientation == "landscape" ? .landscape : .portrait
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let pdfView = PDFView()
        pdfView.document = pdfDocument
        pdfView.print(with: printInfo, autoRotate: true, pageScaling: .pageScaleToFit)
    }

    // MARK: - Layout Helpers

    /// Fits a card with 8.5:11 aspect ratio into the given slot on the page.
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
            // Fit one 8.5:11 card in the usable area
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
            let topY = (pageSize.height + totalHeight) / 2 - h
            let y = topY - CGFloat(slot) * (h + spacing)
            return CGRect(
                x: (pageSize.width - w) / 2,
                y: y,
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
            let startX = (pageSize.width - totalWidth) / 2
            let topY = (pageSize.height + totalHeight) / 2 - h
            return CGRect(
                x: startX + CGFloat(col) * (w + spacing),
                y: topY - CGFloat(row) * (h + spacing),
                width: w,
                height: h
            )
        default:
            return .zero
        }
    }

    /// Returns the largest (width, height) that fits within maxWidth x maxHeight
    /// while maintaining the given width:height ratio.
    private static func fitSize(ratio: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> (CGFloat, CGFloat) {
        let w = min(maxWidth, maxHeight * ratio)
        let h = w / ratio
        return (w, h)
    }
}
