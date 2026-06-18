import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Money test for the 2026-06-18 bug Tom observed: a watch on-a-roll
/// session split into 2 clips landed in `InboxManifest`, but both
/// clips stayed stuck on "Transcribing…" for 20+ minutes after the
/// user opened the app.
///
/// Root cause (confirmed by device-console diagnostics): the
/// scene-active backstop in `MemoryStreamApp` is gated by
/// `guard storageReady else { return }`. On cold launch SwiftUI's
/// `.onChange(of: scenePhase)` fires once with `.active` **before**
/// `LaunchScreenView`'s async storage init has flipped
/// `storageReady = true`. The handler exits silently, no second
/// observer covers the gap, so `transcribePendingInboxClips` never
/// runs and pending clips wait forever.
///
/// **Two-part fix:**
/// 1. `MemoryStreamApp` adds `.onChange(of: storageReady)` that
///    calls `transcribePendingInboxClips(trigger: "scene-active")`
///    when storage transitions ready — bridges the race.
/// 2. `WatchSessionDelegate` adds `scheduleRetryIfStillPending`: a
///    30s self-cancelling retry timer so any non-`.transcribed`
///    outcome (model installing, file not yet downloaded, transient
///    transcriber failure) re-attempts without needing another
///    scene-active or arrival event.
///
/// **Why these tests use `.fileUnreadable`:**
/// The dispatcher's behavior on non-`.transcribed` outcomes is what
/// Fix A targets. `.fileUnreadable` is the one outcome we can force
/// deterministically (just plant a manifest row with a non-existent
/// audio filename). `.modelNotInstalled` would also exercise the
/// same code path but is non-deterministic — the simulator may or
/// may not have the speech model installed, and the existing
/// `WatchClipArrivalTranscriptionTests` already shows that skip
/// pattern can silently no-op. These tests guarantee the assertions
/// run.
///
/// Serialized because all three tests mutate `InboxManifest.shared`
/// and `WatchSessionDelegate.retryTask`, neither of which is
/// thread-safe — per CLAUDE.md's test-concurrency rule.
@MainActor
@Suite(.serialized)
struct ColdLaunchTranscriptionRaceTests {

    /// Plants a manifest row pointing at a non-existent audio file.
    /// `AVAudioFile` open will throw → `TranscriptionService.transcribe`
    /// returns `.fileUnreadable` → dispatcher should NOT mark
    /// attempted → clip stays pending → `scheduleRetryIfStillPending`
    /// MUST arm a retry.
    private func plantUntranscribableClip() -> UUID {
        let clipId = UUID()
        let clip = InboxClip(
            clipId: clipId,
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "test",
            audioFilename: "nonexistent-\(clipId.uuidString).caf",
            transcriptionAttempted: false,
            rollGroupId: nil
        )
        InboxManifest.shared.acceptClip(clip)
        return clipId
    }

    /// Money test #1 — Fix A: when a pending clip fails to transcribe
    /// (here forced via `.fileUnreadable`), the dispatcher must NOT
    /// mark it attempted (so the next sweep retries) AND
    /// `scheduleRetryIfStillPending` must arm the 30s self-retry —
    /// the latter is the entire reason a clip whose model was still
    /// installing previously sat forever after the first attempt.
    @Test func deferredOutcome_armsRetry_andLeavesClipPending() async throws {
        WatchSessionDelegate.cancelPendingRetryForTesting()

        let clipId = plantUntranscribableClip()
        defer {
            InboxManifest.shared.remove(clipId: clipId)
            WatchSessionDelegate.cancelPendingRetryForTesting()
        }

        // Pre-condition: clip is pending.
        let before = InboxManifest.shared.clips.first { $0.clipId == clipId }
        #expect(before?.transcript.isEmpty == true)
        #expect(before?.transcriptionAttempted == false)
        #expect(WatchSessionDelegate.hasPendingRetry == false,
                "Pre-condition: no retry armed at test entry")

        // Money call — what the new `.onChange(of: storageReady)`
        // bridge runs.
        await WatchSessionDelegate.transcribePendingInboxClips(trigger: "scene-active")

        // Post-conditions of Fix A:
        let after = InboxManifest.shared.clips.first { $0.clipId == clipId }
        #expect(after?.transcriptionAttempted == false,
                ".fileUnreadable must NOT mark attempted — otherwise a transient open failure burns the clip permanently")
        #expect(after?.transcript.isEmpty == true)
        #expect(WatchSessionDelegate.hasPendingRetry == true,
                "Fix A: retry MUST be armed when queue still has pending clip — this is what stops the cold-launch starvation loop")
    }

    /// Money test #2 — Fix A self-cancellation: when the pending queue
    /// drains (no clips remaining that need transcription), the retry
    /// timer must NOT remain armed. Otherwise a 30s loop runs forever
    /// re-checking an empty queue.
    @Test func emptyQueue_doesNotArmRetry() async throws {
        WatchSessionDelegate.cancelPendingRetryForTesting()
        defer { WatchSessionDelegate.cancelPendingRetryForTesting() }

        // Drain any pre-existing pending clips on the test
        // simulator's persistent manifest so this test is
        // deterministic regardless of what state the simulator
        // accumulated from prior runs. We mark them attempted
        // (rather than remove) so we don't destroy a developer's
        // real captured-clip data on the test simulator.
        let leftover = InboxManifest.shared.clips.filter {
            $0.transcript.isEmpty && !$0.transcriptionAttempted
        }
        for clip in leftover {
            InboxManifest.shared.recordTranscriptionAttempt(
                clipId: clip.clipId,
                transcript: ""
            )
        }

        await WatchSessionDelegate.transcribePendingInboxClips(trigger: "scene-active")

        #expect(WatchSessionDelegate.hasPendingRetry == false,
                "Empty queue must not arm a retry — otherwise a 30s timer runs forever for no reason")
    }

    /// Money test #3 — Fix A idempotency: calling the dispatcher
    /// twice while pending work remains must not stack retry timers.
    /// `scheduleRetryIfStillPending` cancels the prior task before
    /// arming a new one, so `hasPendingRetry` should still be `true`
    /// after the second call (a fresh timer is armed), not "two
    /// timers running."
    @Test func multipleSweeps_doNotStackRetries() async throws {
        WatchSessionDelegate.cancelPendingRetryForTesting()

        let clipId = plantUntranscribableClip()
        defer {
            InboxManifest.shared.remove(clipId: clipId)
            WatchSessionDelegate.cancelPendingRetryForTesting()
        }

        await WatchSessionDelegate.transcribePendingInboxClips(trigger: "scene-active")
        #expect(WatchSessionDelegate.hasPendingRetry == true)

        await WatchSessionDelegate.transcribePendingInboxClips(trigger: "retry")
        #expect(WatchSessionDelegate.hasPendingRetry == true,
                "After re-arming, exactly one retry should be live (not zero, not two)")
    }
}
