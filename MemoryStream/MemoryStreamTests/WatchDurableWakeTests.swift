import Testing
import Foundation
@testable import HiMem

/// P1 money tests — phone-initiated durable-wake kick for stalled
/// watch→phone sync (`Handoff · carry-forward punch list · 2026-07-14`).
///
/// The bug: a `transferFile` clip queued on a backgrounded watch is
/// durable and always *eventually* delivers, but nothing promptly
/// **kicks** it. The only automatic kick in the system was the watch
/// foregrounding itself (`Himem_WatchApp` scenePhase→.active) — i.e.
/// the "manual watch tap." The phone had no automatic channel to nudge
/// a backgrounded watch: `sendMessage` needs `isReachable` (false when
/// the watch app is backgrounded), so it can't reach it, and re-queuing
/// `transferFile` is a no-op against the `outstandingFileTransfers`
/// dedup guard. The lever is a durable `transferUserInfo`, which wakes
/// the backgrounded watch app to receive it — and that wake is the
/// scheduling opportunity the queued transfer needs.
///
/// These pin the **pure decision layer** — the part that is 100% our
/// code. The "…and the transfer then starts within N seconds" half is
/// iOS-scheduling and is device-dogfood territory, not a unit test
/// (see the risk note in the handoff).
///
/// Serialized because `kick_gatedOnLivePendingSignal` mutates the
/// shared `InboxArrivalTracker.shared` singleton — parallel `@Suite`
/// runs against a shared non-thread-safe singleton corrupt each other
/// (CLAUDE.md · Test Concurrency and Shared Singletons).
@Suite(.serialized)
struct WatchDurableWakeTests {

    // MARK: - The gate (condition 1: only wake when a transfer is pending)

    @Test func decision_wakesWhenInboundPending() {
        #expect(WatchSessionDelegate.durableWakeDecision(hasPendingInbound: true) == .wake)
    }

    @Test func decision_skipsWhenNothingPending() {
        #expect(WatchSessionDelegate.durableWakeDecision(hasPendingInbound: false) == .skip)
    }

    // MARK: - The wire payload the durable wake carries

    @Test func wakePayload_isFlushCommand() {
        let payload = WatchSessionDelegate.durableWakePayload()
        #expect(payload["command"] as? String == "flushPending")
    }

    // MARK: - Gate reads the real in-flight signal end-to-end

    /// Ties the gate to the actual production signal
    /// (`InboxArrivalTracker.hasAnyInFlight`): empty inbox → skip;
    /// after a pre-announce lands → wake. This is the guard that stops
    /// the phone paying the wake/battery cost on every foreground with
    /// an empty inbox.
    @MainActor @Test func kick_gatedOnLivePendingSignal() {
        InboxArrivalTracker.shared.debugResetForTesting()
        #expect(
            WatchSessionDelegate.durableWakeDecision(
                hasPendingInbound: InboxArrivalTracker.shared.hasAnyInFlight
            ) == .skip
        )

        InboxArrivalTracker.shared.recordPreAnnounce(
            clipId: UUID(),
            capturedAt: Date(),
            durationSeconds: 5,
            latitude: nil,
            longitude: nil,
            fileSizeBytes: nil
        )
        #expect(
            WatchSessionDelegate.durableWakeDecision(
                hasPendingInbound: InboxArrivalTracker.shared.hasAnyInFlight
            ) == .wake
        )

        InboxArrivalTracker.shared.debugResetForTesting()
    }
}
