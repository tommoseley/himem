import Testing
import Foundation
import CoreData
@testable import HiMem

/// **THE MONEY TESTS for the 2026-09-22 data loss.**
///
/// Tom deleted a batch of old test memories and emptied Recently Deleted. At
/// 10:10:46 the iCloud container reported **184 deleted `.caf` items**, and the
/// audio directory went from ~190 files to zero. At least 99 of them were
/// referenced by live memories.
///
/// ## The compound state nothing checked
///
/// `recycle(entryId:)` is correct on its own — it retires a part only when
/// this memory is its *last* edge (`edgeCount == 1`). And `recycleClip` is
/// correct on its own: it sets `recycledAt` and **deliberately keeps the
/// edges**, so the part stays attached and is merely filtered out of composed
/// content.
///
/// Put together they permit a part that is **both recycled and still used by a
/// live memory** — recycled at some point in the past, then attached to
/// another memory afterwards (which many-to-many explicitly allows since F2
/// retired). `purgeExpiredRecycledClips` then destroys it, because it selects
/// on **age alone and never asks whether anything still points at it.**
///
/// > The purge cannot distinguish an orphan from referenced audio, because it
/// > never asks.
///
/// The memory survives and keeps its edge; the audio it names is gone.
///
/// **The predicate already existed.** `MediaReference.referencingMemoryCount`
/// counts memories that are not themselves recycled — exactly "is anything
/// live still using this". Nothing on the destruction path consulted it.
@MainActor
@Suite(.serialized)
struct PurgeMustNotTakeLiveAudioTests {

    // MARK: - Fixtures

    private func makeStorage() -> StorageService { StorageService(inMemory: true) }

