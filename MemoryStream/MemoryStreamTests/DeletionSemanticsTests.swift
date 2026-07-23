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
