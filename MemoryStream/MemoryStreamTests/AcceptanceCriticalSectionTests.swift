import Testing
import Foundation
@testable import HiMem

/// Money tests for the per-clipId critical section guarding
/// `acceptArrivedClip` against the double-delivery race documented
/// in § 8.2 of the system reference doc.
///
/// THE BUG: `acceptArrivedClip` awaits on VoiceClipSplitter.split
/// and AudioCompressor.compressInPlace — both release @MainActor.
/// Two concurrent Tasks for the same master clipId can both pass
/// `isMasterAlreadyProcessed` (manifest still empty at check time)
/// before either writes to the manifest. Each then splits into N
/// child fragments with fresh UUIDs. User sees duplicate clips.
/// Tom hit this in QA 2026-05-29 (one unsplit + four split clips,
/// each appearing twice).
///
/// THE FIX: a small @MainActor set of currently-processing clipIds.
/// Second concurrent entry for the same clipId is rejected with a
/// no-op + ack. Set entries clear on every exit (success or throw)
/// via `defer` in `acceptArrivedClip`. These tests lock the
/// contract: enter/exit semantics, re-entry safety, multi-clip
/// independence.
@MainActor
@Suite(.serialized)
struct AcceptanceCriticalSectionTests {

    private func freshSection() {
        #if DEBUG
        AcceptanceCriticalSection.debugResetForTesting()
        #endif
    }

