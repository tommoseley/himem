import Testing
import Foundation
@testable import HiMem

/// Money tests for the rollGroup-keyed ack path (§ 8.7 / § 8.1).
///
/// The bug context: when the iPhone disposes of a clip via
/// `InboxManifest.remove` / `removeBatch`, the re-ack only carried the
/// child's `clipId`. For split-session clips, the watch's pending row
/// was registered under the *master*'s clipId — so a child-clipId ack
/// never matched. If the original arrival ack was lost, the watch row
/// stayed pending forever (Tom QA 2026-05-30).
///
/// The fix: dispose acks now carry either a `clipId` OR a
/// `rollGroupId`. Watch matches pending rows by whichever applies.
/// One ack message covers the master + every child of the roll group.
///
/// These tests pin the pure decision layer:
///   1. `WatchSessionDelegate.confirmationPayload` constructs the new
///      `{ confirmed, kind }` wire shape correctly for both clip and
///      rollGroup acks.
///   2. `InboxManifest.ackActions(for:in:)` groups requested clipIds
///      by rollGroupId so a batch of split children produces one
///      rollGroup ack, not N child acks.
struct WatchAckRollGroupTests {

    // MARK: - Wire-format construction

    @Test func confirmationPayload_forClipId_hasClipKind() {
        let clipId = UUID()
        let payload = WatchSessionDelegate.confirmationPayload(clipId: clipId, rollGroupId: nil)
        #expect(payload["confirmed"] as? String == clipId.uuidString)
        #expect(payload["kind"] as? String == "clip")
    }

    @Test func confirmationPayload_forRollGroupId_hasRollGroupKind() {
        let rollGroupId = UUID()
        let payload = WatchSessionDelegate.confirmationPayload(clipId: nil, rollGroupId: rollGroupId)
        #expect(payload["confirmed"] as? String == rollGroupId.uuidString)
        #expect(payload["kind"] as? String == "rollGroup")
    }

    // MARK: - Ack grouping

    /// All N children of a roll group → ONE rollGroup ack, not N
    /// per-clip acks. The whole point of the rebuild.
    @Test func ackActions_forSplitSession_emitsSingleRollGroupAck() {
        let rollGroupId = UUID()
        let childA = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        let childB = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        let childC = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        let actions = InboxManifest.ackActions(
            for: [childA.clipId, childB.clipId, childC.clipId],
            in: [childA, childB, childC]
        )
        #expect(actions == [.rollGroup(rollGroupId)])
    }

    /// A single-clip session (no rollGroupId) → one clip ack.
    /// Preserves the existing behavior for the common path.
    @Test func ackActions_forSingleClip_emitsClipAck() {
        let clip = makeClip(clipId: UUID(), rollGroupId: nil)
        let actions = InboxManifest.ackActions(for: [clip.clipId], in: [clip])
        #expect(actions == [.clip(clip.clipId)])
    }

    /// Removing only SOME children of a roll group still emits one
    /// rollGroup ack. The phone's removal decision is the user's; the
    /// watch ack is just "this session is acknowledged." Remaining
    /// children stay on the phone unaffected; the watch row clears.
    @Test func ackActions_forPartialSplitSession_emitsSingleRollGroupAck() {
        let rollGroupId = UUID()
        let childA = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        let childB = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        let childC = makeClip(clipId: UUID(), rollGroupId: rollGroupId)
        // Only A + B in the removal batch; C stays in the manifest.
        let actions = InboxManifest.ackActions(
            for: [childA.clipId, childB.clipId],
            in: [childA, childB, childC]
        )
        #expect(actions == [.rollGroup(rollGroupId)])
    }

    /// A mixed batch — two roll groups + one singleton → one ack per
    /// group + one clip ack. Order isn't pinned (the set is the
    /// contract); compare as sets.
    @Test func ackActions_forMixedBatch_emitsOneAckPerGroupPlusSingletons() {
        let rgA = UUID()
        let rgB = UUID()
        let groupA1 = makeClip(clipId: UUID(), rollGroupId: rgA)
        let groupA2 = makeClip(clipId: UUID(), rollGroupId: rgA)
        let groupB1 = makeClip(clipId: UUID(), rollGroupId: rgB)
        let single = makeClip(clipId: UUID(), rollGroupId: nil)
        let actions = InboxManifest.ackActions(
            for: [groupA1.clipId, groupA2.clipId, groupB1.clipId, single.clipId],
            in: [groupA1, groupA2, groupB1, single]
        )
        let expected: Set<InboxManifest.AckAction> = [
            .rollGroup(rgA),
            .rollGroup(rgB),
            .clip(single.clipId)
        ]
        #expect(Set(actions) == expected)
    }

    /// ClipIds in the batch but absent from the manifest fall back to
    /// per-clip ack. Covers stale ack requests for already-disposed
    /// clips — the receiver is the right place to no-op, not us.
    @Test func ackActions_forUnknownClipId_emitsClipAck() {
        let unknownId = UUID()
        let actions = InboxManifest.ackActions(for: [unknownId], in: [])
        #expect(actions == [.clip(unknownId)])
    }

    // MARK: - Helpers

    private func makeClip(clipId: UUID, rollGroupId: UUID?) -> InboxClip {
        InboxClip(
            clipId: clipId,
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(clipId.uuidString).caf",
            rollGroupId: rollGroupId
        )
    }
}
