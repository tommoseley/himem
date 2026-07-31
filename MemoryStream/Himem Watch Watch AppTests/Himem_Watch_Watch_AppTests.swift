import Testing
import Foundation
@testable import Himem_Watch_Watch_App

struct WatchTransferServiceTests {

    // MARK: - shouldEnqueue · duplicate-delivery money tests
    //
    // Dogfood 2026-07-29: one 21 s watch clip arrived on the iPhone FOUR
    // times, from four distinct WC transfer directories. Root cause: every
    // `flushPendingManifest` trigger (reachability false→true, the phone's
    // `flushPending` pull-to-refresh, the phone's durable-wake kick) re-ran
    // `send` → `enqueueReadyTransfer`, whose only de-dup gate was
    // `outstandingFileTransfers`. That array holds only transfers that have
    // NOT yet completed, while the manifest row survives until the iPhone
    // acks — so between "bytes delivered" and "ack received" the clip looked
    // un-sent and got shipped again, in full, on every trigger.
    //
    // The invariant: bytes already delivered are never re-shipped. The ack —
    // not a re-ship — is what clears the manifest row.

    /// THE MONEY ASSERTION. A clip whose bytes WCSession already delivered,
    /// and which is therefore no longer `outstanding`, must NOT be handed to
    /// `transferFile` again while it waits for the iPhone's ack.
    @Test
    func deliveredAwaitingAck_isNotReEnqueued() {
        let clipId = UUID()
        let decision = WatchTransferService.shouldEnqueue(
            clipId: clipId,
            outstanding: [],                 // delivered ⇒ left outstandingFileTransfers
            deliveredAwaitingAck: [clipId]   // …but the iPhone hasn't acked yet
        )
        #expect(decision == false, "Re-shipped bytes already delivered — the 4× duplicate-delivery bug regressed")
    }

    /// A clip still in flight is refused, as before — this is the original
    /// §8.2 double-delivery belt and must keep working.
    @Test
    func inFlightClip_isNotReEnqueued() {
        let clipId = UUID()
        #expect(WatchTransferService.shouldEnqueue(
            clipId: clipId, outstanding: [clipId], deliveredAwaitingAck: []
        ) == false)
    }

    /// A clip that is neither in flight nor delivered DOES ship. Without
    /// this, an over-eager guard would strand every clip — the failure mode
    /// that matters more than duplication.
    @Test
    func freshClip_isEnqueued() {
        #expect(WatchTransferService.shouldEnqueue(
            clipId: UUID(), outstanding: [], deliveredAwaitingAck: []
        ) == true)
    }

    /// Other clips' state is not this clip's business — a delivered sibling
    /// must not suppress an unrelated clip.
    @Test
    func siblingStateDoesNotSuppressThisClip() {
        #expect(WatchTransferService.shouldEnqueue(
            clipId: UUID(), outstanding: [UUID()], deliveredAwaitingAck: [UUID()]
        ) == true)
    }

    /// BOTH ack paths must maintain the delivered-awaiting-ack state, not just
    /// the per-clip one. A rollGroup ack confirms every member clip at once
    /// (§8.7), so it must release every member — otherwise the entries sit
    /// there until activation, and the only thing preventing a re-ship is that
    /// `flushPendingManifest` happens to iterate rows the coordinator already
    /// removed. That is an ordering coincidence, not an invariant, and one ack
    /// path maintaining state the other ignores is precisely the shape of the
    /// duplicate-delivery bug.
    @Test
    func rollGroupAck_releasesEveryMemberClip() async throws {
        let service = await WatchTransferService()
        let rollGroup = UUID()
        let otherGroup = UUID()
        let clipA = UUID(), clipB = UUID(), clipElsewhere = UUID()

        await MainActor.run {
            service.deliveredAwaitingAck = [
                clipA: rollGroup,
                clipB: rollGroup,
                clipElsewhere: otherGroup
            ]
        }

        service.handleAckPayload(["confirmed": rollGroup.uuidString, "kind": "rollGroup"])
        try await Task.sleep(nanoseconds: 50_000_000)

        let remaining = await Set(service.deliveredAwaitingAck.keys)
        #expect(
            remaining == [clipElsewhere],
            "rollGroup ack left members suppressed: \(remaining.count) key(s) remain, expected only the other group's clip"
        )
    }

    /// A rollGroup ack must not release clips belonging to a different group —
    /// the over-clearing mirror of the test above. Releasing too much would
    /// re-open the duplicate storm for unrelated clips.
    @Test
    func rollGroupAck_leavesOtherGroupsSuppressed() async throws {
        let service = await WatchTransferService()
        let acked = UUID(), untouched = UUID()
        let mine = UUID(), theirs = UUID()

        await MainActor.run {
            service.deliveredAwaitingAck = [mine: acked, theirs: untouched]
        }

        service.handleAckPayload(["confirmed": acked.uuidString, "kind": "rollGroup"])
        try await Task.sleep(nanoseconds: 50_000_000)

        let remaining = await Set(service.deliveredAwaitingAck.keys)
        #expect(remaining == [theirs])
    }

    /// Guards the parsing logic that both delivery paths (sendMessage and
    /// transferUserInfo) feed into. Regression target: a typo in the payload
    /// key or UUID parsing change would break ack-driven manifest pruning.
    @Test
    func handleAckPayloadSetsLastAckedClipId() async throws {
        let service = await WatchTransferService()
        let clipId = UUID()

        service.handleAckPayload(["confirmedClipId": clipId.uuidString])

        // The handler hops to MainActor via Task; give it a tick to settle.
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == clipId)
    }

    @Test
    func handleAckPayloadIgnoresMissingKey() async throws {
        let service = await WatchTransferService()
        service.handleAckPayload(["someOtherKey": "value"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == nil)
    }

    @Test
    func handleAckPayloadIgnoresMalformedUUID() async throws {
        let service = await WatchTransferService()
        service.handleAckPayload(["confirmedClipId": "not-a-uuid"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == nil)
    }
}
