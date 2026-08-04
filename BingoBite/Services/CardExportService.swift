import SwiftUI
import PDFKit
import UniformTypeIdentifiers

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
        let pageSize = settings.pageSize
        let cardsPerPage = max(settings.cardsPerPage, 1)
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
                let rect = settings.cardRect(forSlot: slotIndex)

                // Render at a fixed reference width matching the preview, so
                // font sizes appear proportionally the same. The aspect must
                // match the slot or the card is stretched to fit it.
                let referenceWidth = CardDesignSettings.cardReferenceWidth
                let referenceHeight = CardDesignSettings.cardReferenceSize.height

                let cardView = CardWithOverlaysView(
                    card: card,
                    songs: songs,
                    songKeys: songKeys,
                    settings: settings,
                    setID: setID
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
        songKeys: [String],
        settings: CardDesignSettings,
        setID: String = "",
        defaultName: String
    ) {
        guard let pdfData = generatePDF(
            cards: cards,
            songs: songs,
            songKeys: songKeys,
            settings: settings,
            setID: setID
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
        songKeys: [String],
        settings: CardDesignSettings,
        setID: String = ""
    ) {
        guard let pdfData = generatePDF(
            cards: cards,
            songs: songs,
            songKeys: songKeys,
            settings: settings,
            setID: setID
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

}
