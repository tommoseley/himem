import Testing
import AVFoundation
@testable import HiMem

/// Capture-gain P0 (2026-07-15) — the session-mode invariant.
///
/// The watch MUST record in a gain-applying mode. `.measurement` mode
/// minimizes system input processing (including input GAIN), which left the
/// watch mic at ~-40 dBFS — silent, untranscribable clips (the loud-clip
/// dogfood had `in_peak` pinned ~0.01). `.default` applies gain (and resolves
/// the input to mono). Real input energy needs mic hardware to measure — the
/// `[Amp]` transcode log is that device-side check. THIS is the deterministic
/// guard: a refactor can't silently revert the record mode back to
/// `.measurement` and re-break capture. Its own suite, separate from the
/// transcode energy suite.
@Suite
struct WatchAudioSessionConfigTests {

    @Test func recordMode_appliesInputGain_notMeasurement() {
        #expect(WatchAudioSessionConfig.recordMode != .measurement,
                "watch must not record in .measurement — it suppresses input gain (silent clips, capture-gain P0)")
        #expect(WatchAudioSessionConfig.recordMode == .default,
                "watch records in .default (applies input gain, resolves to mono)")
    }
}
