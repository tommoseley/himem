import Testing
import Foundation
@testable import HiMem

/// Characterization tests for `VoiceRecordingController` (CRAP audit
/// Batch 6 — pulled out of `VoiceCaptureScreen` to localize the
/// recording-phase state cluster: elapsed timer + waveform buffer).
///
/// The timer wall-clock cadence is framework code (`Timer.scheduledTimer`
/// in the view layer's `RunLoop.current`) and is intentionally not
/// unit-tested — it's exercised via human QA. The tests below lock
/// in the buffer + reset semantics, which is the part that actually
/// matters for visual continuity.
@MainActor
@Suite(.serialized)
struct VoiceRecordingControllerTests {

    private func makeController() -> VoiceRecordingController {
        VoiceRecordingController()
    }

    // MARK: - start() resets

    @Test func start_resetsElapsedToZero() {
        let c = makeController()
        c.elapsed = 12.5
        c.start()
        #expect(c.elapsed == 0)
    }

    @Test func start_clearsExistingWaveformSamples() {
        let c = makeController()
        c.ingest(sample: 0.3)
        c.ingest(sample: 0.5)
        #expect(c.waveSamples.count == 2)
        c.start()
        #expect(c.waveSamples.isEmpty)
    }

    // MARK: - ingest

    @Test func ingest_appendsToBuffer() {
        let c = makeController()
        c.ingest(sample: 0.1)
        c.ingest(sample: 0.2)
        c.ingest(sample: 0.3)
        #expect(c.waveSamples == [0.1, 0.2, 0.3])
    }

    @Test func ingest_trimsToWaveBarCount() {
        let c = makeController()
        // Push more than the visible window. The buffer must cap
        // at exactly `waveBarCount` so the rendered band doesn't
        // grow without bound.
        for i in 0..<(VoiceRecordingController.waveBarCount + 10) {
            c.ingest(sample: CGFloat(i) / 100)
        }
        #expect(c.waveSamples.count == VoiceRecordingController.waveBarCount)
        // The oldest samples (0..9) should have been dropped from
        // the head; the buffer keeps the most-recent window.
        #expect(c.waveSamples.first ?? 0 > 0)
    }

    // MARK: - sample(atOffsetFromRight:)

    @Test func sample_atOffsetZero_returnsMostRecent() {
        let c = makeController()
        c.ingest(sample: 0.1)
        c.ingest(sample: 0.2)
        c.ingest(sample: 0.9)
        #expect(c.sample(atOffsetFromRight: 0) == 0.9)
    }

    @Test func sample_atPositiveOffset_returnsOlder() {
        let c = makeController()
        c.ingest(sample: 0.1)
        c.ingest(sample: 0.2)
        c.ingest(sample: 0.3)
        #expect(c.sample(atOffsetFromRight: 1) == 0.2)
        #expect(c.sample(atOffsetFromRight: 2) == 0.1)
    }

    @Test func sample_atOffsetBeyondBuffer_returnsZero() {
        let c = makeController()
        c.ingest(sample: 0.5)
        // Bar slots beyond the populated buffer render as zero
        // height — the view always draws all `waveBarCount` bars.
        #expect(c.sample(atOffsetFromRight: 5) == 0)
        #expect(c.sample(atOffsetFromRight: 100) == 0)
    }

    // MARK: - stop()

    @Test func stop_preservesWaveformForFinalizationRendering() {
        // The finalization overlay fades the recording UI but the
        // user still sees their waveform momentarily. stop() must
        // not blow away the buffer that's still being rendered.
        let c = makeController()
        c.ingest(sample: 0.4)
        c.ingest(sample: 0.7)
        c.stop()
        #expect(c.waveSamples == [0.4, 0.7])
    }
}
