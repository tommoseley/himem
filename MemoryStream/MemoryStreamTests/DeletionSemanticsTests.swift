import Testing
import Foundation
import CoreData
@testable import HiMem

/// Phase 8 money tests for the delete verb split.
/// See `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`
/// § Phase 8.
///
/// Three verbs, three semantics:
/// - Remove-from-memory: drop one edge; clip survives.
/// - Delete-memory: cascade edges; clips survive as unplaced.
/// - Delete-clip: destroy evidence + cascade edges.
@MainActor
@Suite(.serialized)
struct DeletionSemanticsTests {

    private func makeStore() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    private func seedMemory(in storage: StorageService, title: String) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        try storage.viewContext.save()
        return entry
    }

    private func fetchRefs(in storage: StorageService) throws -> [MediaReference] {
        try storage.viewContext.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
    }

    private func fetchMemories(in storage: StorageService) throws -> [JournalEntry] {
        try storage.viewContext.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))
    }

    private func fetchEdges(in storage: StorageService) throws -> [MemoryClipEdge] {
        try storage.viewContext.fetch(NSFetchRequest<MemoryClipEdge>(entityName: "MemoryClipEdge"))
    }

    // MARK: - Remove-from-memory (drops one edge, clip survives)

    @Test func removeClipFromMemoryDropsEdgeOnly() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Memory A")
        let memB = try seedMemory(in: storage, title: "Memory B")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "shared.caf",
            transcript: "shared"
        )
        try StorageService.createEdge(from: memB, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        let edgeA = try #require(memA.edgesArray.first)
        service.removeClipFromMemory(edgeId: edgeA.id)

        // The ref survives.
        let refs = try fetchRefs(in: storage)
        #expect(refs.count == 1)
        // One edge remains — memB's.
        let edges = try fetchEdges(in: storage)
        #expect(edges.count == 1)
        #expect(edges.first?.memoryId == memB.id)
    }

    // MARK: - Delete-memory (edges cascade, clips survive)

    @Test func deleteMemoryCascadesEdgesButPreservesClips() throws {
        let (storage, service) = makeStore()
        let mem = try seedMemory(in: storage, title: "Doomed memory")
        _ = try storage.createVoiceFragment(for: mem, audioFilename: "a.caf", transcript: "a")
        _ = try storage.createVoiceFragment(for: mem, audioFilename: "b.caf", transcript: "b")

        service.delete(entryId: mem.id)

        // Clips survive.
        let refs = try fetchRefs(in: storage)
        #expect(refs.count == 2, "Deleting a memory must not destroy its clips — they return to Clips as unplaced evidence")
        // Edges are gone.
        let edges = try fetchEdges(in: storage)
        #expect(edges.isEmpty)
        // Memory is gone.
        let memories = try fetchMemories(in: storage)
        #expect(memories.isEmpty)
        // Each surviving ref has zero edges — the "returned to Clips" state.
        for ref in refs {
            #expect(ref.edgesArray.isEmpty)
        }
    }

    @Test func deleteMemoryPreservesClipsSharedWithOtherMemories() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Memory A")
        let memB = try seedMemory(in: storage, title: "Memory B")

        let shared = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "s.caf",
            transcript: "s"
        )
        try StorageService.createEdge(from: memB, to: shared, linkedAt: Date(), in: storage.viewContext)
        _ = try storage.createVoiceFragment(for: memA, audioFilename: "unique.caf", transcript: "u")
        try storage.save(context: storage.viewContext)

        service.delete(entryId: memA.id)

        let refs = try fetchRefs(in: storage)
        #expect(refs.count == 2, "Both clips survive — 'unique' as unplaced, 'shared' still attached to memB")
        let sharedRef = try #require(refs.first { $0.osIdentifier == "s.caf" })
        #expect(sharedRef.edgesArray.count == 1)
        #expect(sharedRef.edgesArray.first?.memoryId == memB.id)
    }

    // MARK: - Remove from this memory (edge-only, keyed by memory+clip)

    /// The `removeClipFromMemory(memoryId:refId:)` primitive drops the
    /// edge from the specified memory without touching the clip or any
    /// edges to other memories it's referenced from. Wired to the
    /// placement sheet's "Remove from this memory" destination
    /// (`Memory Detail · unified editing model.md:66`).
    @Test func removeClipFromMemoryByMemoryAndRefDropsOneEdgeOnly() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Memory A")
        let memB = try seedMemory(in: storage, title: "Memory B")
        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "shared.caf",
            transcript: "shared"
        )
        try StorageService.createEdge(from: memB, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        service.removeClipFromMemory(memoryId: memA.id, refId: ref.id)

        // Clip survives with one remaining edge (to memB).
        let refs = try fetchRefs(in: storage)
        #expect(refs.count == 1)
        #expect(refs.first?.referencingMemoryCount == 1)
        let edges = try fetchEdges(in: storage)
        #expect(edges.count == 1)
        #expect(edges.first?.memoryId == memB.id)
    }

    // MARK: - Delete-clip (destroys evidence, cascades edges)

    /// P8 (July 19 2026): "Delete this Clip" now **soft-deletes** to
    /// Recently Deleted (recycledAt) — the atom survives, edges preserved,
    /// but it's excluded from every memory that referenced it. `purgeClip`
    /// is the permanent destroy (bin's Delete Forever / 30-day purge).
    @Test func deleteClipSoftDeletesThenPurgeDestroys() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Memory A")
        let memB = try seedMemory(in: storage, title: "Memory B")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "victim.caf",
            transcript: "v"
        )
        try StorageService.createEdge(from: memB, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        service.recycleClip(refId: ref.id)

        // Soft: ref survives, recycled, edges preserved.
        #expect(try fetchRefs(in: storage).count == 1)
        #expect(try fetchRefs(in: storage).first?.recycledAt != nil)
        #expect(try fetchEdges(in: storage).count == 2)
        // Excluded from BOTH memories (removed from every referencing memory).
        #expect(memA.mediaReferencesArray.isEmpty)
        #expect(memB.mediaReferencesArray.isEmpty)

        // Purge: permanent — ref + edges gone, memories survive.
        service.purgeClip(refId: ref.id)
        #expect(try fetchRefs(in: storage).isEmpty)
        #expect(try fetchEdges(in: storage).isEmpty)
        #expect(try fetchMemories(in: storage).count == 2)
    }

    // MARK: - B26 · Remove must remove, even when the store holds a duplicate edge

    /// **The converged state**: one clip attached to one memory by TWO edges.
    /// Built by hand, because `createEdge` correctly refuses to make the second
    /// one — the duplicate requires two separate stores converging via CloudKit,
    /// which no local fixture can stage (three attempts, two of which passed and
    /// proved nothing; see `DuplicateEdgeConvergenceTests.swift.held`).
    private func seedDuplicateEdge(
        in storage: StorageService,
        memory: JournalEntry,
        clip: MediaReference
    ) throws {
        let dupe = MemoryClipEdge(context: storage.viewContext)
        dupe.id = UUID()
        dupe.clipId = clip.id
        dupe.memoryId = memory.id
        dupe.clip = clip
        dupe.memory = memory
        dupe.linkedAt = Date()
        try storage.save(context: storage.viewContext)
    }

    /// **B26's one user-reachable consequence: a Remove button that does not
    /// remove.**
    ///
    /// `removeClipFromMemory(memoryId:refId:)` fetched with `fetchLimit = 1`, so
    /// against a duplicated pair it deleted one edge and left the other — the
    /// clip stayed in the memory, and the row stayed on screen, because
    /// `EntryMapper` dedupes `mediaItems` and so renders one row either way.
    /// The user taps Remove and nothing observable happens.
    ///
    /// That is the silent-no-op class the non-negotiables forbid outright, and
    /// it is worse than a visible failure: the app reports success by doing
    /// nothing. **The render dedupe shipped for B26 made the COUNT honest and
    /// did nothing for this** — a fix for one consequence of a defect is not a
    /// fix for the defect's other consequences.
    ///
    /// The assertion is on **membership**, not on a row count: the promise the
    /// button makes is "this clip is not in this memory any more."
    @Test func removeFromMemoryByMemoryAndRef_clearsEveryEdgeForThePair() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Harbor Lantern")
        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "b26-remove-pair.caf",
            transcript: "the tide had already turned"
        )
        try storage.save(context: storage.viewContext)
        try seedDuplicateEdge(in: storage, memory: memA, clip: ref)
        #expect(ref.edgeCount == 2, "precondition: the store really is in the converged state")

        service.removeClipFromMemory(memoryId: memA.id, refId: ref.id)

        #expect(
            ref.referencingMemoryCount == 0,
            "Remove promises the clip is no longer in this memory — a surviving duplicate edge keeps it there"
        )
        let survivors = try fetchEdges(in: storage).filter {
            $0.memoryId == memA.id && $0.clipId == ref.id
        }
        #expect(survivors.isEmpty, "no edge for the (memory, clip) pair may survive the remove")
    }

    /// The same promise through the **edge-id** door, which Memory Detail uses.
    ///
    /// This variant deletes exactly the edge it is handed, so a duplicate
    /// survives by construction rather than by a fetch limit — a different
    /// mechanism, the identical user-visible outcome. Fixing only the
    /// memory+ref door would have left the defect reachable from the screen
    /// where clips are actually removed. *Guard the caller, not just the owner.*
    @Test func removeFromMemoryByEdgeId_clearsEveryEdgeForThePair() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Harbor Lantern")
        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "b26-remove-edge.caf",
            transcript: "the tide had already turned"
        )
        try storage.save(context: storage.viewContext)
        try seedDuplicateEdge(in: storage, memory: memA, clip: ref)
        let anEdge = try #require(ref.edgesArray.first)

        service.removeClipFromMemory(edgeId: anEdge.id)

        #expect(
            ref.referencingMemoryCount == 0,
            "Remove promises the clip is no longer in this memory, whichever of the duplicate edges the UI happened to hold"
        )
        let survivors = try fetchEdges(in: storage).filter {
            $0.memoryId == memA.id && $0.clipId == ref.id
        }
        #expect(survivors.isEmpty, "no edge for the (memory, clip) pair may survive the remove")
    }

    /// **The ceiling.** A fix that removed every edge for the *clip* would
    /// satisfy both tests above and silently detach it from memories the user
    /// never touched. Remove is scoped to one memory; only the pair goes.
    @Test func removeFromMemory_leavesOtherMemoriesEdgesAlone() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "Harbor Lantern")
        let memB = try seedMemory(in: storage, title: "Thistle Beacon")
        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "b26-remove-scope.caf",
            transcript: "the tide had already turned"
        )
        try StorageService.createEdge(from: memB, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)
        try seedDuplicateEdge(in: storage, memory: memA, clip: ref)
        #expect(ref.edgeCount == 3, "precondition: two edges to memA, one to memB")

        service.removeClipFromMemory(memoryId: memA.id, refId: ref.id)

        #expect(ref.referencingMemoryCount == 1, "memB keeps the clip")
        let remaining: [UUID] = ref.memoriesArray.map { $0.id }
        #expect(remaining == [memB.id])
    }
}

