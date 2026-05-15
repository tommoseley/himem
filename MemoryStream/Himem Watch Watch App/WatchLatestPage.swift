import SwiftUI
import AVFoundation
import Combine

/// Watch — Pages model, left page. Shows the newest pending clip with
/// inline playback: duration + date label, a waveform, time markers,
/// and a tappable play button. Read-only — no edits, no swipe-to-delete
/// (the Pending page owns mutation). Falls back to an empty-state
/// placeholder when nothing is pending.
///
/// We deliberately read from `WatchPendingManifest.shared.clips.first`
/// rather than fetching the catalog from the iPhone: there's no
/// "latest memory" plumbing across WCSession yet, but a clip the user
/// just recorded is right here on the watch. Once iPhone-to-watch
/// catalog sync lands, swap the data source.
struct WatchLatestPage: View {
    @ObservedObject private var pending = WatchPendingManifest.shared
    @StateObject private var playback = LatestPlaybackService()

    var body: some View {
        if let clip = pending.clips.first {
            playbackView(for: clip)
        } else {
            emptyState
        }
    }

    // MARK: - Playback view

    private func playbackView(for clip: WatchPendingClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerLabel(for: clip))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 4)

            Spacer(minLength: 4)

            WaveformBars(progress: progressFor(clip))
                .frame(height: 28)
                .padding(.horizontal, 4)

            HStack {
                Text(timeLabel(for: playback.currentTime(for: clip.clipId)))
                Spacer()
                Text(timeLabel(for: clip.duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.horizontal, 4)

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button {
                    playback.togglePlay(clip: clip)
                } label: {
                    Image(systemName: playback.isPlaying(clip.clipId) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying(clip.clipId) ? "Pause" : "Play")
                Spacer()
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 22)
        .onDisappear { playback.stop() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("No recent memory")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text("Memories you capture\nwill replay here.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.bottom, 22)
    }

    // MARK: - Helpers

    private func progressFor(_ clip: WatchPendingClip) -> Double {
        let current = playback.currentTime(for: clip.clipId)
        let total = max(clip.duration, 0.0001)
        return min(1.0, max(0.0, current / total))
    }

    private func headerLabel(for clip: WatchPendingClip) -> String {
        let duration = timeLabel(for: clip.duration)
        let cal = Calendar.current
        if cal.isDateInToday(clip.capturedAt) { return "\(duration) · today" }
        if cal.isDateInYesterday(clip.capturedAt) { return "\(duration) · yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(duration) · \(f.string(from: clip.capturedAt))"
    }

    private func timeLabel(for seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Waveform glyph

/// Decorative waveform bars. Heights come from a static pattern (peak
/// metering after-the-fact off a saved file is overkill for a watch
/// surface). Bars are coloured in the accent up to `progress`, dimmed
/// white beyond it — same visual logic as a player's progress
/// indicator.
private struct WaveformBars: View {
    let progress: Double

    private static let heights: [CGFloat] = [
        6, 10, 18, 12, 22, 14, 20, 8, 16, 24,
        18, 10, 14, 20, 16, 22, 12, 8, 14, 10, 6, 4
    ]

    var body: some View {
        GeometryReader { proxy in
            let count = Self.heights.count
            let cutoff = Int((Double(count) * progress).rounded())
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i < cutoff ? WatchTheme.accent : Color.white.opacity(0.22))
                        .frame(width: max(2, (proxy.size.width / CGFloat(count)) - 2),
                               height: Self.heights[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Playback service

/// AVAudioPlayer-backed playback for the LATEST page. One clip at a
/// time; pressing play on a different clip stops the previous. Tracks
/// `currentTime` via a 4Hz timer so the waveform progress + time label
/// stay in sync.
@MainActor
final class LatestPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private var playingClipId: UUID?
    @Published private var elapsed: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func isPlaying(_ clipId: UUID) -> Bool {
        playingClipId == clipId && (player?.isPlaying ?? false)
    }

    func currentTime(for clipId: UUID) -> TimeInterval {
        playingClipId == clipId ? elapsed : 0
    }

    func togglePlay(clip: WatchPendingClip) {
        if isPlaying(clip.clipId) {
            pause()
        } else {
            play(clip: clip)
        }
    }

    private func play(clip: WatchPendingClip) {
        stop()
        let url = WatchPendingManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingClipId = clip.clipId
            startTicker()
        } catch {
            // Best-effort — if the file can't be opened, leave the UI
            // in the not-playing state.
        }
    }

    private func pause() {
        player?.pause()
        stopTicker()
        objectWillChange.send()
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        playingClipId = nil
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let p = player else { return }
        elapsed = p.currentTime
        if !p.isPlaying && elapsed == 0 {
            playingClipId = nil
            stopTicker()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
