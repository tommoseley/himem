import Testing
import Foundation
@testable import HiMem

/// Money tests for the hands-free recording cap (TestFlight #4b, 2026-07-25).
/// `VoiceCaptureScreen.shouldAutoSaveAtLimit` is the pure policy: a Siri/hands-
/// free recording auto-saves (never discards, watch wrist-off rule) when it
/// reaches the user's limit; a held (manual) recording is never capped; `0` =
/// No limit.
struct RecordingCapTests {

    @Test func handsFree_atOrPastLimit_autosaves() {
        // 10-minute limit → cap at 600 s.
        #expect(VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 600, limitMinutes: 10))
        #expect(VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 601, limitMinutes: 10))
        #expect(VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 300, limitMinutes: 5))
    }

    @Test func handsFree_belowLimit_keepsRecording() {
        #expect(!VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 599, limitMinutes: 10))
        #expect(!VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 0, limitMinutes: 10))
    }

    @Test func manual_isNeverCapped() {
        // A held recording is unbounded — even far past any limit.
        #expect(!VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .manual, elapsed: 100_000, limitMinutes: 10))
        #expect(!VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .manual, elapsed: 600, limitMinutes: 5))
    }

    @Test func noLimit_isNeverCapped() {
        // limitMinutes == 0 → "No limit" — even a hands-free recording runs on.
        #expect(!VoiceCaptureScreen.shouldAutoSaveAtLimit(source: .handsFree, elapsed: 100_000, limitMinutes: 0))
    }

    /// The confirmation is one string for both a Siri stop and a cap-triggered
    /// save (so the cap never reads as an error), with the real duration and
    /// correct pluralization; a sub-minute clip still reads "1 minute".
    @Test func savedConfirmation_realDuration_uniform() {
        #expect(VoiceCaptureScreen.savedConfirmation(minutes: 10) == "Saved — 10 minutes.")
        #expect(VoiceCaptureScreen.savedConfirmation(minutes: 1) == "Saved — 1 minute.")
        #expect(VoiceCaptureScreen.savedConfirmation(minutes: 0) == "Saved — 1 minute.")
    }
}
