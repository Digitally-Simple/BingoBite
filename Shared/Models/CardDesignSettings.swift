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

    // MARK: - Page Layout
    var cardsPerPage: Int = 1
    var pageOrientation: String = "portrait"

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