    @Test func tryEnter_succeedsOnEmptySet() {
        freshSection()
        let id = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id))
    }

    // MARK: - Redelivered-master reclaim · both directions
    //
    // The referencedness check the original unconditional delete should have
    // had. Removing that delete outright (the fix above) closed a data-loss
    // path but left a narrower regression: a SPLIT clip's redelivered master
    // is unreferenced, and nothing reclaims it — `MediaBlobOrphanSweep` is
    // deliberately disabled (F23 T1.1, guarded by
    // `OrphanSweepReachabilityTests`) because its keep-set cannot see another
    // device's staged clips. Both directions are tested so the data-loss
    // direction is pinned by test, not by care.
    //
    // Correction (2026-07-31): this comment previously said the sweep "is not
    // wired to anything." It WAS wired, via Settings Debug. The claim came
    // from a grep for `.orphans(` that could not have matched the production
    // `plan()`/`execute()` calls — a retracted premise, propagated here.

    /// THE DATA-LOSS DIRECTION. A single clip's master file *is* the clip's
    /// audio, so a manifest row references it and it must survive a rejected
    /// redelivery. This is the direction that loses a recording if it regresses.
    @Test func referencedMaster_isNeverReclaimed() {
        let filename = "\(UUID().uuidString).caf"
        #expect(
            WatchSessionDelegate.shouldReclaimRedeliveredMaster(
                masterFilename: filename,
                referencedFilenames: [filename]
            ) == false,
            "Reclaimed a master a manifest row still points at — that is the clip's audio (storage lock)"
        )
    }

    /// THE RESIDUE DIRECTION. A split clip's master was consumed into N
    /// fragments with fresh UUIDs, so nothing references it; a redelivered copy
    /// is an unreferenced blob in the user's iCloud container and is reclaimed.
    @Test func unreferencedMaster_isReclaimed() {
        let master = "\(UUID().uuidString).caf"
        let fragments: Set<String> = ["\(UUID().uuidString).caf", "\(UUID().uuidString).caf"]
        #expect(
            WatchSessionDelegate.shouldReclaimRedeliveredMaster(
                masterFilename: master,
                referencedFilenames: fragments
            ) == true,
            "Left an unreferenced master on disk — orphan residue in the user's iCloud container"
        )
    }

    /// THE WIRING REPRODUCTION. The predicate above is only worth anything if
    /// `acceptArrivedClip` consults it. Drives the real split-redelivery shape:
    /// a fragment row already holds the rollGroupId (so `shouldDropArrivedMaster`
    /// fires via `rollGroupIdAlreadyInUse`) and its `audioFilename` is a fresh
    /// UUID, so the master filename is referenced by nothing. The re-copied
    /// master must be reclaimed rather than left as residue in the user's
    /// iCloud container.
    @Test func splitRedelivery_reclaimsTheUnreferencedMaster() async throws {
        freshSection()
        let masterClipId = UUID()
        let rollGroupId = UUID()
        let masterFilename = "\(masterClipId.uuidString).caf"
        let masterURL = InboxManifest.audioURL(for: masterFilename)

        // A surviving fragment from the earlier split: same rollGroup, its own
        // filename. This is what makes the master unreferenced.
        let fragment = InboxClip(
            clipId: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_785_000_000),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(UUID().uuidString).caf",
            rollGroupId: rollGroupId
        )
        InboxManifest.shared.acceptClip(fragment)
        defer { InboxManifest.shared.remove(clipId: fragment.clipId) }

        try FileManager.default.createDirectory(
            at: masterURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("redelivered-master".utf8).write(to: masterURL)
        defer { try? FileManager.default.removeItem(at: masterURL) }

        let metadata = ClipMetadata(
            clipId: masterClipId,
            capturedAt: Date(timeIntervalSince1970: 1_785_000_000),
            duration: 21.6,
            transcript: "",
            rollGroupId: rollGroupId
        )
        await WatchSessionDelegate.acceptArrivedClip(metadata: metadata, masterFilename: masterFilename)

        #expect(
            !FileManager.default.fileExists(atPath: masterURL.path),
            "Unreferenced redelivered master left on disk — orphan residue, and MediaBlobOrphanSweep is deliberately disabled (F23 T1.1), so nothing else will collect it"
        )
    }

    /// A recycled (soft-deleted, restorable) clip still counts as referenced —
    /// its bytes must survive the 30-day window.
    @Test func recycledClipsMasterIsStillReferenced() {
        let filename = "\(UUID().uuidString).caf"
        let referenced: Set<String> = [filename, "\(UUID().uuidString).caf"]
        #expect(WatchSessionDelegate.shouldReclaimRedeliveredMaster(
            masterFilename: filename, referencedFilenames: referenced
        ) == false)
    }

    /// An empty keep-set must not be read as "everything is referenced" — a
    /// fresh manifest with a stray blob still reclaims.
    @Test func emptyReferenceSet_reclaims() {
        #expect(WatchSessionDelegate.shouldReclaimRedeliveredMaster(
            masterFilename: "\(UUID().uuidString).caf", referencedFilenames: []
        ) == true)
    }

    /// THE DATA-LOSS MONEY ASSERTION (dogfood 2026-07-29).
    ///
    /// Rejecting a redelivered master must **never** delete the master file.
    /// Every delivery of a clip copies to the SAME canonical path
    /// (`InboxManifest.audioURL(for: "<clipId>.caf")`) and the copy is
    /// idempotent — `if !fileExists { copy } else { skip }` — so there is
    /// never a second, redundant file to reclaim. The old "drop the
    /// redelivered master file so disk doesn't bloat" delete therefore could
    /// only destroy the *live* audio of the clip already accepted.
    ///
    /// Observed: one clip delivered four times; delivery #2 hit this branch
    /// and deleted the master, so transcription failed with
    /// `kAudio_FileNotFoundError` and only recovered because delivery #4
    /// happened to re-copy the bytes. Had that been the last delivery, the
    /// recording was gone — a direct violation of the storage lock, under
    /// which audio is the source of truth and the transcript is derivative.
    @Test func rejectedRedelivery_doesNotDeleteTheMasterAudio() async throws {
        freshSection()
        let clipId = UUID()
        let filename = "\(clipId.uuidString).caf"
        let url = InboxManifest.audioURL(for: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("master-audio-bytes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Hold the section so `acceptArrivedClip` takes the rejected-redelivery
        // branch — the same branch delivery #2 hit on device.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: clipId) == true)
        defer { AcceptanceCriticalSection.exit(clipId: clipId) }

        let metadata = ClipMetadata(
            clipId: clipId,
            capturedAt: Date(timeIntervalSince1970: 1_785_000_000),
            duration: 21.6,
            transcript: ""
        )
        await WatchSessionDelegate.acceptArrivedClip(metadata: metadata, masterFilename: filename)

        #expect(
            FileManager.default.fileExists(atPath: url.path),
            "Rejected redelivery deleted the live audio of an already-accepted clip — audio is the source of truth (storage lock)"
        )
    }

    /// THE BUG-FIX MONEY ASSERTION. A second tryEnter for the same
    /// clipId, while the first is still inside, must fail — that's
    /// what blocks the duplicate `acceptArrivedClip` race.
    @Test func tryEnter_failsOnConcurrentReentryForSameClipId() {
        freshSection()
        let id = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == false,
                "Second concurrent tryEnter for the same clipId must reject")
    }

    @Test func exit_allowsReentry() {
        freshSection()
        let id = UUID()
        _ = AcceptanceCriticalSection.tryEnter(clipId: id)
        AcceptanceCriticalSection.exit(clipId: id)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id) == false)
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true,
                "Re-entry after exit must succeed (next delivery of same clip)")
    }

    @Test func differentClipIds_doNotBlock() {
        freshSection()
        let a = UUID()
        let b = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: a) == true)
        // Concurrent processing of a different clip must proceed —
        // the section is per-clipId, not a global mutex. Multi-clip
        // sync bursts (the common case) must parallelize.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: b) == true)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: a))
        #expect(AcceptanceCriticalSection.isInFlight(clipId: b))
    }

    @Test func exitUntrackedClipId_isHarmless() {
        // Defensive: if a code path called exit without a matching
        // tryEnter (it shouldn't, but defer-only exit paths can be
        // tricky), the call must be a no-op rather than throwing or
        // corrupting state.
        freshSection()
        let id = UUID()
        AcceptanceCriticalSection.exit(clipId: id)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id) == false)
    }

    /// Simulates the realistic race: Task A calls tryEnter and
    /// (hypothetically) starts an await; Task B calls tryEnter for
    /// the same clipId before Task A's defer fires. Task B must be
    /// rejected. After Task A's defer, Task C arriving fresh for the
    /// same clipId (e.g., a much later re-delivery) succeeds. This
    /// is the exact lifecycle the fix locks.
    @Test func realisticConcurrentLifecycle() {
        freshSection()
        let id = UUID()
        // Task A entry.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        // Task B arrives mid-processing.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == false)
        // Task A finishes — defer fires.
        AcceptanceCriticalSection.exit(clipId: id)
        // Task C arrives much later (e.g., iOS re-delivers from queue).
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        AcceptanceCriticalSection.exit(clipId: id)
    }
}
