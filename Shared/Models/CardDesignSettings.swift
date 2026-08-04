import SwiftUI

struct CardDesignSettings: Codable, Equatable {
    // MARK: - Cell Content Toggles
    var showTrackName: Bool = true
    var showArtistName: Bool = true
    var showAlbumName: Bool = false
    var showArtwork: Bool = false
    var useArtworkAsBackground: Bool = false
    var artworkBackgroundOpacity: CGFloat = 0.4

    // MARK: - Typography
    var fontFamily: String = "System"
    var trackNameFontSize: CGFloat = 11
    var artistNameFontSize: CGFloat = 9
    var albumNameFontSize: CGFloat = 8
    var fontWeight: String = "regular"
    var shrinkTextToFit: Bool = false

    // MARK: - Colors
    var cellBackgroundHex: String = "#FFFFFF"
    var cellTextColorHex: String = "#000000"
    var headerBackgroundHex: String = "#2C5F2D"
    var headerTextColorHex: String = "#FFFFFF"
    var cardBackgroundHex: String = "#FFFFFF"
    var borderColorHex: String = "#333333"
    var borderWidth: CGFloat = 1.0

    // MARK: - Card Title
    var cardTitle: String = "BINGO"
    var cardTitleFontSize: CGFloat = 28
    var cardTitleColorHex: String = "#2C5F2D"

    // MARK: - Free Space
    var freeSpaceText: String = "FREE"
    var freeSpaceColorHex: String = "#FFD700"

    // MARK: - Card Number
    var showCardNumbers: Bool = true
    var cardNumberFontSize: CGFloat = 10
    var cardNumberColorHex: String = "#999999"
    /// Print the deck's set code alongside the number, `AB-1` rather than
    /// `Card #1`, so shuffled decks can be told apart.
    var showSetID: Bool = true

    // MARK: - Page Layout
    var cardsPerPage: Int = 1
    var pageOrientation: String = "portrait"

    // MARK: - Page geometry
    //
    // One source of truth for page and card shape. These used to be a
    // hardcoded `8.5 / 11.0` in seven places, which meant switching to
    // landscape resized the paper but left the card portrait — so the card
    // just shrank and the preview never changed at all.

    /// US Letter in points, long edge horizontal when landscape.
    static let letterShortEdge: CGFloat = 612
    static let letterLongEdge: CGFloat = 792

    static let pageMargin: CGFloat = 36
    static let cardSpacing: CGFloat = 12

    /// Width every card is laid out at before being scaled to its slot.
    ///
    /// Font sizes are absolute points, so a card composed directly into a
    /// small frame collapses — the text can't shrink and the grid gets
    /// squeezed. Both the PDF exporter and the preview compose at this width
    /// and scale the result, which keeps everything proportional and makes the
    /// two match.
    static let cardReferenceWidth: CGFloat = 370

    static var cardReferenceSize: CGSize {
        CGSize(width: cardReferenceWidth, height: cardReferenceWidth / cardAspectRatio)
    }

    var isLandscape: Bool { pageOrientation == "landscape" }

    var pageSize: CGSize {
        isLandscape
            ? CGSize(width: Self.letterLongEdge, height: Self.letterShortEdge)
            : CGSize(width: Self.letterShortEdge, height: Self.letterLongEdge)
    }

    var pageAspectRatio: CGFloat { pageSize.width / pageSize.height }

    /// How cards are arranged on the sheet.
    ///
    /// Two-up flips with the paper: stacked on portrait, side by side on
    /// landscape. Keeping it stacked on landscape would waste most of the
    /// width and print two tiny cards.
    var grid: (columns: Int, rows: Int) {
        switch max(cardsPerPage, 1) {
        case 1:  (1, 1)
        case 2:  isLandscape ? (2, 1) : (1, 2)
        case 4:  (2, 2)
        default: (1, 1)
        }
    }

    /// A bingo card is always 8.5:11, whatever the paper is doing.
    ///
    /// Orientation and cards-per-sheet change how many cards fit and where
    /// they sit — never the card's proportions. Letting a card stretch to fill
    /// its slot distorts the grid and looks wrong.
    static let cardAspectRatio: CGFloat = 8.5 / 11.0
    var cardAspectRatio: CGFloat { Self.cardAspectRatio }

    /// The area available to one card, before the card's own ratio is applied.
    var cardSlotSize: CGSize {
        let grid = grid
        let usableWidth = pageSize.width - (Self.pageMargin * 2)
        let usableHeight = pageSize.height - (Self.pageMargin * 2)
        let width = (usableWidth - Self.cardSpacing * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
        let height = (usableHeight - Self.cardSpacing * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return CGSize(width: width, height: height)
    }

    /// The card's printed size: the largest 8.5:11 rectangle that fits the slot.
    var cardSize: CGSize {
        let slot = cardSlotSize
        let width = min(slot.width, slot.height * Self.cardAspectRatio)
        return CGSize(width: width, height: width / Self.cardAspectRatio)
    }

    /// Frame for the card in the given slot, with the whole block of cards
    /// centred on the sheet.
    func cardRect(forSlot slot: Int) -> CGRect {
        let grid = grid
        let size = cardSize
        let totalWidth = size.width * CGFloat(grid.columns) + Self.cardSpacing * CGFloat(grid.columns - 1)
        let totalHeight = size.height * CGFloat(grid.rows) + Self.cardSpacing * CGFloat(grid.rows - 1)
        let originX = (pageSize.width - totalWidth) / 2
        let originY = (pageSize.height - totalHeight) / 2

        let column = slot % grid.columns
        let row = slot / grid.columns
        return CGRect(
            x: originX + CGFloat(column) * (size.width + Self.cardSpacing),
            y: originY + CGFloat(row) * (size.height + Self.cardSpacing),
            width: size.width,
            height: size.height
        )
    }

    /// The same rect expressed in a preview of `previewSize`, so the on-screen
    /// sheet and the PDF are laid out by identical maths.
    func cardRect(forSlot slot: Int, scaledTo previewSize: CGSize) -> CGRect {
        let scale = previewSize.width / pageSize.width
        let rect = cardRect(forSlot: slot)
        return CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    // MARK: - Image Overlays
    var imageOverlays: [ImageOverlay] = []

    // MARK: - Encoding

    func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    static func decode(from data: Data?) -> CardDesignSettings {
        guard let data, !data.isEmpty else { return CardDesignSettings() }
        return (try? JSONDecoder().decode(CardDesignSettings.self, from: data)) ?? CardDesignSettings()
    }

    // MARK: - Font Helpers

    var resolvedFontWeight: Font.Weight {
        switch fontWeight {
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    func font(size: CGFloat) -> Font {
        if fontFamily == "System" {
            return .system(size: size, weight: resolvedFontWeight)
        }
        return .custom(fontFamily, size: size)
    }
}

// MARK: - Color ↔ Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        #if os(macOS)
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Creates a two-way binding between a hex string and a SwiftUI Color.
func hexColorBinding(_ source: Binding<String>) -> Binding<Color> {
    Binding<Color>(
        get: { Color(hex: source.wrappedValue) },
        set: { source.wrappedValue = $0.toHex() }
    )
}
