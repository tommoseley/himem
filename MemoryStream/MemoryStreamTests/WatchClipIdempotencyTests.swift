import Testing
import Foundation
@testable import HiMem

/// Money tests for the 2026-05-27 duplicate-fragments bug. Tom
/// recorded 3 Record→Stop cycles (single, single, on-a-roll-2-clip)
/// and the phone produced a single session card with 8-10 clips —
/// the on-a-roll master was being redelivered by iOS WC and each
/// redelivery ran `VoiceClipSplitter` again, minting fresh
/// `UUID()` fragment clipIds that bypassed
/// `InboxManifest.acceptClip`'s clipId-based dedup.
///
/// Fix: `WatchSessionDelegate.shouldDropArrivedMaster` — when the
/// master's clipId or rollGroupId is already represented in the
/// manifest (single path uses clipId, split path uses rollGroupId on
/// every fragment), treat the redelivery as a no-op. After Step F's
/// consolidation the predicate operates on the manifest's `status`
/// enum + an `isRollGroupKnown` query; these tests exercise that
/// composed contract.
///
/// `ClipMetadata.clipId` is documented as the iPhone-side
/// idempotency key. These tests assert the gate honors that.
@MainActor
struct WatchClipIdempotencyTests {

    private func makeInboxClip(
        clipId: UUID = UUID(),
        rollGroupId: UUID? = nil,
        capturedAt: Date = Date()
    ) -> InboxClip {
        InboxClip(
            clipId: clipId,
            capturedAt: capturedAt,
            duration: 0.1,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(clipId.uuidString).caf",
            transcriptionAttempted: true,
            rollGroupId: rollGroupId
        )
    }

    private func makeMetadata(
        clipId: UUID = UUID(),
        rollGroupId: UUID? = nil,
        nextTapOffsets: [TimeInterval] = []
    ) -> ClipMetadata {
        ClipMetadata(
            clipId: clipId,
            capturedAt: Date(),
            duration: 0.1,
            transcript: "",
            source: "watch",
            rollGroupId: rollGroupId,
            nextTapOffsets: nextTapOffsets
        )
    }

    /// Helper that composes the same decision the live
    /// `acceptArrivedClip` makes: look up the clipId's status in the
    /// given clips, check if any clip uses the master's rollGroupId,
    /// hand both to `shouldDropArrivedMaster`. Mirrors the live
    /// call site so a regression there shows up here.
    private func wouldDrop(
        _ metadata: ClipMetadata,
        in manifestClips: [InboxClip]
    ) -> Bool {
        let status = manifestClips.first { $0.clipId == metadata.clipId }?.status
        let rollGroupId = metadata.rollGroupId ?? metadata.clipId
        let rollGroupInUse = manifestClips.contains { $0.rollGroupId == rollGroupId }
        return WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: status,
            rollGroupIdAlreadyInUse: rollGroupInUse
        )
    }

    @Test func emptyManifest_isNotDuplicate() {
        let metadata = makeMetadata()
        #expect(wouldDrop(metadata, in: []) == false)
    }

    @Test func singlePath_clipIdAlreadyInManifest_isDuplicate() {
        // Single-clip arrival: master's clipId is reused as the
        // InboxClip's clipId. Redelivery should be a no-op.
        let masterClipId = UUID()
        let existing = makeInboxClip(clipId: masterClipId, rollGroupId: nil)
        let metadata = makeMetadata(clipId: masterClipId, rollGroupId: nil)
        #expect(wouldDrop(metadata, in: [existing]) == true)
    }

    /// The exact regression: split-path fragments carry the master's
    /// rollGroupId. A redelivery of the master with the same
    /// rollGroupId must be detected as duplicate even though the
    /// existing fragment InboxClip.clipId is a fresh UUID and does
    /// NOT equal `metadata.clipId`.
    @Test func splitPath_rollGroupIdAlreadyInManifest_isDuplicate() {
        let masterClipId = UUID()
        let rollId = UUID()
        let fragment = makeInboxClip(clipId: UUID(), rollGroupId: rollId)
        let metadata = makeMetadata(
            clipId: masterClipId,
            rollGroupId: rollId,
            nextTapOffsets: [3.0]
        )
        #expect(wouldDrop(metadata, in: [fragment]) == true)
    }

    /// Split-path edge case: metadata had no rollGroupId, so the
    /// receive path fell back to using `metadata.clipId` as the
    /// fragment rollGroupId. Detect that on redelivery too.
    @Test func splitPath_clipIdAsRollGroupId_isDuplicate() {
        let masterClipId = UUID()
        let fragment = makeInboxClip(clipId: UUID(), rollGroupId: masterClipId)
        let metadata = makeMetadata(
            clipId: masterClipId,
            rollGroupId: nil,
            nextTapOffsets: [3.0]
        )
        #expect(wouldDrop(metadata, in: [fragment]) == true)
    }

    @Test func differentMaster_inManifest_isNotDuplicate() {
        let existing = makeInboxClip(clipId: UUID(), rollGroupId: UUID())
        let metadata = makeMetadata(clipId: UUID(), rollGroupId: UUID())
        #expect(wouldDrop(metadata, in: [existing]) == false)
    }

    /// Tom's screenshot scenario: the on-a-roll master is in the
    /// manifest as 2 fragments sharing a rollGroupId. The watch
    /// redelivers the same master. The gate must catch it.
    @Test func twoFragmentMaster_redelivered_isDuplicate_perScreenshotBug() {
        let masterClipId = UUID()
        let rollId = UUID()
        let fragmentA = makeInboxClip(clipId: UUID(), rollGroupId: rollId)
        let fragmentB = makeInboxClip(clipId: UUID(), rollGroupId: rollId)
        let redelivery = makeMetadata(
            clipId: masterClipId,
            rollGroupId: rollId,
            nextTapOffsets: [3.0]
        )
        #expect(wouldDrop(redelivery, in: [fragmentA, fragmentB]) == true)
    }

    @Test func unrelatedRollIdInManifest_isNotDuplicate() {
        let unrelatedRoll = UUID()
        let other = makeInboxClip(clipId: UUID(), rollGroupId: unrelatedRoll)
        let metadata = makeMetadata(
            clipId: UUID(),
            rollGroupId: UUID(),  // different roll
            nextTapOffsets: [3.0]
        )
        #expect(wouldDrop(metadata, in: [other]) == false)
    }
}
