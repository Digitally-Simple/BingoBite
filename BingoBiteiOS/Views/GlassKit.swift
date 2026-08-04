import SwiftUI

/// The app's surface vocabulary.
///
/// Two tiers, split by what a surface actually sits on:
///
/// * **Floating chrome** — the player deck, which hovers over scrolling
///   content. Real content passes behind it, so it uses `Glass.clear` and
///   genuinely refracts, exactly like the Music player.
/// * **Content cards** — panels sitting on the page itself. The page is flat
///   black or flat white, so clear glass there would refract nothing and the
///   card would vanish. These use a quiet neutral fill with a hairline edge:
///   structure without chrome.
enum Glassware {
    static let cardCorner: CGFloat = 20
    static let panelCorner: CGFloat = 24
    static let tileCorner: CGFloat = 16
    static let deckCorner: CGFloat = 30

    /// Floating material — transparent, never frosted. `interactive()` opts
    /// into the system's own liquid touch response, so the glass reacts to
    /// fingers as a material characteristic rather than anything we animate.
    static func floating(tint: Color? = nil) -> Glass {
        let base = tint.map { Glass.clear.tint($0.opacity(0.45)) } ?? Glass.clear
        return base.interactive()
    }
}

/// The flat field the whole app sits on: black in dark, white in light.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color.black : Color.white)
            .ignoresSafeArea()
    }
}

/// The quiet card surface — a near-invisible lift off the page plus a hairline
/// so edges stay readable at a glance.
private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var corner: CGFloat
    var tint: Color?

    private var fill: Color {
        if let tint { return tint.opacity(colorScheme == .dark ? 0.16 : 0.12) }
        return colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var stroke: Color {
        if let tint { return tint.opacity(colorScheme == .dark ? 0.40 : 0.35) }
        return colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.09)
    }

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
    }
}

extension View {
    /// A content card on the page.
    func glassCard(corner: CGFloat = Glassware.cardCorner, tint: Color? = nil) -> some View {
        modifier(CardSurface(corner: corner, tint: tint))
    }

    /// A content card that is tappable. Same surface — the press feedback comes
    /// from the button style, not from the material.
    func interactiveGlassCard(corner: CGFloat = Glassware.cardCorner, tint: Color? = nil) -> some View {
        modifier(CardSurface(corner: corner, tint: tint))
    }

    /// A bar that floats over scrolling content. The one place real Liquid
    /// Glass earns its keep, because there is something behind it to bend.
    func glassDeck(corner: CGFloat = Glassware.deckCorner, tint: Color? = nil) -> some View {
        glassEffect(Glassware.floating(tint: tint), in: .rect(cornerRadius: corner))
            .shadow(color: .black.opacity(0.34), radius: 24, y: 10)
    }

    /// Puts a modally-presented surface on the same flat field as the window.
    func appSurface() -> some View {
        background { AppBackground() }
    }

    /// Section heading used above grouped content.
    func sectionHeadingStyle() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

/// Uppercase section label with consistent spacing.
struct SectionHeading: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .sectionHeadingStyle()
    }
}

/// Artwork with a music-note placeholder, used everywhere a song appears.
struct ArtworkView: View {
    let data: Data?
    var corner: CGFloat = 12
    var placeholderScale: CGFloat = 0.34

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let data, let image = PlatformImage(data: data) {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "music.note")
                            .font(.system(size: max(side * placeholderScale, 10)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

/// Key/value row used by the song detail panels.
struct DetailRow: View {
    let label: String
    let value: String
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)

            if showsDivider {
                Divider().padding(.leading, 18)
            }
        }
    }
}

/// Makes the whole disclosure header row tappable, not just the chevron.
struct TappableDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            }

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

/// Flow layout for the media-link pills.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}

// MARK: - Formatting

enum Format {
    /// m:ss, or h:mm:ss past an hour.
    static func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "--:--" }
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func relationshipType(_ type: String) -> String {
        switch type {
        case "samples":           "Samples"
        case "sampled_in":        "Sampled in"
        case "interpolates":      "Interpolates"
        case "interpolated_by":   "Interpolated by"
        case "cover_of":          "Cover of"
        case "covered_by":        "Covered by"
        case "remix_of":          "Remix of"
        case "remixed_by":        "Remixed by"
        case "live_version_of":   "Live version of"
        case "performed_live_as": "Performed live as"
        default:                  type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func providerName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":     "Spotify"
        case "apple_music": "Apple Music"
        case "youtube":     "YouTube"
        case "soundcloud":  "SoundCloud"
        default:            provider.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func providerIcon(_ provider: String) -> String {
        switch provider.lowercased() {
        case "youtube": "play.rectangle.fill"
        case "spotify", "apple_music", "soundcloud": "music.note"
        default: "link"
        }
    }
}
