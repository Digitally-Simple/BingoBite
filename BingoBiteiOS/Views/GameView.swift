import SwiftUI
import SwiftData

enum GameTab: String, CaseIterable, Identifiable {
    case songs = "Play Order"
    case analytics = "Analytics"
    case boards = "Boards"
    case info = "Now Playing"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .songs: "list.number"
        case .analytics: "chart.xyaxis.line"
        case .boards: "square.grid.3x3.fill"
        case .info: "info.circle.fill"
        }
    }
}

/// The live game screen: a glass transport deck pinned to the bottom, with the
/// play order, scored boards, and current-song details above it.
struct GameView: View {
    @Environment(\.modelContext) private var modelContext
    var game: BingoGame
    @ObservedObject var audioPlayer: AudioPlayerService
    var onInspectSong: (Song) -> Void

    @State private var activeTab: GameTab = .songs
    @State private var songs: [Song] = []
    @State private var accessedURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEndConfirmation = false
    @State private var roundError: RoundError?
    @State private var shuffleIncludesPreviouslyPlayed = false
    /// Runs the game hands-free when the host arms it: each round's segment
    /// plays out, the gap passes, the next round starts. Lives with the game
    /// screen rather than the app, so leaving the screen ends the run.
    @StateObject private var autoplay = AutoplayEngine()

    /// A round whose song can't be played. Surfaced as a banner rather than a
    /// silent skip, because mid-game the host needs to know why nothing
    /// started and be able to move on immediately.
    struct RoundError: Identifiable {
        let id = UUID()
        let message: String
        let canReplace: Bool
    }
    /// Scoring every board is cheap but not free, so the count is recomputed
    /// when the game moves rather than on every re-render.
    @State private var bingoCount = 0
    /// Every saved trim, so the deck's playhead can name the round's in and out
    /// points — and pick up an edit made from the details sheet without waiting
    /// for the round to change.
    @Query private var soundBytes: [SoundByte]

    private var currentClip: DeckClip? { DeckClip.find(for: currentSong, in: soundBytes) }

    private var songLookup: SongIndex { SongIndex(songs) }

    private var currentSong: Song? {
        guard game.currentIndex >= 0, game.currentIndex < game.shuffledSongKeys.count else { return nil }
        return songLookup.song(for: game.shuffledSongKeys[game.currentIndex])
    }

    private var canGoBack: Bool { game.currentIndex >= 0 }
    private var canGoForward: Bool { game.currentIndex < game.shuffledSongKeys.count - 1 }

