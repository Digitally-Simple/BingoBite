import SwiftUI

/// The floating transport that hovers over every screen, modelled on the
/// iPadOS Music player: one clear-glass capsule holding a transport cluster on
/// the left, the now-playing identity in the middle, and contextual actions on
/// the right. Content scrolls underneath it rather than being pushed up.
struct PlayerDeck<Leading: View, Trailing: View>: View {
    /// Small label above the title — "Round 3 of 25", "Previewing clip".
    var eyebrow: String?
    var eyebrowTint: Color = .accentColor
    var artwork: Data?
    var title: String
    var subtitle: String
    /// 0…1 playhead, drawn as a hairline along the bottom edge.
    var progress: Double
    var onTapIdentity: (() -> Void)?

    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 18) {
                // The clusters hold their intrinsic size; the identity in the
                // middle is what gives way when the detail column is narrow.
                leading.layoutPriority(1)
                identity
                trailing.layoutPriority(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(alignment: .bottom) { progressLine }
            .glassDeck()
        }
        .frame(maxWidth: 940)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            ArtworkView(data: artwork, corner: 10)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(eyebrowTint)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTapIdentity?() }
        .accessibilityAddTraits(onTapIdentity == nil ? [] : .isButton)
    }

    private var progressLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.tint)
                .frame(width: geo.size.width * max(0, min(progress, 1)), height: 3)
                .animation(.linear(duration: 0.25), value: progress)
        }
        .frame(height: 3)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Controls

/// Borderless icon button sized for the deck. Deliberately *not* glass —
/// stacking glass inside glass muddies both layers, so the capsule is the only
/// material and its controls read as vibrant symbols on top of it.
struct DeckButton: View {
    let title: String
    let systemImage: String
    var prominence: Prominence = .standard
    var isOn = false
    var action: () -> Void

    enum Prominence {
        case standard, primary, quiet

        var font: Font {
            switch self {
            case .standard: .title3
            case .primary: .largeTitle
            case .quiet: .body
            }
        }

        var diameter: CGFloat {
            switch self {
            case .standard: 40
            case .primary: 50
            case .quiet: 34
            }
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(prominence.font)
                .fontWeight(prominence == .primary ? .regular : .medium)
                .frame(width: prominence.diameter, height: prominence.diameter)
                .background {
                    if isOn {
                        Circle().fill(.tint)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(DeckButtonStyle(isOn: isOn))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct DeckButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.3)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

/// The one filled control in the deck — the call to action that moves the game
/// forward. Tinted rather than glass so it stays legible over any artwork.
struct DeckPrimaryButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Capsule().fill(.tint))
                .foregroundStyle(.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Browsing deck

/// Deck shown while browsing playlists and libraries — plain preview playback.
struct NowPlayingDeck: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayerService
    var onInspect: () -> Void

    var body: some View {
        PlayerDeck(
            eyebrow: audioPlayer.isPreviewing ? "Sound byte preview" : nil,
            eyebrowTint: .accentColor,
            artwork: song.artworkData,
            title: song.displayTitle,
            subtitle: song.displayArtist,
            progress: audioPlayer.progress,
            onTapIdentity: onInspect
        ) {
            HStack(spacing: 4) {
                DeckButton(title: "Previous", systemImage: "backward.fill") {
                    audioPlayer.skipBackward()
                }
                .disabled(!audioPlayer.canSkipBackward)

                DeckButton(
                    title: audioPlayer.isPlaying ? "Pause" : "Play",
                    systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill",
                    prominence: .primary
                ) {
                    audioPlayer.togglePlayPause()
                }

                DeckButton(title: "Next", systemImage: "forward.fill") {
                    audioPlayer.skipForward()
                }
                .disabled(!audioPlayer.canSkipForward)
            }
        } trailing: {
            HStack(spacing: 6) {
                Text("\(audioPlayer.formattedCurrentTime) / \(audioPlayer.formattedDuration)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)

                DeckButton(title: "Song Details", systemImage: "info.circle", prominence: .quiet) {
                    onInspect()
                }

                DeckButton(title: "Stop", systemImage: "xmark", prominence: .quiet) {
                    audioPlayer.stop()
                }
            }
        }
    }
}

// MARK: - Game deck

/// Deck shown during a live game. The transport drives *rounds*, not just
/// playback: Previous and Next Song move the game on and rescore every board,
/// while the trailing cluster swaps what fills the screen behind the deck.
struct GameDeck: View {
    var roundLabel: String
    var song: Song?
    var isCompleted: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var isPlaying: Bool
    var canPlayPause: Bool
    var progress: Double
    @Binding var activeTab: GameTab

    var onPrevious: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onInspect: () -> Void

    /// Artist and album together — the host is reading these out loud, so the
    /// deck carries the same identifying detail the printed cards do.
    private var credit: String {
        guard let song else { return "Tap Next Song to reveal the first track" }
        let album = song.displayAlbum
        return album.isEmpty ? song.displayArtist : "\(song.displayArtist) · \(album)"
    }

    var body: some View {
        PlayerDeck(
            eyebrow: roundLabel,
            eyebrowTint: isCompleted ? .secondary : .accentColor,
            artwork: song?.artworkData,
            title: song?.displayTitle ?? "No song played yet",
            subtitle: credit,
            progress: progress,
            onTapIdentity: onInspect
        ) {
            if isCompleted {
                Label("Complete", systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            } else {
                HStack(spacing: 4) {
                    DeckButton(title: "Previous Round", systemImage: "backward.fill", action: onPrevious)
                        .disabled(!canGoBack)

                    DeckButton(
                        title: isPlaying ? "Pause" : "Play",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        prominence: .primary,
                        action: onPlayPause
                    )
                    .disabled(!canPlayPause)

                    DeckPrimaryButton(title: "Next Song", systemImage: "forward.fill", action: onNext)
                        .disabled(!canGoForward)
                        .padding(.leading, 6)
                }
            }
        } trailing: {
            HStack(spacing: 2) {
                ForEach(GameTab.allCases) { tab in
                    DeckButton(
                        title: tab.rawValue,
                        systemImage: tab.systemImage,
                        isOn: activeTab == tab
                    ) {
                        withAnimation(.smooth(duration: 0.25)) { activeTab = tab }
                    }
                }
            }
        }
    }
}
