import Testing
import Foundation
@testable import HiMem

/// Money tests for `WatchSessionDelegate.shouldDropArrivedMaster` —
/// the consolidated idempotency gate that replaces the
/// three-layer dedup in `acceptArrivedClip`.
///
/// **What this replaces.** Before Step F the function ran:
///   1. `AcceptanceCriticalSection.tryEnter` — still here for the
///      concurrent-actor race (§ 8.2).
///   2. `isMasterAlreadyProcessed` — clipId-match OR
///      rollGroupId-match against active manifest clips.
///   3. (Step C era) `InboxProcessedClipIds.contains` — B5
///      tombstone check against a separate persistent set.
///
/// **What it is now.** One pure function over `(manifestStatusForClipId,
/// rollGroupIdAlreadyInUse)`. The single status field on `InboxClip`
/// — `.announced` / `.received` / `.transcribing` / `.transcribed` /
/// `.disposed` — is the authoritative answer. Combined with a single
/// rollGroupId-already-known query against the manifest (active +
/// tombstones), the decision is a two-line predicate.
///
/// Eliminates the bug surface from §§ 7.3 / 8.1 / 8.2 / 8.6 of
/// `docs/architecture/Captured Clips · watch-to-phone sync system.md`
/// by construction — see also `SplitIdempotencyTests` and
/// `WatchAckRollGroupTests`.
struct AcceptArrivedClipTests {

    /// Pre-announce row exists but the master file hasn't arrived
    /// yet → status is `.announced`. The arriving master IS the file
    /// the pre-announce was about, so we proceed.
    @Test func shouldDropArrivedMaster_statusAnnounced_returnsFalse() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: .announced,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == false)
    }

    /// A second delivery for the same clipId after the manifest
    /// already accepted the file → drop. Catches the in-flight
    /// double-delivery scenario where iOS WC layer hands us the
    /// same file twice in quick succession.
    @Test func shouldDropArrivedMaster_statusReceived_returnsTrue() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: .received,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == true)
    }

    @Test func shouldDropArrivedMaster_statusTranscribing_returnsTrue() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: .transcribing,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == true)
    }

    @Test func shouldDropArrivedMaster_statusTranscribed_returnsTrue() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: .transcribed,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == true)
    }

    /// The B5 case (§ 7.3) — user disposed of the clip and iOS is
    /// ghost-redelivering it from its system WC queue hours/days
    /// later. The tombstone catches it.
    @Test func shouldDropArrivedMaster_statusDisposed_returnsTrue() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: .disposed,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == true)
    }

    /// Master arrives with a rollGroupId that the manifest already
    /// has split children for. After Step A made splits idempotent
    /// the redundant work is correct (same UUIDs), so this is an
    /// efficiency drop, not a correctness one. Either way we don't
    /// want to do the work twice.
    @Test func shouldDropArrivedMaster_rollGroupAlreadyInUse_returnsTrue() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: nil,
            rollGroupIdAlreadyInUse: true
        )
        #expect(drop == true)
    }

    /// Fresh master, never seen — proceed.
    @Test func shouldDropArrivedMaster_freshClipId_andNoRollGroup_returnsFalse() {
        let drop = WatchSessionDelegate.shouldDropArrivedMaster(
            manifestStatusForClipId: nil,
            rollGroupIdAlreadyInUse: false
        )
        #expect(drop == false)
    }

    // MARK: - InboxManifest.isRollGroupKnown coverage

    @Test @MainActor func isRollGroupKnown_matchInActiveClips_returnsTrue() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        let rollGroupId = UUID()
        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test.caf",
            transcriptionAttempted: false,
            rollGroupId: rollGroupId,
            status: .received,
            disposedAt: nil
        )
        manifest.debugReplaceClipsForTesting(prior + [clip])
        #expect(manifest.isRollGroupKnown(rollGroupId))
    }

    @Test @MainActor func isRollGroupKnown_matchInDisposedTombstone_returnsTrue() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        let rollGroupId = UUID()
        let tombstone = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "",
            transcriptionAttempted: false,
            rollGroupId: rollGroupId,
            status: .disposed,
            disposedAt: Date()
        )
        manifest.debugReplaceClipsForTesting(prior + [tombstone])
        #expect(manifest.isRollGroupKnown(rollGroupId))
    }

    @Test @MainActor func isRollGroupKnown_noMatch_returnsFalse() async {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips
        defer { manifest.debugReplaceClipsForTesting(prior) }
        manifest.debugReplaceClipsForTesting(prior)
        #expect(manifest.isRollGroupKnown(UUID()) == false)
    }
}
