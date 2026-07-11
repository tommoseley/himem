import Testing
import Foundation
import Combine
@testable import HiMem

/// Money tests for the Sort dismissal store on `InboxManifest`.
/// Per `Captured Clips · session-first · spec.md` v3 § "Sort is
/// the bench's resting state" + Tom's Q3 answer (July 4 2026):
/// dismissed cluster fingerprints suppress re-propose; prune-on-
/// write drops records whose clipIds are no longer all in the
/// inbox.
@MainActor
@Suite(.serialized)
struct InboxManifestDismissedClustersTests {

    // MARK: - Fixtures

    private func plantClip(_ clipId: UUID = UUID()) -> UUID {
        let clip = InboxClip(
            clipId: clipId,
            capturedAt: Date(),
            duration: 5,
            transcript: "test",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(clipId.uuidString).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
        // Touch a stub audio file so the manifest keeps the row
        // through load's file-existence filter.
        let url = InboxManifest.audioURL(for: clip.audioFilename)
        FileManager.default.createFile(atPath: url.path, contents: Data([0x00]))
        InboxManifest.shared.acceptClip(clip)
        return clipId
    }

    private func proposal(clipIds: [UUID], rule: ClusterProposal.RuleTag = .timePlace) -> ClusterProposal {
        ClusterProposal(
            clipIds: clipIds,
            ruleTag: rule,
            whyText: "test cluster",
            proposedName: "test",
            previewLines: []
        )
    }

    // MARK: - Suppression

    /// Dismissing a proposal adds its fingerprint to the
    /// `dismissedClusterFingerprints` set the proposer consumes.
    @Test
    func dismiss_addsFingerprintToSet() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }

        // Fresh state — snapshot + restore to keep the test
        // isolated from prior runs on the same simulator.
        let priorClips = InboxManifest.shared.clips
        let priorDismissed = InboxManifest.shared.dismissedClusters
        InboxManifest.shared.debugReplaceClipsForTesting([])
        InboxManifest.shared.debugReplaceDismissedForTesting([])
        defer {
            InboxManifest.shared.debugReplaceDismissedForTesting(priorDismissed)
            InboxManifest.shared.debugReplaceClipsForTesting(priorClips)
        }

        let a = plantClip()
        let b = plantClip()
        let p = proposal(clipIds: [a, b])