    private var shuffledBinding: Binding<[String]> {
        Binding(
            get: { game.shuffledSongKeys },
            set: { BingoGameService.updateShuffledOrder(game, newOrder: $0, in: modelContext) }
        )
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading songs…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Source Folder Unavailable", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(loadError)
                    Text("The playlist this game came from may have been deleted, or its folder moved in Files.")
                }
            } else {
                VStack(spacing: 0) {
                    ScoreboardBanner(
                        game: game,
                        song: currentSong,
                        isPlaying: audioPlayer.isPlaying,
                        bingoCount: bingoCount
                    )
                    if let roundError { roundErrorBanner(roundError) }
                    tabContent
                }
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        // Three separate groups rather than one item holding an HStack: the
        // shuffle lock, the tab picker, and End Game are unrelated controls, and
        // sharing a capsule made the picker read as a group nested inside a
        // group. The spacers are what break the shared background.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shuffleIncludesPreviouslyPlayed.toggle()
                } label: {
                    Image(systemName: shuffleIncludesPreviouslyPlayed ? "lock.open.fill" : "lock.fill")
                }
                .disabled(game.isCompleted)
                .accessibilityLabel(shuffleIncludesPreviouslyPlayed ? "Unlock shuffle protection" : "Lock shuffle protection")
                .help(shuffleIncludesPreviouslyPlayed ? "Unlocked: replayed rounds can shuffle" : "Locked: preserve played rounds")
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleAutoplay) {
                    HStack(spacing: 5) {
                        Image(systemName: autoplay.isEnabled ? "play.square.stack.fill" : "play.square.stack")
                        // The countdown sits in the control itself: a host
                        // glancing up mid-round wants to know how long they
                        // have before the room hears the next song.
                        if let seconds = autoplay.displayedSecondsRemaining {
                            Text("\(seconds)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .tint(autoplay.isEnabled ? Color.accentColor : nil)
                .disabled(game.isCompleted)
                .accessibilityLabel(autoplay.isEnabled ? "Turn autoplay off" : "Turn autoplay on")
                .help(autoplayHelp)
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Plain buttons rather than a segmented picker: the picker drew its
            // own track and selection pill *inside* the toolbar's glass, which
            // read as a group nested in a group next to the round buttons
            // either side of it. A group of buttons gets one shared capsule —
            // the same chrome as everything else on this bar — and the tint is
            // what says which view is showing.
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(GameTab.allCases) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .labelStyle(.iconOnly)
                            .fontWeight(activeTab == tab ? .semibold : .regular)
                    }
                    // Tint, not `foregroundStyle` — a toolbar button styles its
                    // own label, and only the tint survives.
                    .tint(activeTab == tab ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(activeTab == tab ? [.isSelected] : [])
                }
            }

            if !game.isCompleted {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button("End Game", systemImage: "flag.checkered", role: .destructive) {
                        showEndConfirmation = true
                    }
                }
            }
        }
        .modifier(
            DeckOverlay(isVisible: !isLoading && loadError == nil) {
                gameDeck
            }
        )
        .task(id: game.playlistUUID) { await loadSongs() }
        .onAppear { updateSkipHandlers() }
        .onAppear { BingoGameService.recordCurrentProgress(game, in: modelContext) }
        .onDisappear {
            autoplay.isEnabled = false
            audioPlayer.clearPlaybackHandlers()
            BingoLiveActivityCommandBus.shared.setHandler(nil)
            BingoLiveActivityController.stop()
            releaseAccess()
        }
        .onChange(of: game.currentIndex) {
            updateSkipHandlers()
            syncLiveActivity()
        }
        .onChange(of: audioPlayer.isPlaying) { syncLiveActivity() }
        .onChange(of: game.isCompleted) {
            if game.isCompleted {
                let state = liveActivityState
                bingoCount = state.bingoCount
                BingoLiveActivityController.finish(state: state)
            }
        }
        .confirmationDialog("End this game?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Game", role: .destructive) { endGame() }
        } message: {
            Text("The final boards stay available, but you won't be able to play more songs.")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .songs:
            GamePlayOrderView(
                shuffledSongs: shuffledBinding,
                currentIndex: game.currentIndex,
                protectedThroughIndex: shuffleIncludesPreviouslyPlayed ? game.currentIndex : max(game.currentIndex, game.highestPlayedIndex),
                songLookup: songLookup,
                isCompleted: game.isCompleted
            )
        case .analytics:
            GameAnalyticsView(game: game)
        case .boards:
            GameBoardsView(game: game, songLookup: songLookup)
        case .info:
            SongDetailPanel(song: currentSong, audioPlayer: audioPlayer, emptyMessage: "Press Next Song to start the game.")
        }
    }

    // MARK: - Transport deck

    private var gameDeck: some View {
        GameDeck(
            roundLabel: roundLabel,
            song: currentSong,
            audioPlayer: audioPlayer,
            isCompleted: game.isCompleted,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            canPlayPause: game.currentIndex >= 0,
            canShuffle: canShuffle,
            shuffleIncludesPreviouslyPlayed: shuffleIncludesPreviouslyPlayed,
            clip: currentClip,
            onPrevious: previousSong,
            onPlayPause: playPause,
            onNext: nextSong,
            onShuffle: shuffleRemainingSongs,
            onInspect: { if let currentSong { onInspectSong(currentSong) } }
        )
    }

    private var roundLabel: String {
        if game.isCompleted { return "Completed" }
        // During a gap the deck says what's about to happen rather than what
        // just did — it's the only thing on screen that's moving.
        if let seconds = autoplay.displayedSecondsRemaining {
            return "Next song in \(seconds)s"
        }
        if game.currentIndex < 0 { return "Ready" }
        return "Round \(game.currentIndex + 1) of \(game.shuffledSongKeys.count)"
    }

    private var autoplayHelp: String {
        if let seconds = autoplay.displayedSecondsRemaining {
            return "Autoplay on — next song in \(seconds)s"
        }
        return autoplay.isEnabled
            ? "Autoplay on — the next song starts on its own"
            : "Autoplay off — you're calling each round"
    }

    // MARK: - Loading

    @MainActor
    private func loadSongs() async {
        isLoading = true
        loadError = nil
        releaseAccess()

        let uuid = game.playlistUUID
        guard !uuid.isEmpty else {
            loadError = "This game has no source playlist."
            isLoading = false
            return
        }

        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == uuid })
        guard let playlist = try? modelContext.fetch(descriptor).first else {
            loadError = "Source playlist not found."
            isLoading = false
            return
        }

        do {
            let (loaded, _, _, url) = try await PlaylistService.loadSongs(for: playlist, in: modelContext)
            songs = loaded
            accessedURL = url
            applyOverrides()
        } catch {
            loadError = error.localizedDescription
            songs = []
        }
        isLoading = false
        if loadError == nil {
            updateSkipHandlers()
            syncLiveActivity()
        }
    }

    private func applyOverrides() {
        let overrides = SongMetadataService.fetchAll(in: modelContext)
        for index in songs.indices {
            if let override = overrides[songs[index].stableKey] {
                songs[index] = songs[index].applying(override: override)
            }
        }
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }

    // MARK: - Playback

    private func playPause() {
        // Reaching for the transport during a gap means the host wants the
        // wheel back for a moment; autoplay stays armed for the round after.
        autoplay.cancelPending()
        if audioPlayer.currentSong != nil {
            audioPlayer.togglePlayPause()
        } else {
            playCurrentIndex()
        }
    }

    private func nextSong() {
        BingoGameService.advanceToNextSong(game, in: modelContext)
        playCurrentIndex()
    }

    private func previousSong() {
        BingoGameService.goToPreviousSong(game, in: modelContext)
        if game.currentIndex >= 0 {
            playCurrentIndex()
        } else {
            autoplay.roundStarted()
            audioPlayer.fadeOutAndStop {}
        }
    }

    /// Arming autoplay starts the show when nothing is going on and stays out
    /// of the way when something is — it never cuts a song already playing.
    private func toggleAutoplay() {
        autoplay.isEnabled.toggle()
        guard autoplay.isEnabled, !audioPlayer.isPlaying else { return }

        if audioPlayer.currentSong == nil {
            // Nothing loaded: either the game hasn't started or the screen was
            // just reopened on a round that never played.
            if game.currentIndex < 0 {
                nextSong()
            } else {
                playCurrentIndex()
            }
        } else if autoplay.isAwaitingAdvance {
            // The round finished while autoplay was off. Pick up from there
            // rather than making the host press Next once to get going.
            autoplay.scheduleAdvance(after: AppSettingsService.autoplayGap(in: modelContext))
        }
    }

    private var canShuffle: Bool {
        guard !game.isCompleted else { return false }
        let protectedIndex = shuffleIncludesPreviouslyPlayed
            ? game.currentIndex
            : max(game.currentIndex, game.highestPlayedIndex)
        return protectedIndex + 1 < game.shuffledSongKeys.count
    }

    private func shuffleRemainingSongs() {
        BingoGameService.reshuffleRemainingSongs(
            game,
            includePreviouslyPlayed: shuffleIncludesPreviouslyPlayed,
            in: modelContext
        )
        updateSkipHandlers()
        syncLiveActivity()
    }

    /// Shown in place of silently skipping a round whose song won't play.
    private func roundErrorBanner(_ error: RoundError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            if canGoForward {
                Button("Skip Round") { nextSong() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            Button("Dismiss") { roundError = nil }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }

    /// Starts the current round, riding whatever is playing down first so a
    /// press of Next sounds like the fade the host configured rather than a
    /// cut. Nothing playing means the handoff runs straight through.
    private func playCurrentIndex() {
        guard game.currentIndex >= 0, game.currentIndex < game.shuffledSongKeys.count else { return }
        autoplay.roundStarted()
        audioPlayer.fadeOutAndStop { startCurrentRound() }
    }

    /// The round the game is on *now* — read at the moment the handoff lands,
    /// not when it was scheduled, so a double press ends up on the right song.
    private func startCurrentRound() {
        let index = game.currentIndex
        guard index >= 0, index < game.shuffledSongKeys.count else { return }
        roundError = nil

        let key = game.shuffledSongKeys[index]

        // A missing song used to be a silent no-op that still advanced the
        // round — the host would be left staring at a deck that never started,
        // mid-game, with no idea which track was gone.
        guard let song = songLookup.song(for: key) else {
            roundError = RoundError(
                message: "This round's song is missing: \(SongIndex.fileName(from: key) ?? "unknown file")",
                canReplace: true
            )
            audioPlayer.stop()
            return
        }

        let clip = Self.clipWindow(for: song, in: modelContext)
        if !audioPlayer.play(song, clipStart: clip.start, clipEnd: clip.end) {
            roundError = RoundError(
                message: "Couldn't play “\(song.displayTitle)”. The file may be damaged.",
                canReplace: true
            )
        }
    }

    /// The window of a song a round plays.
    ///
    /// A trim can be half-set: a start with no end plays from there to the end
    /// of the file, an end with no start plays from the beginning to there. An
    /// unset handle is stored as `0`, which is also a legitimate start time —
    /// hence only the *end* needs the zero check.
    ///
    /// Static so the escaping handlers can reach it without holding on to a
    /// snapshot of the view.
    private static func clipWindow(
        for song: Song,
        in context: ModelContext
    ) -> (start: TimeInterval, end: TimeInterval?) {
        guard let byte = SoundByteService.fetch(for: song, in: context) else { return (0, nil) }
        return (max(byte.startTime, 0), byte.endTime > 0 ? byte.endTime : nil)
    }

    private func endGame() {
        autoplay.isEnabled = false
        audioPlayer.stop()
        audioPlayer.clearPlaybackHandlers()
        BingoGameService.endGame(game, in: modelContext)
    }

    /// Wires everything that moves the game without a tap on this screen: the
    /// lock-screen / Control Center skip buttons, the Live Activity's buttons,
    /// and autoplay's end-of-segment handoff.
    ///
    /// All of it is closures held by objects that outlive the view, so they
    /// capture references — the game, the player, the engine — and read the
    /// round off them when they fire rather than closing over a stale index.
    private func updateSkipHandlers() {
        guard !game.isCompleted else {
            autoplay.isEnabled = false
            audioPlayer.clearPlaybackHandlers()
            BingoLiveActivityCommandBus.shared.setHandler(nil)
            return
        }

        let game = game
        let player = audioPlayer
        let context = modelContext
        let lookup = songLookup
        let engine = autoplay

        func play(at index: Int) {
            guard index >= 0, index < game.shuffledSongKeys.count else { return }
            guard let song = lookup.song(for: game.shuffledSongKeys[index]) else { return }
            let clip = Self.clipWindow(for: song, in: context)
            engine.roundStarted()
            player.fadeOutAndStop {
                player.play(song, clipStart: clip.start, clipEnd: clip.end)
            }
        }

        /// Pushes the current state back to the Lock Screen card. SwiftUI's
        /// `onChange` can't be relied on while the app is backgrounded, which
        /// is exactly when these handlers run.
        func syncCard() {
            let index = game.currentIndex
            let song = (index >= 0 && index < game.shuffledSongKeys.count)
                ? lookup.song(for: game.shuffledSongKeys[index])
                : nil
            BingoLiveActivityController.sync(
                game: game,
                state: BingoLiveActivityState.make(game: game, song: song, isPlaying: player.isPlaying)
            )
        }

        player.onSkipForward = canGoForward ? {
            BingoGameService.advanceToNextSong(game, in: context)
            play(at: game.currentIndex)
        } : nil

        player.onSkipBackward = canGoBack ? {
            BingoGameService.goToPreviousSong(game, in: context)
            if game.currentIndex >= 0 {
                play(at: game.currentIndex)
            } else {
                engine.roundStarted()
                player.stop()
            }
        } : nil

        // The round's segment reached its out point on its own. Whether that
        // starts a gap or just sits there is autoplay's call.
        player.onClipFinished = {
            guard !game.isCompleted else { return }
            engine.segmentFinished(
                gap: AppSettingsService.autoplayGap(in: context),
                canAdvance: game.currentIndex < game.shuffledSongKeys.count - 1
            )
        }

        engine.onAdvance = {
            guard !game.isCompleted else { return }
            BingoGameService.advanceToNextSong(game, in: context)
            play(at: game.currentIndex)
            syncCard()
        }

        player.setSkipState(canForward: canGoForward, canBackward: canGoBack)

        // The Lock Screen buttons ride the same handlers, so a press from the
        // Live Activity moves the game exactly as the deck does.
        BingoLiveActivityCommandBus.shared.setHandler { command in
            switch command {
            case .nextRound:
                player.skipForward()
            case .previousRound:
                player.skipBackward()
            case .togglePlayback:
                engine.cancelPending()
                if player.currentSong != nil {
                    player.togglePlayPause()
                } else {
                    player.skipForward()
                }
            }
            syncCard()
        }
    }

    // MARK: - Live Activity

    private var liveActivityState: BingoGameActivityAttributes.ContentState {
        BingoLiveActivityState.make(game: game, song: currentSong, isPlaying: audioPlayer.isPlaying)
    }

    /// One pass over the boards feeds both the on-screen scoreboard and the
    /// Lock Screen card — they're showing the same numbers, so they should be
    /// computed together.
    private func syncLiveActivity() {
        let state = liveActivityState
        bingoCount = state.bingoCount
        guard !isLoading, loadError == nil, !game.isCompleted else { return }
        BingoLiveActivityController.sync(game: game, state: state)
    }
}
