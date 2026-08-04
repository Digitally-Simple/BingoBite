import SwiftData
import SwiftUI

/// The floating transport row, modelled on the iPadOS Music player: a
/// transport cluster on the left, the now-playing identity in the middle, and
/// contextual actions on the right. The row carries no glass of its own — the
/// owning deck applies `glassDeck()`, so a deck can stack extra content above
/// the row inside the same pane (the browsing deck grows taller this way).
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

// MARK: - Grabbable glass

/// The floating pane both decks live in.
///
/// It owns the *material* — the rounded rectangle, the tall state, and the
/// grab-and-stretch gesture — while each deck supplies what goes inside: a
/// transport row, and the taller content that rises above it. Tap the identity
/// and the top edge rises; tap again to lower it. Press and hold and the bar
/// "grabs" (a small pop); drag while holding and the glass stretches from that
/// edge or corner with rubber-band resistance, then snaps back on release.
struct GrabbableDeck<Expanded: View, Row: View>: View {
    /// The tall half, handed the closure that lowers the deck again.
    @ViewBuilder var expanded: (@escaping () -> Void) -> Expanded
    /// The always-visible row, handed the current state and the toggle.
    @ViewBuilder var row: (Bool, @escaping () -> Void) -> Row

    @State private var isExpanded = false

    /// Live drag translation while the glass is being pulled.
    @State private var stretch: CGSize = .zero
    /// True from the moment the hold "grabs" until release.
    @State private var isGrabbed = false
    /// The pinned corner the stretch scales away from — the opposite of where
    /// the finger grabbed. Kept after release so the snap-back animates from
    /// the same anchor.
    @State private var stretchAnchor: UnitPoint = .center
    @State private var deckSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expanded { setExpanded(false) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            row(isExpanded) { setExpanded(!isExpanded) }
        }
        // Clip to the deck shape so the expanded content stays inside the
        // rectangle while the top edge is mid-animation.
        .clipShape(RoundedRectangle(cornerRadius: Glassware.deckCorner, style: .continuous))
        .glassDeck()
        .scaleEffect(x: stretchScale.x, y: stretchScale.y, anchor: stretchAnchor)
        .frame(maxWidth: 940)
        // Covers the whole pane, including the quiet zones between controls,
        // so touches land on the glass instead of passing through to the
        // content scrolling underneath.
        .contentShape(RoundedRectangle(cornerRadius: Glassware.deckCorner, style: .continuous))
        // Simultaneous so the hold still registers on children with their own
        // gestures (the identity's tap); quick taps never reach the hold
        // threshold, so buttons behave normally.
        .simultaneousGesture(grabGesture)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            deckSize = size
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isGrabbed) { _, grabbed in grabbed }
        .sensoryFeedback(.impact(weight: .medium), trigger: isExpanded)
        .accessibilityAction(named: isExpanded ? "Collapse player" : "Expand player") {
            setExpanded(!isExpanded)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.smooth(duration: 0.4)) { isExpanded = expanded }
    }

    // MARK: Grab & stretch

    /// Hold to grab, then either release in place (toggle the tall shape) or
    /// pull to stretch the glass. The stretch is a rubber band: response
    /// diminishes as the pull grows, and release springs everything home.
    private var grabGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, nil):
                    isGrabbed = true
                case .second(true, .some(let drag)):
                    isGrabbed = true
                    stretchAnchor = Self.pinnedCorner(for: drag.startLocation, in: deckSize)
                    stretch = drag.translation
                default:
                    break
                }
            }
            .onEnded { value in
                var moved = false
                if case .second(true, .some(let drag)) = value {
                    moved = abs(drag.translation.width) > 12 || abs(drag.translation.height) > 12
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    stretch = .zero
                    isGrabbed = false
                }
                if !moved { setExpanded(!isExpanded) }
            }
    }

    /// Grabbing near a side pins the opposite side; grabbing the horizontal
    /// middle pins nothing on that axis, so the pull reads as the whole bar
    /// flexing. Vertically there is no dead band — the bar is short, so any
    /// grab pins the opposite edge and a vertical pull always stretches.
    private static func pinnedCorner(for grab: CGPoint, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        let ux = grab.x / size.width
        let uy = grab.y / size.height
        let anchorX: CGFloat = ux < 0.33 ? 1 : (ux > 0.67 ? 0 : 0.5)
        let anchorY: CGFloat = uy < 0.5 ? 1 : 0
        return UnitPoint(x: anchorX, y: anchorY)
    }

    /// Damped, capped scale factors: `tanh` gives a strong response to the
    /// first few points of pull that flattens out, so the glass feels elastic
    /// rather than glued to the finger.
    private var stretchScale: (x: CGFloat, y: CGFloat) {
        guard deckSize.width > 0, deckSize.height > 0, isGrabbed || stretch != .zero else {
            return (1, 1)
        }
        let dirX: CGFloat = stretchAnchor.x == 0 ? 1 : (stretchAnchor.x == 1 ? -1 : 0)
        let dirY: CGFloat = stretchAnchor.y == 0 ? 1 : (stretchAnchor.y == 1 ? -1 : 0)
        let px = stretch.width * dirX / deckSize.width
        let py = stretch.height * dirY / deckSize.height
        let grabPop: CGFloat = isGrabbed ? 1.015 : 1
        return (
            grabPop * (1 + 0.10 * tanh(2.5 * px)),
            grabPop * (1 + 0.22 * tanh(2.5 * py))
        )
    }
}