        #expect(InboxManifest.shared.dismissedClusterFingerprints.contains(p.fingerprint) == false,
                "Pre-condition: fingerprint not yet dismissed")

        InboxManifest.shared.dismissCluster(p)

        #expect(InboxManifest.shared.dismissedClusterFingerprints.contains(p.fingerprint),
                "dismissCluster must add the fingerprint to the suppression set")

        InboxManifest.shared.remove(clipId: a)
        InboxManifest.shared.remove(clipId: b)
    }

    /// Field-observed bug (2026-07-11 screenshot): tapping
    /// **Not together** on a cluster card did nothing visible — the
    /// card stayed on screen. Root cause: `dismissedClusters` was
    /// not `@Published`, so mutating it never fired
    /// `objectWillChange`. `SessionListView` observes
    /// `InboxManifest.shared` via `@ObservedObject`; without a
    /// publisher fire, SwiftUI never re-rendered, so the
    /// `proposals` computed property never recomputed and the
    /// dismissed cluster stayed visible.
    ///
    /// Money-test invariant: `dismissCluster(_:)` must fire
    /// `objectWillChange` at least once. Before the fix, the count
    /// stays at `0`; after the fix (adding `@Published` to
    /// `dismissedClusters`) the count is `≥ 1`.
    @Test
    func dismissCluster_firesObjectWillChange_soSwiftUIRerenders() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }

        let priorClips = InboxManifest.shared.clips
        let priorDismissed = InboxManifest.shared.dismissedClusters
        InboxManifest.shared.debugReplaceClipsForTesting([])
        InboxManifest.shared.debugReplaceDismissedForTesting([])
        defer {
            InboxManifest.shared.debugReplaceDismissedForTesting(priorDismissed)
            InboxManifest.shared.debugReplaceClipsForTesting(priorClips)
        }

        let a = plantClip()
        let b = plantClip()
        let p = proposal(clipIds: [a, b])

        // Subscribe AFTER setup so only the dismissCluster call
        // is measured.
        var fireCount = 0
        let cancellable = InboxManifest.shared.objectWillChange.sink { _ in
            fireCount += 1
        }
        defer { cancellable.cancel() }

        InboxManifest.shared.dismissCluster(p)

        #expect(fireCount >= 1,
                "dismissCluster must fire objectWillChange so SessionListView re-renders and the dismissed cluster disappears from the workbench")

        InboxManifest.shared.remove(clipId: a)
        InboxManifest.shared.remove(clipId: b)
    }

    /// Dismissing the same proposal twice is a no-op — the second
    /// call must not double-store.
    @Test
    func dismiss_isIdempotent() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }

        let priorClips = InboxManifest.shared.clips
        let priorDismissed = InboxManifest.shared.dismissedClusters
        InboxManifest.shared.debugReplaceClipsForTesting([])
        InboxManifest.shared.debugReplaceDismissedForTesting([])
        defer {
            InboxManifest.shared.debugReplaceDismissedForTesting(priorDismissed)
            InboxManifest.shared.debugReplaceClipsForTesting(priorClips)
        }

        let a = plantClip()
        let b = plantClip()
        let p = proposal(clipIds: [a, b])

        InboxManifest.shared.dismissCluster(p)
        InboxManifest.shared.dismissCluster(p)
        InboxManifest.shared.dismissCluster(p)

        #expect(InboxManifest.shared.dismissedClusters.count == 1,
                "Idempotent dismiss — three calls must produce one record; got \(InboxManifest.shared.dismissedClusters.count)")

        InboxManifest.shared.remove(clipId: a)
        InboxManifest.shared.remove(clipId: b)
    }

    // MARK: - Prune-on-write

    /// When a clipId in a dismissed cluster leaves the inbox, the
    /// dismissal record becomes dead weight (the fingerprint can
    /// never match a future proposal) and must be pruned. Money
    /// test for Tom's Q3 answer.
    @Test
    func placedClip_prunesItsDismissedRecords() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }

        let priorClips = InboxManifest.shared.clips
        let priorDismissed = InboxManifest.shared.dismissedClusters
        InboxManifest.shared.debugReplaceClipsForTesting([])
        InboxManifest.shared.debugReplaceDismissedForTesting([])
        defer {
            InboxManifest.shared.debugReplaceDismissedForTesting(priorDismissed)
            InboxManifest.shared.debugReplaceClipsForTesting(priorClips)
        }

        let a = plantClip()
        let b = plantClip()
        let p = proposal(clipIds: [a, b])
        InboxManifest.shared.dismissCluster(p)
        #expect(InboxManifest.shared.dismissedClusters.count == 1)

        // "Place" clip A — remove it from the inbox. The dismissal
        // record containing A now has a missing member and is
        // dead; prune-on-write must drop it.
        InboxManifest.shared.remove(clipId: a)

        #expect(InboxManifest.shared.dismissedClusters.isEmpty,
                "Prune-on-write must drop records whose clipIds are no longer all in the inbox")
        #expect(InboxManifest.shared.dismissedClusterFingerprints.isEmpty)

        InboxManifest.shared.remove(clipId: b)
    }

    /// An untouched cluster (all clipIds still in the inbox) must
    /// survive prune-on-write. Guard against over-pruning.
    @Test
    func liveCluster_survivesPrune() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }

        let priorClips = InboxManifest.shared.clips
        let priorDismissed = InboxManifest.shared.dismissedClusters
        InboxManifest.shared.debugReplaceClipsForTesting([])
        InboxManifest.shared.debugReplaceDismissedForTesting([])
        defer {
            InboxManifest.shared.debugReplaceDismissedForTesting(priorDismissed)
            InboxManifest.shared.debugReplaceClipsForTesting(priorClips)
        }

        let a = plantClip()
        let b = plantClip()
        let c = plantClip()

        // Dismiss cluster (a, b). Then place clip C. The (a, b)
        // record still has all members present → must NOT prune.
        InboxManifest.shared.dismissCluster(proposal(clipIds: [a, b]))
        InboxManifest.shared.remove(clipId: c)

        #expect(InboxManifest.shared.dismissedClusters.count == 1,
                "Untouched dismissal must survive a peer-clip placement")

        InboxManifest.shared.remove(clipId: a)
        InboxManifest.shared.remove(clipId: b)
    }
}
