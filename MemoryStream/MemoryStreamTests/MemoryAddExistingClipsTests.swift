import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the Memory Detail "Add existing clips" FAB path
/// (`Memory Detail · unified editing model.md` §"Adding clips to a
/// memory"). Inside a memory, the `+` offers two paths: capture a new
/// clip (the existing modality stack) OR add existing loose clips from
/// the bench. This suite covers the second path — attaching existing
/// `MediaReference`s via new `MemoryClipEdge`s in append order, with
/// content regeneration and **no auto-reorganize**.
@MainActor
@Suite(.serialized)
struct MemoryAddExistingClipsTests {

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    /// An organized memory with one original clip captured *before* the
    /// organize watermark — so it starts NOT stale.
    private func seedOrganizedMemory(in storage: StorageService, organizedAt: Date) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = "Dinner"
        _ = try storage.createVoiceFragment(
            for: entry,
            audioFilename: "orig.caf",
            transcript: "the original clip",
            createdAt: organizedAt.addingTimeInterval(-60)
        )
        entry.content = EntryLifecycleService.joinedContent(from: entry)
        entry.lastOrganizedAt = organizedAt
        try storage.viewContext.save()
        return entry
    }

    /// A loose bench clip: a `MediaReference` with no edges, not
    /// recycled, captured in the past.
    private func makeLooseClip(in storage: StorageService, filename: String, transcript: String, createdAt: Date) throws -> MediaReference {
        let ref = MediaReference(context: storage.viewContext)
        ref.id = UUID()
        ref.osIdentifier = filename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.transcript = transcript
        ref.isAccessible = true
        ref.createdAt = createdAt
        try storage.viewContext.save()
        return ref
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let r = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try? storage.viewContext.fetch(r).first
    }

    // MARK: - Cycle 1: staleness must key off the edge, not clip.createdAt

    /// **The money test.** Attaching an *existing* clip (captured long
    /// ago, so `ref.createdAt < lastOrganizedAt`) to an organized memory
    /// must mark that memory stale — "identical to new clips arriving"
    /// (`Memory Detail · unified editing model.md` §Moving clips). Before
    /// the fix, `clipsAddedSinceLastOrganize` keyed off `ref.createdAt`,
    /// so an old clip attached *today* counted as zero and the memory
    /// never offered Reorganize — the new clip's words silently stayed
    /// out of the title/summary with no user path to fold them in.
    ///
    /// Reproduced with `createEdge` directly (the primitive every attach
    /// path shares) so the failure is unambiguously in the staleness
    /// derivation, not the higher-level service.
    @Test func attachingExistingOldClipViaEdge_marksMemoryStale() throws {
        let storage = StorageService(inMemory: true)
        let organizedAt = Date()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: organizedAt)
        #expect(entry.hasChangesSinceLastOrganize == false, "A freshly organized memory is not stale")

        let old = try makeLooseClip(
            in: storage,
            filename: "loose.caf",
            transcript: "a thought from last week",
            createdAt: organizedAt.addingTimeInterval(-7 * 86_400)
        )

        // Attach today: the edge's linkedAt (now) is the "added to THIS
        // memory" event — well past the organize watermark.
        try StorageService.createEdge(from: entry, to: old, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()

        #expect(entry.clipsAddedSinceLastOrganize == 1, "An old clip attached AFTER the organize is new to THIS memory")
        #expect(entry.hasChangesSinceLastOrganize == true, "Attaching an existing clip must mark the memory stale so it offers Reorganize")
    }

    // MARK: - Cycle 2: the attachExistingClips primitive

    /// Attaches two loose clips and asserts: edges land in append order
    /// (after the memory's original clip), `entry.content` regenerates to
    /// include the new transcripts, and one evidence record per clip
    /// (no duplication — the clip is stored once, cited by an edge).
    @Test func attachExistingClips_createsEdgesInAppendOrder_regeneratesContent() throws {
        let (storage, service) = makeService()
        let organizedAt = Date()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: organizedAt)
        #expect(entry.edgesArray.count == 1)

        let a = try makeLooseClip(in: storage, filename: "a.caf", transcript: "first added", createdAt: organizedAt.addingTimeInterval(-200))
        let b = try makeLooseClip(in: storage, filename: "b.caf", transcript: "second added", createdAt: organizedAt.addingTimeInterval(-100))

        let n = service.attachExistingClips(entryId: entry.id, clipIds: [a.id, b.id])
        #expect(n == 2)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        // Append order: original, then a, then b.
        let orderedIds = refreshed.edgesArray.map { $0.clip?.osIdentifier }
        #expect(orderedIds == ["orig.caf", "a.caf", "b.caf"], "New clips attach after the memory's existing clips, in the order given")
        // orderInMemory is strictly increasing in append order. (Absolute
        // values are 1-based — `createEdge` reads `edgesArray.count` after
        // the edge is already inserted via its inverse relationship; only
        // relative order is load-bearing, since `edgesArray` sorts by it.)
        let orders = refreshed.edgesArray.map { $0.orderInMemory }
        #expect(orders == orders.sorted() && Set(orders).count == orders.count, "Append order is strictly increasing")

        // Evidence stored once — attaching does not clone the ref.
        let allRefs = try storage.viewContext.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(allRefs.count == 3, "Original + 2 attached, each stored once")

        // Content regenerated to the joined transcripts in edge order.
        #expect(refreshed.content == "the original clip\n\nfirst added\n\nsecond added")
    }

    /// Spec (`Memory Detail · unified editing model.md` §"Adding clips
    /// to a memory"): "New clips append in `orderInMemory`/**capturedAt**
    /// order" — chronological bulk-append, NOT the
    /// order the user happened to tap them. Select newer-then-older; they
    /// must still land oldest-first after the memory's existing clips.
    @Test func attachExistingClips_appendsInCapturedAtOrder_notTapOrder() throws {
        let (storage, service) = makeService()
        let organizedAt = Date()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: organizedAt)

        // older = -300, newer = -100.
        let older = try makeLooseClip(in: storage, filename: "older.caf", transcript: "older", createdAt: organizedAt.addingTimeInterval(-300))
        let newer = try makeLooseClip(in: storage, filename: "newer.caf", transcript: "newer", createdAt: organizedAt.addingTimeInterval(-100))

        // User taps NEWER first, then OLDER.
        let n = service.attachExistingClips(entryId: entry.id, clipIds: [newer.id, older.id])
        #expect(n == 2)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        let orderedIds = refreshed.edgesArray.map { $0.clip?.osIdentifier }
        #expect(orderedIds == ["orig.caf", "older.caf", "newer.caf"], "Appended clips order by capturedAt, not tap order")
    }

    /// The regression guard: `attachExistingClips` must NOT queue a
    /// ProcessingTask. If someone "simplifies" it onto `append()`, this
    /// fails — `append()` reprocesses and (on Plus) auto-organizes,
    /// which the Add-clips path explicitly forbids.
    @Test func attachExistingClips_doesNotQueueProcessingTask() throws {
        let (storage, service) = makeService()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: Date())
        let clip = try makeLooseClip(in: storage, filename: "x.caf", transcript: "x", createdAt: Date().addingTimeInterval(-500))

        service.attachExistingClips(entryId: entry.id, clipIds: [clip.id])

        let req = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        req.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let tasks = try storage.viewContext.fetch(req)
        #expect(tasks.isEmpty, "attachExistingClips must not queue a ProcessingTask — Reorganize is user-tap-only")
    }

    /// Re-attaching an already-attached clip is a no-op — no duplicate
    /// edge, count reflects only the newly added.
    @Test func attachExistingClips_isIdempotent() throws {
        let (storage, service) = makeService()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: Date())
        let clip = try makeLooseClip(in: storage, filename: "dup.caf", transcript: "once", createdAt: Date().addingTimeInterval(-500))

        let first = service.attachExistingClips(entryId: entry.id, clipIds: [clip.id])
        #expect(first == 1)
        let second = service.attachExistingClips(entryId: entry.id, clipIds: [clip.id])
        #expect(second == 0, "Re-attaching the same clip is a no-op")

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        let dupEdges = refreshed.edgesArray.filter { $0.clip?.osIdentifier == "dup.caf" }
        #expect(dupEdges.count == 1, "No duplicate edge for a re-attached clip")
    }

    /// A recycled clip (in Recently Deleted) is never attachable — the
    /// bench picker excludes it, and the primitive guards regardless.
    @Test func attachExistingClips_skipsRecycledClip() throws {
        let (storage, service) = makeService()
        let entry = try seedOrganizedMemory(in: storage, organizedAt: Date())
        let clip = try makeLooseClip(in: storage, filename: "gone.caf", transcript: "gone", createdAt: Date().addingTimeInterval(-500))
        clip.recycledAt = Date()
        try storage.viewContext.save()

        let n = service.attachExistingClips(entryId: entry.id, clipIds: [clip.id])
        #expect(n == 0, "A recycled clip is not attachable")
    }

    @Test func attachExistingClips_missingEntry_returnsZero() throws {
        let (_, service) = makeService()
        #expect(service.attachExistingClips(entryId: UUID(), clipIds: [UUID()]) == 0)
    }
}
