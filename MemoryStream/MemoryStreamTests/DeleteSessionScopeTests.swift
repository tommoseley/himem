import Testing
import Foundation
@testable import HiMem

/// **"Delete session" destroys everything the card DRAWS** (ruled 2026-08-19).
///
/// If the card shows a photo, deleting the session deletes the photo. This
/// previously removed the session's voice clips and left its absorbed media
/// sitting on the bench — the count-describes-a-different-set class in its
/// destructive form. The user deletes what they see, not what we internally
/// scope to voice.
///
/// These cover the **scope** half: which ids are destroyed, and down which
/// backing. The **route** half — that they land in Recently Deleted and come
/// back — lives in `InboxClipRecycleTests`, the suite that owns the manifest
/// singleton and its cleanup discipline.
///
/// Deliberately free of Core Data and of `InboxManifest.shared`:
/// `recycleTargets` is a pure function of ids, so it needs neither, and B24
/// (an undiagnosed intermittent host crash whose stated suspect is a growing
/// number of parallel in-memory stores) is a reason not to add one for
/// decoration. That the card draws both kinds is `ResolvedSessionTests`' job.
struct DeleteSessionScopeTests {

    private func clip(_ id: UUID) -> InboxClip {
        InboxClip(
            clipId: id,
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            duration: 30,
            transcript: "t",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(id).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
    }

    /// **The money test for the ruling: the photo is in the destroyed set.**
    @Test
    func deletingAMixedSessionDestroysItsPhotoAsWellAsItsVoice() {
        let voiceId = UUID()
        let photoId = UUID()

        let targets = SessionListView.recycleTargets(
            itemIds: [voiceId, photoId],
            manifestClips: [clip(voiceId)]
        )

        #expect(targets.clipIds == [voiceId], "the voice clip is a manifest row and recycles through the manifest")
        #expect(targets.refIds == [photoId],
                "the PHOTO must be destroyed too — deleting a session used to leave it on the bench, so the user deleted what they saw and found it still there")
        // Covering and disjoint: every drawn item is destroyed exactly once.
        #expect(Set(targets.clipIds).union(targets.refIds) == [voiceId, photoId])
        #expect(Set(targets.clipIds).isDisjoint(with: targets.refIds))
    }

    /// A materialized VOICE clip is a ref, not a manifest row — the partition
    /// is over **backing**, never over kind (P0-3). Without this, a clip that
    /// had been materialized would go to the manifest recycler, which no-ops on
    /// an id it has no row for: a silent failure to delete, which is the
    /// `markSessionReviewed` defect in destructive form.
    @Test
    func aMaterializedVoiceClipTakesTheRefBranchNotTheManifestBranch() {
        let manifestVoice = UUID()
        let materializedVoice = UUID()

        let targets = SessionListView.recycleTargets(
            itemIds: [manifestVoice, materializedVoice],
            manifestClips: [clip(manifestVoice)]
        )

        #expect(targets.clipIds == [manifestVoice])
        #expect(targets.refIds == [materializedVoice],
                "a materialized clip is a ref; routing it to the manifest recycler is a silent no-op")
    }

    /// Both empty directions, so the partition cannot be a constant that
    /// happens to read right — a split that sent everything down one branch
    /// would satisfy a one-sided check while failing half the bench.
    @Test
    func aVoiceOnlySessionMakesNoRefWorkAndAMediaOnlySessionMakesNoManifestWork() {
        let voiceId = UUID()
        let refId = UUID()
        let manifest = [clip(voiceId)]

        let voiceOnly = SessionListView.recycleTargets(itemIds: [voiceId], manifestClips: manifest)
        #expect(voiceOnly.clipIds == [voiceId])
        #expect(voiceOnly.refIds.isEmpty)

        let mediaOnly = SessionListView.recycleTargets(itemIds: [refId], manifestClips: manifest)
        #expect(mediaOnly.clipIds.isEmpty)
        #expect(mediaOnly.refIds == [refId])
    }
}