// MARK: - The row, short and tall

/// What sits along the bottom edge of a deck, in whichever of its two jobs it
/// currently has.
///
/// Short, the row *is* the player: identity and transport. Tall, all of that
/// has moved up into the pane, so leaving it here would say everything twice —
/// two artworks, two titles, two play buttons. The row hands its controls over
/// and becomes the playhead instead, and the swap is a blur-replace so the
/// controls read as moving rather than disappearing.
private struct DeckRow<Transport: View, Scrubber: View>: View {
    var isExpanded: Bool
    @ViewBuilder var transport: Transport
    @ViewBuilder var scrubber: Scrubber

    var body: some View {
        Group {
            if isExpanded {
                scrubber
            } else {
                transport
            }
        }
        .transition(.blurReplace)
    }
}

/// The trimmed window a round will actually play, if the host set one.
struct DeckClip: Equatable {
    /// Non-nil only where the host moved the handle off the file's own edge —
    /// which is what lets the scrubber say "Beginning" instead of "0:00".
    var start: TimeInterval?
    var end: TimeInterval?

    init?(_ byte: SoundByte?) {
        guard let byte else { return nil }
        start = byte.startTime > 0 ? byte.startTime : nil
        end = byte.endTime > 0 ? byte.endTime : nil
        if start == nil, end == nil { return nil }
    }

    /// Picks a song's trim out of a live `@Query` of every saved one. Reading
    /// from a query rather than fetching means a trim saved from the details
    /// sheet lands on the playhead straight away, without waiting for the deck
    /// to change songs.
    static func find(for song: Song?, in bytes: [SoundByte]) -> DeckClip? {
        guard let key = song?.stableKey else { return nil }
        return DeckClip(bytes.first { $0.songKey == key })
    }
}

/// The playhead a deck shows once it's tall.
///
/// Elapsed and total bookend a draggable track, and under them sit the sound
/// byte's in and out points — "Beginning" and "End" when the round plays the
/// whole file, the trimmed times when it doesn't. The trimmed window is drawn
/// on the track too, so a host can see how much of the song this round is
/// actually going to play without doing arithmetic.
private struct DeckScrubber: View {
    @ObservedObject var audioPlayer: AudioPlayerService
    var clip: DeckClip?

    /// Non-nil while the finger is down — the bar shows this instead of the
    /// live playhead so it doesn't fight the 0.25s progress ticker.
    @State private var scrubFraction: Double?

    private var displayedElapsed: TimeInterval {
        (scrubFraction ?? audioPlayer.progress) * audioPlayer.duration
    }

    private var inLabel: String {
        guard let start = clip?.start else { return "Beginning" }
        return "\(Format.time(start)) in"
    }

    private var outLabel: String {
        guard let end = clip?.end else { return "End" }
        return "\(Format.time(end)) out"
    }

