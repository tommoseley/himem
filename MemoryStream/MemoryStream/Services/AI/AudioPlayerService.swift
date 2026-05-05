import Foundation
import AVFoundation

@MainActor
final class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published var isPlaying = false
    @Published var currentFile: String?

    private var player: AVAudioPlayer?

    /// Exposes the underlying player so views needing live playback time
    /// (e.g. AudioPlayerSheet's scrub bar) can poll `currentTime`. Read-only
    /// reference — control surface remains `play(filename:)` / `stop()`.
    var currentAVPlayer: AVAudioPlayer? { player }

    func play(filename: String) {
        stop()

        let url = SpeechService.audioURL(for: filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Audio file not found: \(url.path)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = PlaybackDelegate.shared
            player?.play()
            isPlaying = true
            currentFile = filename

            PlaybackDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.currentFile = nil
                }
            }
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentFile = nil
    }

    static func deleteAudio(filename: String) {
        let url = SpeechService.audioURL(for: filename)
        try? FileManager.default.removeItem(at: url)
    }
}

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = PlaybackDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
