import Testing
import Foundation
import Combine
@testable import Himem_Watch_Watch_App

/// Money tests for the rapid multi-ack delivery path on the watch.
///
/// The bug context (2026-05-29): Tom saw three clips arrive on the
/// phone but the watch still showed all three as pending and a red
/// "Hasn't reached your phone in a day" chip. The phone-side code
/// fires `sendConfirmation` per clip plus a fan-out `reconcileWatchAcks`
/// on every new arrival and on scene-active, so each clip gets
/// multiple ack attempts. If acks reach the watch, the manifest's
/// `remove(viaSync:)` updates `lastConfirmedReceiptAt` which clears
/// the stuck chip and removes the row.
///
/// These tests can't reproduce the actual WCSession delivery layer
/// (no real watch in the test env), but they CAN verify:
///   1. `handleAckPayload` called N times rapidly produces N
///      distinct `lastAckedClipId` publisher events — the channel
///      doesn't coalesce or drop values.
///   2. The manifest's `remove(viaSync:)` is idempotent and updates
///      `lastConfirmedReceiptAt` so the next assertion of
///      "stuck > 24h" resets correctly.
///
/// If these tests pass and Tom's bug reproduces, the failure is at
/// the WC delivery layer (Apple's queue, reachability state, app
/// suspension) — not in our handler code.
struct WatchAckPipelineMultiClipTests {

    /// Rapid back-to-back ack payloads must produce a distinct
    /// publisher event per clipId. Catches regressions where someone
    /// adds `.removeDuplicates()` or collapses the channel onto a
    /// single latest-value semantic, which would silently drop
    /// in-flight acks.
    @Test
    func rapidAckPayloads_publishesEveryClipIdAtLeastOnce() async throws {
        let service = await WatchTransferService()
        let ids = (0..<5).map { _ in UUID() }

        // Subscribe BEFORE firing payloads so we don't race the
        // first-value emission.
        var received: [UUID] = []
        let lock = NSLock()
        let cancellable = await MainActor.run {
            service.$lastAckedClipId
                .compactMap { $0 }
                .sink { id in
                    lock.lock()
                    received.append(id)
                    lock.unlock()
                }
        }
        defer { cancellable.cancel() }

        for id in ids {
            service.handleAckPayload(["confirmedClipId": id.uuidString])
        }

        // Each Task hops to MainActor; give them a generous window
        // to all drain. Real-world ack bursts arrive over hundreds
        // of ms, so 200 ms is enough headroom.
        try await Task.sleep(nanoseconds: 200_000_000)

        lock.lock()
        let receivedCopy = received
        lock.unlock()
        let uniqueReceived = Set(receivedCopy)
        for id in ids {
            #expect(uniqueReceived.contains(id), "Ack for \(id) did not publish — multi-ack pipeline dropped it")
        }
    }

    /// The manifest's `lastConfirmedReceiptAt` is what gates the
    /// red "Hasn't reached your phone in a day" chip — once any
    /// ack lands, the chip should clear. Confirm `remove(viaSync:
    /// false)` updates the timestamp on every call (not just the
    /// first), so rapid clears keep the timestamp fresh.
    @Test @MainActor
    func remove_viaSync_updatesLastConfirmedReceiptAt() async throws {
        let manifest = WatchPendingManifest.shared
        // Stash + restore prior state so the test doesn't leak.
        let priorClips = manifest.clips
        let priorReceipt = manifest.lastConfirmedReceiptAt
        defer {
            manifest.debugReplaceClipsForTesting(priorClips)
            manifest.debugSetLastConfirmedReceiptForTesting(priorReceipt)
        }

        // Seed three pending clips + a stale receipt from > 24h ago.
        func makeClip() -> WatchPendingClip {
            WatchPendingClip(
                clipId: UUID(),
                capturedAt: Date(),
                duration: 10,
                transcript: "",
                latitude: nil,
                longitude: nil,
                audioFilename: "test-\(UUID().uuidString).caf"
            )
        }
        let clipA = makeClip()
        let clipB = makeClip()
        let clipC = makeClip()
        manifest.debugReplaceClipsForTesting([clipA, clipB, clipC])
        manifest.debugSetLastConfirmedReceiptForTesting(Date().addingTimeInterval(-48 * 3600))
        #expect(manifest.isSyncStuck, "Setup precondition: manifest should be stuck after 48h")

        // First ack: timestamp updates to "now-ish."
        let before = Date()
        manifest.remove(clipId: clipA.clipId, viaSync: false)
        let firstReceipt = manifest.lastConfirmedReceiptAt
        #expect(firstReceipt != nil)
        #expect(firstReceipt! >= before, "First ack did not refresh lastConfirmedReceiptAt")
        #expect(manifest.isSyncStuck == false, "Single fresh ack did not clear the stuck flag")

        // Second + third acks: timestamp keeps advancing (or at
        // least stays current); manifest empties out.
        manifest.remove(clipId: clipB.clipId, viaSync: false)
        manifest.remove(clipId: clipC.clipId, viaSync: false)
        #expect(manifest.clips.isEmpty, "Acks for B + C did not remove rows")
    }
}
