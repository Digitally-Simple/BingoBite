import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var isPreviewing = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

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
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let target = fraction * player.duration
        player.currentTime = target
        currentTime = target
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
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
            return
        }
        if !player.isPlaying && isPlaying {
            // Playback ended naturally
            isPlaying = false
            currentTime = 0
            stopTimer()
        }
    }

    private static func format(time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
