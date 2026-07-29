import SwiftUI

/// The Live Activity palette.
///
/// Defined in code rather than in an asset catalog so the widget extension and
/// the app resolve identical values without shipping a second catalog — and so
/// the card keeps its own dark identity on a Lock Screen that may be light.
enum BingoActivityTheme {
    /// The app's accent, hard-coded so the extension doesn't need the catalog.
    static let live = Color(red: 1.000, green: 0.259, blue: 0.353)
    static let paused = Color(red: 1.000, green: 0.702, blue: 0.251)
    static let done = Color(red: 0.188, green: 0.820, blue: 0.345)
    /// The one high-attention colour, reserved for a bingo and for the primary
    /// action — the same job Flighty's yellow gate pill does.
    static let gold = Color(red: 1.000, green: 0.831, blue: 0.149)

    static let card = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.20)
    static let control = Color.white.opacity(0.12)
}

extension BingoGameActivityAttributes.ContentState {
    /// One colour carries the whole state — everything accented picks it up.
    var tint: Color {
        switch phase {
        case .ready:     return BingoActivityTheme.dim
        case .playing:   return BingoActivityTheme.live
        case .paused:    return BingoActivityTheme.paused
        case .completed: return BingoActivityTheme.done
        }
    }
}
