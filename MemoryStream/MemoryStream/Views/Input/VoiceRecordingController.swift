import Foundation
import SwiftUI

/// Owns the recording-phase state cluster (elapsed timer + rolling
/// waveform buffer) for `VoiceCaptureScreen`. Extracted from the
/// view (CRAP audit Batch 6) to localize ~5 `@State` properties
/// that were entangled — start/stop touched the timer, the
/// startedAt anchor, the elapsed counter, and the waveform sample
/// buffer in lockstep, and they all had to live in the view
/// because they read each other's values.
///
/// **What's here:**
///   - `elapsed` — derived from a 10 Hz `Timer.scheduledTimer`
///     anchored to `startedAt` on `start()`.
///   - `waveSamples` — rolling audio-level buffer capped at
///     `waveBarCount` (56 to match the phone composer width).
///   - `start()` / `stop()` — timer + buffer lifecycle.
///   - `ingest(sample:)` — driven by the view's `.onReceive` of
///     `SpeechService.$audioLevel`.
///   - `sample(atOffsetFromRight:)` — view-side bar lookup that
///     returns 0 when reading past the populated buffer.
///
/// **What stayed on the view:** `recPulse` (pure SwiftUI animation
/// toggle), `phase` (state machine for the breath/recording/denied
/// switch — it owns sub-view selection, not recording mechanics),
/// `sessionLocation` (orchestrates LocationService, presentation
/// concern). Those don't belong in a recording controller.
@MainActor
final class VoiceRecordingController: ObservableObject {

    /// Phone composer has more horizontal room than the watch, so
    /// the band carries 56 bars. Each bar is ~3pt + 1pt gap across
    /// the typical iPhone composer width with 16pt side padding.
    /// Static so callers (and tests) don't need to reach through
    /// an instance.
    static let waveBarCount: Int = 56

    @Published var elapsed: TimeInterval = 0
    @Published var waveSamples: [CGFloat] = []

    private var startedAt: Date?
    private var timer: Timer?

    init() {}

    /// Anchors `startedAt` to now, zeroes `elapsed`, clears the
    /// waveform buffer, and kicks off the 100 ms timer that drives
    /// the on-screen counter. The 10 Hz cadence matches the
    /// `SpeechService` audio-level throttle so the counter and the
    /// waveform share visual rhythm.
    func start() {
        stop()
        startedAt = Date()
        elapsed = 0
        waveSamples = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(s)
            }
        }
    }

    /// Stops the timer. The waveform buffer is intentionally
    /// preserved so the finalization overlay can render the last
    /// audible moment as the screen fades out.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Appends a fresh audio-level sample to the rolling buffer
    /// and trims to the visible window. The view calls this on
    /// every `SpeechService.$audioLevel` tick while the recording
    /// phase is active.
    func ingest(sample: CGFloat) {
        waveSamples.append(sample)
        if waveSamples.count > Self.waveBarCount {
            waveSamples.removeFirst(waveSamples.count - Self.waveBarCount)
        }
    }

    /// Returns the wave-bar height for the position `offsetFromRight`
    /// slots back from the latest sample. The view always renders
    /// `waveBarCount` bars; any position past the populated buffer
    /// reads 0, which the view draws as a zero-height bar.
    func sample(atOffsetFromRight offset: Int) -> CGFloat {
        let bufIdx = waveSamples.count - 1 - offset
        return bufIdx >= 0 ? waveSamples[bufIdx] : 0
    }
}