    /// The clip as a 0…1 span of the file, or nil when there's nothing to draw.
    private var clipSpan: (start: Double, end: Double)? {
        guard let clip, audioPlayer.duration > 0 else { return nil }
        let start = min(max((clip.start ?? 0) / audioPlayer.duration, 0), 1)
        let end = min(max((clip.end ?? audioPlayer.duration) / audioPlayer.duration, 0), 1)
        guard end > start else { return nil }
        return (start, end)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            column(time: Format.time(displayedElapsed), caption: inLabel, alignment: .leading)
            track
            column(time: Format.time(audioPlayer.duration), caption: outLabel, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    private func column(time: String, caption: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(time)
                .font(.caption)
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(minWidth: 78, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = max(0, min(scrubFraction ?? audioPlayer.progress, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)

                if let span = clipSpan {
                    Capsule()
                        .fill(.tint.opacity(0.3))
                        .frame(width: width * (span.end - span.start))
                        .offset(x: width * span.start)
                }

                Capsule()
                    .fill(.tint)
                    .frame(width: width * fraction)
            }
            .frame(height: scrubFraction == nil ? 7 : 12)
            .frame(maxHeight: .infinity)
            .animation(scrubFraction == nil ? .linear(duration: 0.25) : nil, value: fraction)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubFraction = max(0, min(value.location.x / width, 1))
                    }
                    .onEnded { value in
                        audioPlayer.seek(to: max(0, min(value.location.x / width, 1)))
                        scrubFraction = nil
                    }
            )
        }
        .frame(height: 26)
        .animation(.smooth(duration: 0.2), value: scrubFraction == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playhead")
        .accessibilityValue(Text("\(Format.time(displayedElapsed)) of \(Format.time(audioPlayer.duration))"))
        .accessibilityAdjustableAction { direction in
            let step = 10.0 / max(audioPlayer.duration, 1)
            let target = audioPlayer.progress + (direction == .increment ? step : -step)
            audioPlayer.seek(to: max(0, min(target, 1)))
        }
    }
}

// MARK: - Browsing deck

/// Deck shown while browsing playlists and libraries — plain preview playback.
struct NowPlayingDeck: View {
    @Query private var soundBytes: [SoundByte]

    let song: Song
    @ObservedObject var audioPlayer: AudioPlayerService
    var onInspect: () -> Void

    private var clip: DeckClip? { DeckClip.find(for: song, in: soundBytes) }

    var body: some View {
        GrabbableDeck { collapse in
            NowPlayingExpandedContent(
                song: song,
                audioPlayer: audioPlayer,
                onInspect: onInspect,
                onCollapse: collapse
            )
        } row: { isExpanded, toggle in
            DeckRow(isExpanded: isExpanded) {
                transportRow(onTapIdentity: toggle)
            } scrubber: {
                DeckScrubber(audioPlayer: audioPlayer, clip: clip)
            }
        }
    }

    private func transportRow(onTapIdentity: @escaping () -> Void) -> some View {
        PlayerDeck(
            eyebrow: audioPlayer.isPreviewing ? "Sound byte preview" : nil,
            eyebrowTint: .accentColor,
            artwork: song.artworkData,
            title: song.displayTitle,
            subtitle: song.displayArtist,
            progress: audioPlayer.progress,
            // Tapping the identity grows/collapses the bar; the song details
            // sheet moved to the info buttons.
            onTapIdentity: onTapIdentity
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

// MARK: - Expanded content

/// The tall half of a deck, whichever deck it is: a grab chevron, big artwork,
/// and a metadata column beside it carrying every control the row gave up.
/// Collapses via the chevron, a downward swipe, or the grab gesture. The
/// playhead isn't here — it's the row, directly underneath.
private struct DeckExpandedShell<Details: View>: View {
    var artwork: Data?
    var onCollapse: () -> Void
    @ViewBuilder var details: Details

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.compact.down")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse player")

            HStack(alignment: .center, spacing: 26) {
                ArtworkView(data: artwork, corner: 20)
                    .frame(width: 210, height: 210)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

                details
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 560)
        }
        .padding(.top, 12)
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // Swipe down anywhere in the expanded area to collapse. The scrubber
        // lives in the row below this, so its drag never fights this one.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 60 { onCollapse() }
                }
        )
    }
}

