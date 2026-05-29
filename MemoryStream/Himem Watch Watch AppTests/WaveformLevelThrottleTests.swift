import Testing
import Foundation
@testable import Himem_Watch_Watch_App

/// Money tests for `WatchRecordingService.WaveformLevelThrottle` —
/// the helper that closes the second waveform bug Tom hit on
/// 2026-05-29.
///
/// The bug: the 100 ms throttle was sampling a single ~5 ms audio
/// buffer per window, then publishing its peak as the bar height.
/// If that one buffer happened to fall between syllables, the
/// waveform read as silence even though the rest of the 100 ms
/// window contained real speech. The fix tracks running peak
/// across every buffer in the window and publishes the max when
/// the window closes.
///
/// These tests drive the helper deterministically with synthetic
/// (peak, time) pairs so the bug-fix invariant — "the loudest
/// sample in the window survives to the publish" — is locked
/// against future regressions.
struct WaveformLevelThrottleTests {

    /// Convenience seed: a fresh lock + zeroed state holders.
    private final class State {
        var lastPublishedAt: CFTimeInterval = 0
        var runningPeak: Float = 0
        let lock = NSLock()
    }

    /// THE BUG-FIX MONEY ASSERTION. Within a single throttle window,
    /// a loud syllable followed by a quiet buffer must NOT lose the
    /// loud peak when the window finally closes — that was the
    /// exact failure mode Tom saw on the watch waveform.
    @Test
    func loudPeakThenSilence_publishesTheLoudPeak() {
        let s = State()
        // t=0.00: first call — loud syllable. Publishes immediately
        // (lastPublishedAt was 0) and resets.
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.0, now: 0, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        // t=0.01: loud syllable mid-window. Tracks; not due.
        let r1 = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.8, now: 0.01, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(r1 == nil)
        // t=0.05: dead air between syllables. Running peak holds 0.8.
        let r2 = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.05, now: 0.05, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(r2 == nil)
        // t=0.11: window closes. Must publish 0.8 — the loudest
        // moment in this window — NOT the 0.05 of the boundary
        // buffer.
        let r3 = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.05, now: 0.11, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(r3 == 0.8, "Throttle dropped the loud syllable — pre-fix bug regressed")
    }

    /// After publishing, the running peak resets so the NEXT window
    /// starts fresh from whatever its own buffers bring. Without
    /// the reset, a loud syllable in window 1 would shadow quieter
    /// passages in window 2 forever.
    @Test
    func runningPeakResetsAfterPublish() {
        let s = State()
        // Burn the first publish (lastPublishedAt=0 triggers an
        // immediate publish on call #1).
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.9, now: 0, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        // Window 1: loud peak, then close.
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.7, now: 0.05, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        let close1 = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.0, now: 0.11, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(close1 == 0.7)
        // Window 2: only quiet samples. Must NOT republish 0.7.
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.1, now: 0.15, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        let close2 = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.1, now: 0.22, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(close2 == 0.1, "Running peak leaked across windows: \(close2 ?? -1)")
    }

    /// Sub-throttle calls (within the 100 ms window) return nil —
    /// no publish happens. Only the window-closing call gets a
    /// snapshot.
    @Test
    func midWindowCalls_returnNil() {
        let s = State()
        s.lastPublishedAt = 1.0  // simulate already mid-stream
        for tick in stride(from: 1.01, through: 1.09, by: 0.01) {
            let r = WatchRecordingService.WaveformLevelThrottle.observe(
                bufferPeak: 0.4, now: tick, lastPublishedAt: &s.lastPublishedAt,
                runningPeak: &s.runningPeak, lock: s.lock
            )
            #expect(r == nil, "Mid-window call at t=\(tick) shouldn't publish")
        }
        // Just past 100 ms → publishes.
        let r = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0.4, now: 1.11, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(r != nil)
    }

    /// Sanity: peak of zero through a whole window publishes 0.
    /// The function isn't required to be positive — pure silence
    /// must read as silence.
    @Test
    func allZeroes_publishesZero() {
        let s = State()
        // Burn the first publish so the next is clean.
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0, now: 0, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        _ = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0, now: 0.05, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        let close = WatchRecordingService.WaveformLevelThrottle.observe(
            bufferPeak: 0, now: 0.11, lastPublishedAt: &s.lastPublishedAt,
            runningPeak: &s.runningPeak, lock: s.lock
        )
        #expect(close == 0)
    }
}