/// Money tests for `MediaReference.referencingMemoryCount` and the
/// Phase 7 "Referenced in" contract.
@MainActor
@Suite(.serialized)
struct MediaReferenceReferencedInTests {

    private func makeStore() -> StorageService {
        StorageService(inMemory: true)
    }

    private func seedMemory(in storage: StorageService, title: String) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        try storage.viewContext.save()
        return entry
    }

    @Test func referencingMemoryCountMatchesEdgeCount() throws {
        let storage = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let memB = try seedMemory(in: storage, title: "B")
        let memC = try seedMemory(in: storage, title: "C")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "shared.caf",
            transcript: "x"
        )
        try StorageService.createEdge(from: memB, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: memC, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        #expect(ref.referencingMemoryCount == 3)
    }

    @Test func referencingMemoriesSortedByLinkedAtDesc() throws {
        let storage = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let memB = try seedMemory(in: storage, title: "B")
        let memC = try seedMemory(in: storage, title: "C")

        let ref = try storage.createVoiceFragment(
            for: memA,
            audioFilename: "x.caf",
            transcript: "x"
        )
        // Stamp memA's edge with the oldest linkedAt so ordering is deterministic.
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try StorageService.createEdge(from: memB, to: ref, linkedAt: base.addingTimeInterval(100), in: storage.viewContext)
        try StorageService.createEdge(from: memC, to: ref, linkedAt: base.addingTimeInterval(200), in: storage.viewContext)
        let memAEdges = ((memA.edges as? Set<MemoryClipEdge>) ?? [])
        try #require(memAEdges.first).linkedAt = base
        try storage.save(context: storage.viewContext)

        let memories = ref.referencingMemoriesSortedByLinkedAtDesc
        #expect(memories.map { $0.id } == [memC.id, memB.id, memA.id])
    }

}
