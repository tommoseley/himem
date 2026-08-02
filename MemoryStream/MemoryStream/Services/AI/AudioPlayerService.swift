import Foundation
import AVFoundation

@MainActor
final class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published var isPlaying = false
    @Published var currentFile: String?

    private var player: AVAudioPlayer?
    /// Tracks whether we activated the shared AVAudioSession in
    /// `play()`. We only `setActive(false)` in `stop()` when this is
    /// true, to avoid the HAL churn warned about in CLAUDE.md's
    /// "Audio Session Coordination" rule ("Calling `setActive(false)`
    /// on an already-inactive session can churn the audio HAL").
    private var sessionActivated = false

    /// Exposes the underlying player so views needing live playback time
    /// (e.g. AudioPlayerSheet's scrub bar) can poll `currentTime`. Read-only
    /// reference — control surface remains `play(filename:)` / `stop()`.
    var currentAVPlayer: AVAudioPlayer? { player }

    /// Plays a clip from the **memory store** (`Documents/VoiceEntries`).
    func play(filename: String) {
        play(url: SpeechService.audioURL(for: filename), label: filename)
    }

    /// Plays a clip from an explicit URL — the entry point for audio that does
    /// not live in the memory store, notably a bench clip staged in the inbox
    /// (`InboxManifest.audioURL(for:)`).
    ///
    /// This exists because `SessionListView` used to hand-roll its own
    /// `AVAudioPlayer` purely to reach the other store, and that copy omitted
    /// the `AVAudioPlayerDelegate` — so a bench clip played to its natural end
    /// never deactivated the `.playback` session (F23 T2.3; verbatim the bug
    /// the `play(filename:)` path documents having already fixed). One owner,
    /// two stores.
    ///
    /// - Parameter label: what `currentFile` reports while this plays. Callers
    ///   pass the clip's filename so a view can derive "is this row playing?"
    ///   from the service rather than keeping its own copy of the answer.
    func play(url: URL, label: String) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Audio file not found: \(url.path)")
            return
        }
        let filename = label

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActivated = true

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = PlaybackDelegate.shared
            player?.play()
            isPlaying = true
            currentFile = filename

            // Natural end-of-playback routes through stop() so the
            // session deactivates symmetrically with how it activated.
            // Previously this set isPlaying = false directly and left
            // the session in `.playback` active forever, which on a
            // plugged-in iPhone made the device feel like it was
            // refusing to sleep.
            PlaybackDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.stop()
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
        if sessionActivated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
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