    /// A part with a REAL file behind it, so "was the audio destroyed" is a
    /// question about the filesystem rather than about a flag.
    private func makeVoicePart(_ storage: StorageService,
                               in entry: JournalEntry,
                               name: String = "purge-\(UUID().uuidString).caf") throws -> (MediaReference, URL) {
        let ref = try storage.createVoiceFragment(for: entry, audioFilename: name, transcript: "her words")
        try storage.viewContext.save()
        let url = UbiquityStore.shared.audioURL(for: name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data("audio bytes".utf8).write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path), "precondition: the audio exists")
        return (ref, url)
    }

    private func makeMemory(_ storage: StorageService, _ title: String) throws -> JournalEntry {
        let e = try storage.createEntry(content: "", inputType: .typed)
        e.title = title
        try storage.viewContext.save()
        return e
    }

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    // MARK: - The money test

    /// **Exactly what happened.** A part recycled long ago is still attached to
    /// a live memory. Emptying Recently Deleted must not destroy its audio.
    @Test("emptying the bin never destroys audio a live memory still uses")
    func purgeSparesAudioALiveMemoryUses() throws {
        let storage = makeStorage()
        let lifecycle = EntryLifecycleService(storage: storage)

        let kept = try makeMemory(storage, "Global cuisine dinner")
        let (part, url) = try makeVoicePart(storage, in: kept)

        // Recycled 60 days ago — past the 30-day window — while `kept` still
        // references it. `recycleClip` preserves edges by design.
        part.recycledAt = daysAgo(60)
        try storage.viewContext.save()
        #expect(part.referencingMemoryCount == 1, "precondition: a live memory still uses it")

        lifecycle.purgeExpiredRecycledClips()

        #expect(FileManager.default.fileExists(atPath: url.path), """
            The 30-day purge destroyed audio that a LIVE memory still references. \
            This is the 2026-09-22 loss: the purge selects on age alone and never \
            asks whether anything still points at the file.
            """)
        try? FileManager.default.removeItem(at: url)
    }

    /// **Tom's scenario, end to end.** Old test memories deleted, the bin
    /// emptied, while other memories still reference the same parts.
    @Test("deleting old memories then emptying the bin spares the shared parts")
    func sharedPartsSurviveTheOldMemoryPurge() throws {
        let storage = makeStorage()
        let lifecycle = EntryLifecycleService(storage: storage)

        let old = try makeMemory(storage, "Old test memory")
        let live = try makeMemory(storage, "Judi at the market")
        let (shared, sharedURL) = try makeVoicePart(storage, in: old)
        let (onlyOld, onlyOldURL) = try makeVoicePart(storage, in: old)

        // The shared part is in BOTH — the ordinary M:M shape since F2 retired.
        try StorageService.createEdge(from: live, to: shared, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(shared.edgeCount == 2)

        // Delete the old memory. P8 retires only the part whose last edge it was.
        lifecycle.recycle(entryId: old.id)
        #expect(onlyOld.recycledAt != nil, "the part only the old memory used is retired with it")
        #expect(shared.recycledAt == nil, "a part used elsewhere must not be retired")

        // Age both past the window, then empty the bin.
        onlyOld.recycledAt = daysAgo(60)
        shared.recycledAt = daysAgo(60)   // the compound state the purge ignores
        try storage.viewContext.save()
        lifecycle.purgeExpiredRecycledClips()

        #expect(FileManager.default.fileExists(atPath: sharedURL.path), """
            Audio still used by "Judi at the market" was destroyed by emptying \
            the bin. Deleting one memory must never take audio another still uses.
            """)
        #expect(live.edgesArray.contains { $0.clipId == shared.id },
                "and the live memory must still hold its edge")
        try? FileManager.default.removeItem(at: sharedURL)
        try? FileManager.default.removeItem(at: onlyOldURL)
    }

    /// **The purge must still do its job.** A genuinely unreferenced part, past
    /// the window, is destroyed — otherwise the fix is a leak wearing a
    /// safety's clothes.
    @Test("a genuinely orphaned part is still purged")
    func orphanedPartIsStillPurged() throws {
        let storage = makeStorage()
        let lifecycle = EntryLifecycleService(storage: storage)

        let doomed = try makeMemory(storage, "Doomed")
        let (part, url) = try makeVoicePart(storage, in: doomed)
        lifecycle.recycle(entryId: doomed.id)
        doomed.isRecycled = true
        part.recycledAt = daysAgo(60)
        try storage.viewContext.save()
        #expect(part.referencingMemoryCount == 0, "precondition: nothing live points at it")

        lifecycle.purgeExpiredRecycledClips()

        #expect(!FileManager.default.fileExists(atPath: url.path),
                "an orphan past the window must still be destroyed — the purge has a job")
    }

    /// A part inside the window is untouched whatever its edges.
    @Test("a recently recycled part is not purged early")
    func recentlyRecycledIsNotPurged() throws {
        let storage = makeStorage()
        let lifecycle = EntryLifecycleService(storage: storage)
        let m = try makeMemory(storage, "Yesterday")
        let (part, url) = try makeVoicePart(storage, in: m)
        part.recycledAt = daysAgo(3)
        try storage.viewContext.save()

        lifecycle.purgeExpiredRecycledClips()
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    /// **Empty Recently Deleted obeys the same rule as the sweep**, because
    /// it is the path that actually caused the loss. An explicit single
    /// *Delete this Clip* does not — she chose that part having been told what
    /// it holds, and `DeletionSemanticsTests` pins that locked behaviour.
    @Test("a bulk Delete All Forever spares audio a live memory still uses")
    func explicitPurgeSparesLiveAudio() throws {
        let storage = makeStorage()
        let lifecycle = EntryLifecycleService(storage: storage)
        let live = try makeMemory(storage, "Still here")
        let (part, url) = try makeVoicePart(storage, in: live)
        part.recycledAt = daysAgo(1)
        try storage.viewContext.save()

        lifecycle.purgeClip(refId: part.id, sparingLiveReferences: true)

        #expect(FileManager.default.fileExists(atPath: url.path), """
            Delete Forever destroyed audio a live memory still references. The \
            sweep and the button must obey the same rule.
            """)
        try? FileManager.default.removeItem(at: url)
    }
}