/// The browsing deck's tall half: full metadata and the whole transport,
/// including the stop and details buttons the row was carrying.
private struct NowPlayingExpandedContent: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayerService
    var onInspect: () -> Void
    var onCollapse: () -> Void

    /// "Country · 2023" — whatever identifying facts the file actually has.
    private var facts: String {
        [song.genre, song.year].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    var body: some View {
        DeckExpandedShell(artwork: song.artworkData, onCollapse: onCollapse) {
            VStack(alignment: .leading, spacing: 5) {
                Text(song.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !song.displayAlbum.isEmpty {
                    Text(song.displayAlbum)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !facts.isEmpty {
                    Text(facts)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 1)
                }

                HStack(spacing: 8) {
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

                    DeckButton(title: "Song Details", systemImage: "info.circle", prominence: .quiet) {
                        onInspect()
                    }
                    .padding(.leading, 6)

                    DeckButton(title: "Stop", systemImage: "xmark", prominence: .quiet) {
                        audioPlayer.stop()
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

/// The game deck's tall half. Same shell, but the controls move *rounds* rather
/// than playback, so the cluster is the deck's own transport and the eyebrow
/// carries the round the room is on.
private struct GameDeckExpandedContent: View {
    var roundLabel: String
    var song: Song?
    var credit: String
    var isCompleted: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var isPlaying: Bool
    var canPlayPause: Bool
    var canShuffle: Bool
    var shuffleIncludesPreviouslyPlayed: Bool

    var onPrevious: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onShuffle: () -> Void
    var onInspect: () -> Void
    var onCollapse: () -> Void

    var body: some View {
        DeckExpandedShell(artwork: song?.artworkData, onCollapse: onCollapse) {
            VStack(alignment: .leading, spacing: 5) {
                Text(roundLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(song?.displayTitle ?? "No song played yet")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(credit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if isCompleted {
                    Label("Complete", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else {
                    HStack(spacing: 8) {
                        DeckButton(
                            title: shuffleIncludesPreviouslyPlayed ? "Shuffle replayable and remaining songs" : "Shuffle remaining unplayed songs",
                            systemImage: "shuffle",
                            prominence: .quiet,
                            action: onShuffle
                        )
                        .disabled(!canShuffle)
                        .padding(.trailing, 4)

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

                        DeckButton(title: "Song Details", systemImage: "info.circle", prominence: .quiet, action: onInspect)
                            .disabled(song == nil)
                            .padding(.leading, 6)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

// MARK: - Game deck

/// Deck shown during a live game. The transport drives *rounds*, not just
/// playback: Previous and Next Song move the game on and rescore every board.
/// Grows taller on a tap like the browsing deck, so the room can see the
/// artwork of the round being called from across the table.
struct GameDeck: View {
    var roundLabel: String
    var song: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    var isCompleted: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var canPlayPause: Bool
    var canShuffle: Bool
    var shuffleIncludesPreviouslyPlayed: Bool
    /// The trimmed window this round will play, resolved by the game screen —
    /// the deck has no model context of its own.
    var clip: DeckClip?

    var onPrevious: () -> Void
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onShuffle: () -> Void
    var onInspect: () -> Void

    /// Artist and album together — the host is reading these out loud, so the
    /// deck carries the same identifying detail the printed cards do.
    private var credit: String {
        guard let song else { return "Tap Next Song to reveal the first track" }
        let album = song.displayAlbum
        return album.isEmpty ? song.displayArtist : "\(song.displayArtist) · \(album)"
    }

    var body: some View {
        GrabbableDeck { collapse in
            GameDeckExpandedContent(
                roundLabel: roundLabel,
                song: song,
                credit: credit,
                isCompleted: isCompleted,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                isPlaying: audioPlayer.isPlaying,
                canPlayPause: canPlayPause,
                canShuffle: canShuffle,
                shuffleIncludesPreviouslyPlayed: shuffleIncludesPreviouslyPlayed,
                onPrevious: onPrevious,
                onPlayPause: onPlayPause,
                onNext: onNext,
                onShuffle: onShuffle,
                onInspect: onInspect,
                onCollapse: collapse
            )
        } row: { isExpanded, toggle in
            DeckRow(isExpanded: isExpanded) {
                transportRow(onTapIdentity: toggle)
            } scrubber: {
                DeckScrubber(audioPlayer: audioPlayer, clip: clip)
            }
        }
    }

    /// Tapping the identity grows the deck rather than opening the song sheet —
    /// the sheet is what the info button is for, here and in the browsing deck.
    private func transportRow(onTapIdentity: @escaping () -> Void) -> some View {
        PlayerDeck(
            eyebrow: roundLabel,
            eyebrowTint: isCompleted ? .secondary : .accentColor,
            artwork: song?.artworkData,
            title: song?.displayTitle ?? "No song played yet",
            subtitle: credit,
            progress: audioPlayer.progress,
            onTapIdentity: onTapIdentity
        ) {
            if isCompleted {
                Label("Complete", systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            } else {
                HStack(spacing: 4) {
                    DeckButton(
                        title: shuffleIncludesPreviouslyPlayed ? "Shuffle replayable and remaining songs" : "Shuffle remaining unplayed songs",
                        systemImage: "shuffle",
                        prominence: .quiet,
                        action: onShuffle
                    )
                    .disabled(!canShuffle)
                    .padding(.trailing, 6)

                    DeckButton(title: "Previous Round", systemImage: "backward.fill", action: onPrevious)
                        .disabled(!canGoBack)

                    DeckButton(
                        title: audioPlayer.isPlaying ? "Pause" : "Play",
                        systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill",
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
            DeckButton(title: "Song Details", systemImage: "info.circle", prominence: .quiet, action: onInspect)
                .disabled(song == nil)
        }
    }
}
