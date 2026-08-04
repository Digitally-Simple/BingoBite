import SwiftUI
import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var isPreviewing = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var canSkipForward = false
    @Published var canSkipBackward = false
    /// Set when a file couldn't be opened. Views surface this instead of the
    /// transport deck sitting there showing a song that never starts.
    @Published var playbackError: String?

    var onSkipForward: (() -> Void)?
    var onSkipBackward: (() -> Void)?

    /// Called when the playing segment reaches its own end — the trim's out
    /// point, or the end of the file when there isn't one.
    ///
    /// Deliberately not called for a stop, a pause, a song replaced by another,
    /// or a sound byte preview. It exists so a game screen can move to the next
    /// round on its own, and none of those are a round finishing.
    var onClipFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    /// The window of the file being played, in absolute file time.
    /// `clipEndTime` is nil when playback runs to the file's own end.
    ///
    /// The fade envelope is measured against this window rather than the whole
    /// file, so a trimmed round fades in at its in point and is already at
    /// silence by its out point.
    private var clipStartTime: TimeInterval = 0
    private var clipEndTime: TimeInterval?
    private var fadeTimer: Timer?
    private var meterTimer: Timer?
    private var manualFade: ManualFade?

    /// Volume shape applied while playing. Set from settings by whoever owns
    /// this player; defaults to no fade so playback works before it's wired.
    var fadeEnvelope: FadeEnvelope = .none {
        didSet {
            guard oldValue != fadeEnvelope else { return }
            if isPlaying { startFadeTimer() } else { applyCurrentVolume() }
        }
    }

    /// Where the host has the fader, 0...1. The envelope rides *underneath* it,
    /// so what the room hears is this times the envelope's gain — pulling the
    /// level down mid-round doesn't flatten the fades, it scales them.
    /// Clamped where it's used rather than in `didSet` — assigning to the
    /// property from inside its own observer re-enters the observer, and the
    /// recursion only ends when the stack does.
    @Published var masterVolume: Double = 1 {
        didSet {
            guard manualFade == nil else { return }
            applyCurrentVolume()
        }
    }

    /// The fader, guaranteed to be in range whatever a caller stored.
    private var clampedMasterVolume: Double { min(max(masterVolume, 0), 1) }

    /// The live level, on its own publisher so a fade doesn't redraw the room.
    /// See `AudioLevelMeter`.
    let levels = AudioLevelMeter()

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String {
        Self.format(time: currentTime)
    }

    var formattedDuration: String {
        Self.format(time: duration)
    }

    init() {
        configureAudioSession()
        setupRemoteCommandCenter()
    }

    /// iOS needs an explicit playback session so audio keeps going with the
    /// screen locked or the app backgrounded (the iPad is the game host).
    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AudioPlayerService: audio session setup failed - \(error.localizedDescription)")
        }
        #endif
    }

    /// Starts playback, optionally confined to a trimmed window of the file.
    ///
    /// A song with only a start time plays from there to the end; one with only
    /// an end time plays from the beginning to there; one with both plays just
    /// that segment. Either way the fade envelope is measured against the
    /// segment, so what the room hears is the clip the host trimmed, faded in
    /// and out at its own edges.
    ///
    /// Returns false when the file couldn't be opened — it was deleted, is
    /// damaged, or is in a format this platform can't decode.
    ///
    /// `@discardableResult` so existing call sites are unaffected, but callers
    /// that can show the user something should check it. Failing silently here
    /// is how a missing file used to look identical to a song that just doesn't
    /// start.
    @discardableResult
    func play(_ song: Song, clipStart: TimeInterval = 0, clipEnd: TimeInterval? = nil) -> Bool {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: song.id)
            player.prepareToPlay()

            let start = min(max(clipStart, 0), max(player.duration - Self.minimumClipDuration, 0))
            let end = Self.resolvedClipEnd(clipEnd, start: start, fileDuration: player.duration)

            player.currentTime = start
            self.player = player
            self.currentSong = song
            self.duration = player.duration
            self.currentTime = start
            self.clipStartTime = start
            self.clipEndTime = end
            // Volume has to be set before the first sample, or a fade-in
            // starts at full level for the frames before the ticker catches it.
            applyCurrentVolume()
            player.play()
            self.isPlaying = true
            self.playbackError = nil
            startTimer()
            updateNowPlayingInfo()
            updatePlaybackState()
            return true
        } catch {
            playbackError = "Couldn't play \(song.displayTitle). \(error.localizedDescription)"
            return false
        }
    }

    /// Shortest window worth treating as a clip. Below this a trim is a
    /// rounding error, not a segment, and playing it would be a click.
    private static let minimumClipDuration: TimeInterval = 0.25

    /// A trim's out point, ignored when it doesn't leave a clip worth playing —
    /// including the common "no end set" case stored as `0`.
    private static func resolvedClipEnd(
        _ end: TimeInterval?,
        start: TimeInterval,
        fileDuration: TimeInterval
    ) -> TimeInterval? {
        guard let end else { return nil }
        let capped = min(end, fileDuration)
        guard capped - start >= minimumClipDuration else { return nil }
        return capped
    }

    func togglePlayPause() {
        // A handoff in flight already owns what plays next — the round has
        // moved on even though the old song is still fading. Landing it first
        // means play/pause acts on the song the screen is naming, rather than
        // on one that's two seconds from gone.
        finishManualFade()

        guard let player else { return }
        isPreviewing = false
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
        updatePlaybackState()
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let target = fraction * player.duration
        player.currentTime = target
        currentTime = target
        updateNowPlayingElapsedTime()
    }

    func preview(_ song: Song, startTime: TimeInterval, endTime: TimeInterval) {
        if currentSong != song {
            stop()
            do {
                let player = try AVAudioPlayer(contentsOf: song.id)
                player.prepareToPlay()
                self.player = player
                self.currentSong = song
                self.duration = player.duration
            } catch {
                playbackError = "Couldn't load \(song.displayTitle). \(error.localizedDescription)"
                return
            }
        }
        guard let player else { return }
        cancelManualFade()
        player.currentTime = startTime
        currentTime = startTime
        clipStartTime = startTime
        clipEndTime = Self.resolvedClipEnd(endTime, start: startTime, fileDuration: player.duration)
        isPreviewing = true
        applyCurrentVolume()
        player.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
        updatePlaybackState()
    }

    func stop() {
        manualFade = nil
        stopTimer()
        player?.stop()
        player = nil
        currentSong = nil
        isPlaying = false
        isPreviewing = false
        clipStartTime = 0
        clipEndTime = nil
        currentTime = 0
        duration = 0
        // Nothing is coming out, so the needles drop rather than holding the
        // last sample they saw.
        levels.silence()
        clearNowPlayingInfo()
    }

    // MARK: - Segment timing

    /// Everything a deck needs to narrate the segment being played: where it
    /// starts and ends inside the file, where the fades land, and how far in
    /// the playhead is.
    ///
    /// The fade lengths here are the *resolved* ones — on a clip too short for
    /// both, they're the scaled-down values actually being played, not what
    /// the settings ask for.
    struct SegmentTiming: Equatable {
        /// Absolute times in the file.
        var start: TimeInterval
        var end: TimeInterval
        var fadeIn: TimeInterval
        var fadeOut: TimeInterval
        /// Seconds into the segment, clamped to it.
        var elapsed: TimeInterval

        var duration: TimeInterval { max(end - start, 0) }
        var remaining: TimeInterval { max(duration - elapsed, 0) }

        /// Absolute times, for labelling against the file's own clock.
        var fadeInEndsAt: TimeInterval { start + fadeIn }
        var fadeOutStartsAt: TimeInterval { end - fadeOut }

        /// Seconds until the fade-out begins, nil once it has.
        var untilFadeOut: TimeInterval? {
            guard fadeOut > 0 else { return nil }
            let left = duration - fadeOut - elapsed
            return left > 0 ? left : nil
        }

        var isFadingIn: Bool { fadeIn > 0 && elapsed < fadeIn }
        var isFadingOut: Bool { fadeOut > 0 && remaining <= fadeOut && duration > 0 }

        /// Where the playhead sits across the segment, 0...1.
        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(elapsed / duration, 0), 1)
        }
    }

    /// The segment currently loaded, or nil when nothing is.
    var segmentTiming: SegmentTiming? {
        guard let player, currentSong != nil else { return nil }
        let end = clipEndTime ?? player.duration
        let duration = end - clipStartTime
        guard duration > 0 else { return nil }
        let (fadeIn, fadeOut) = fadeEnvelope.resolvedDurations(clipDuration: duration)
        return SegmentTiming(
            start: clipStartTime,
            end: end,
            fadeIn: fadeIn,
            fadeOut: fadeOut,
            elapsed: min(max(currentTime - clipStartTime, 0), duration)
        )
    }

    @discardableResult
    func play(_ song: Song, from startTime: TimeInterval) -> Bool {
        play(song, clipStart: startTime)
    }

    /// Rides the current song down to silence, then runs `completion`.
    ///
    /// This is what a manual Next or Previous goes through, so moving rounds by
    /// hand sounds like the fades the host configured rather than a cut. The
    /// ride is capped well below the longest fade the settings allow: someone
    /// who just pressed Next has a room waiting on them, and a fifteen-second
    /// exit is not an answer to a button press.
    ///
    /// Pressing again while a ride is in flight replaces the pending handoff
    /// rather than stacking a second fade on top, so a double press lands on
    /// the round the host actually stopped on.
    func fadeOutAndStop(then completion: @escaping () -> Void) {
        if manualFade != nil {
            manualFade?.completion = completion
            return
        }

        let rideDuration = min(fadeEnvelope.fadeOutDuration, Self.manualAdvanceFadeCap)
        guard let player, isPlaying, rideDuration > 0 else {
            stop()
            completion()
            return
        }

        // The envelope ticker and the ride would fight over the same volume,
        // so the ride takes the wheel until it's done.
        stopFadeTimer()
        manualFade = ManualFade(
            curve: fadeEnvelope.fadeOutCurve,
            duration: rideDuration,
            startVolume: player.volume,
            startedAt: Date(),
            completion: completion
        )
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.fadeTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickManualFade()
            }
        }
    }

    func skipForward() {
        onSkipForward?()
    }

    func skipBackward() {
        onSkipBackward?()
    }

    func setSkipState(canForward: Bool, canBackward: Bool) {
        canSkipForward = canForward
        canSkipBackward = canBackward
        updateRemoteSkipCommands()
    }

    /// Hands the transport back. Called by whichever screen wired itself up as
    /// it goes away, so a game's round handling doesn't outlive the game screen.
    func clearPlaybackHandlers() {
        onSkipForward = nil
        onSkipBackward = nil
        onClipFinished = nil
        canSkipForward = false
        canSkipBackward = false
        updateRemoteSkipCommands()
    }

    // MARK: - Now Playing / Remote Commands

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player != nil, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player != nil else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                let fraction = positionEvent.positionTime / player.duration
                self.seek(to: fraction)
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipForward()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipBackward()
            }
            return .success
        }

        updateRemoteSkipCommands()
    }

    private func updateRemoteSkipCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = canSkipForward
        commandCenter.previousTrackCommand.isEnabled = canSkipBackward
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artist = song.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artworkData = song.artworkData, let image = PlatformImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState() {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateNowPlayingElapsedTime()
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateTime()
            }
        }
        startFadeTimer()
        startMeterTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        stopFadeTimer()
        stopMeterTimer()
        levels.silence()
    }

    // MARK: - Fade envelope

    /// Fades run on their own ticker rather than the 0.25s progress timer —
    /// at that rate a fade would arrive in four audible steps per second.
    /// Setting `player.volume` is cheap, so 60Hz costs nothing meaningful, and
    /// the ticker only exists while something is playing.
    private static let fadeTickInterval: TimeInterval = 1.0 / 60.0

    /// Longest ride down a manual Next or Previous will sit through, however
    /// long the configured fade-out is.
    private static let manualAdvanceFadeCap: TimeInterval = 2.0

    /// A one-shot ride to silence, for a handoff the host asked for. Separate
    /// from the envelope because it starts from wherever the volume happens to
    /// be — mid-fade-in, mid-fade-out, or flat — rather than from the clip.
    private struct ManualFade {
        let curve: FadeCurve
        let duration: TimeInterval
        let startVolume: Float
        let startedAt: Date
        var completion: () -> Void
    }

    private func tickManualFade() {
        guard let fade = manualFade, player != nil else { return }
        let progress = min(Date().timeIntervalSince(fade.startedAt) / fade.duration, 1)
        setOutput(level: Double(fade.startVolume) * fade.curve.fallingGain(at: progress))
        guard progress >= 1 else { return }
        finishManualFade()
    }

    /// Lands a handoff: the old song goes, and whoever asked for the ride gets
    /// to start what comes next. Called by the ticker when the ride runs out,
    /// and directly by anything that needs the handoff over with now.
    private func finishManualFade() {
        guard let fade = manualFade else { return }
        // Cleared before `stop()` so the stop doesn't cancel the very handoff
        // it's part of.
        manualFade = nil
        stopFadeTimer()
        stop()
        fade.completion()
    }

    /// Drops a handoff in flight without running it — something else (a pause,
    /// a new song, a stop) is taking over, and the volume goes back to whatever
    /// the envelope says it should be.
    private func cancelManualFade() {
        guard manualFade != nil else { return }
        manualFade = nil
        stopFadeTimer()
        if isPlaying {
            startFadeTimer()
        } else {
            applyCurrentVolume()
        }
    }

    // MARK: - Level

    /// The envelope's gain at the playhead right now, 1 when no fade applies.
    private var envelopeGainNow: Double {
        guard let player, fadeEnvelope.isActive else { return 1 }
        let clipEnd = clipEndTime ?? player.duration
        let clipDuration = clipEnd - clipStartTime
        guard clipDuration > 0 else { return 1 }
        return fadeEnvelope.gain(
            atElapsed: player.currentTime - clipStartTime,
            clipDuration: clipDuration
        )
    }

    private func applyCurrentVolume() {
        setOutput(level: clampedMasterVolume * envelopeGainNow)
    }

    /// The one place `player.volume` is written, so the meter can never
    /// disagree with what's actually coming out.
    private func setOutput(level: Double) {
        let level = min(max(level, 0), 1)
        currentOutputGain = level
        player?.volume = Float(level)
    }

    /// The gain last written to the player, kept so the signal meter can scale
    /// by it. `AVAudioPlayer`'s metering reads the decoded audio, which doesn't
    /// know the volume property exists — without this the bar would sit at full
    /// height through a fade-out the room can hear disappearing.
    private var currentOutputGain: Double = 1

    // MARK: - Signal metering

    /// Fast enough to look alive, slow enough that a phone-sized view isn't
    /// redrawing on every display frame for a bar a few points wide.
    private static let meterTickInterval: TimeInterval = 1.0 / 24.0

    private func startMeterTimer() {
        stopMeterTimer()
        player?.isMeteringEnabled = true
        meterTimer = Timer.scheduledTimer(withTimeInterval: Self.meterTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickMeter()
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tickMeter() {
        guard let player, player.isPlaying else {
            levels.silence()
            return
        }
        player.updateMeters()
        // A mono file has one channel and drives both bars from it, rather
        // than showing a dead right-hand side.
        let leftDB = Double(player.averagePower(forChannel: 0))
        let rightDB = player.numberOfChannels > 1
            ? Double(player.averagePower(forChannel: 1))
            : leftDB
        levels.feed(leftDecibels: leftDB, rightDecibels: rightDB, gain: currentOutputGain)
    }

    private func startFadeTimer() {
        guard fadeEnvelope.isActive else {
            applyCurrentVolume()
            return
        }
        stopFadeTimer()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.fadeTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyFadeEnvelope()
            }
        }
        applyFadeEnvelope()
    }

    private func stopFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    /// Rides the volume to match the envelope at the current playhead.
    private func applyFadeEnvelope() {
        guard player != nil, fadeEnvelope.isActive, manualFade == nil else { return }
        applyCurrentVolume()
    }

    private func updateTime() {
        guard let player else { return }
        currentTime = player.currentTime

        // A handoff is riding the volume down. What happens at the end of this
        // song has already been decided, so don't decide it again here.
        guard manualFade == nil else { return }

        if let clipEndTime, currentTime >= clipEndTime {
            finishSegment(atTrimPoint: true)
            return
        }
        if !player.isPlaying && isPlaying {
            // Playback ended naturally
            finishSegment(atTrimPoint: false)
        }
    }

    /// The segment played itself out. The song stays loaded rather than being
    /// torn down, so the deck keeps showing whatever was just called.
    private func finishSegment(atTrimPoint: Bool) {
        let wasPreviewing = isPreviewing
        player?.pause()
        isPlaying = false
        isPreviewing = false
        // Reaching a trim's out point leaves the playhead there; running off
        // the end of the file rewinds, as it always has.
        if !atTrimPoint { currentTime = 0 }
        stopTimer()
        updatePlaybackState()
        // A preview isn't a round, so it never moves a game along.
        if !wasPreviewing { onClipFinished?() }
    }

    private static func format(time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
