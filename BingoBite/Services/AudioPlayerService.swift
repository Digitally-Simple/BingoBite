import AppKit
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

    var onSkipForward: (() -> Void)?
    var onSkipBackward: (() -> Void)?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var previewEndTime: TimeInterval = 0

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
        setupRemoteCommandCenter()
    }

    func play(_ song: Song) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: song.id)
            player.prepareToPlay()
            player.play()
            self.player = player
            self.currentSong = song
            self.duration = player.duration
            self.currentTime = 0
            self.isPlaying = true
            startTimer()
            updateNowPlayingInfo()
            updatePlaybackState()
        } catch {
            print("AudioPlayerService: failed to play \(song.fileName) — \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
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
                print("AudioPlayerService: failed to load \(song.fileName) — \(error.localizedDescription)")
                return
            }
        }
        guard let player else { return }
        player.currentTime = startTime
        currentTime = startTime
        previewEndTime = endTime
        isPreviewing = true
        player.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
        updatePlaybackState()
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        currentSong = nil
        isPlaying = false
        isPreviewing = false
        previewEndTime = 0
        currentTime = 0
        duration = 0
        clearNowPlayingInfo()
    }

    func play(_ song: Song, from startTime: TimeInterval) {
        play(song)
        guard startTime > 0, startTime < duration else { return }
        seek(to: startTime / duration)
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

    func clearSkipHandlers() {
        onSkipForward = nil
        onSkipBackward = nil
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
        if let artworkData = song.artworkData, let image = NSImage(data: artworkData) {
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
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTime() {
        guard let player else { return }
        currentTime = player.currentTime
        if isPreviewing && currentTime >= previewEndTime {
            player.pause()
            isPlaying = false
            isPreviewing = false
            previewEndTime = 0
            stopTimer()
            updatePlaybackState()
            return
        }
        if !player.isPlaying && isPlaying {
            // Playback ended naturally
            isPlaying = false
            currentTime = 0
            stopTimer()
            updatePlaybackState()
        }
    }

    private static func format(time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
