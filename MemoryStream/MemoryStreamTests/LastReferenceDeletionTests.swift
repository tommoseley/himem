import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the P8 last-reference deletion rule (July 19 2026),
/// which narrowly reverses P6's "clips always survive Let Go." Decided
/// from current edge counts at delete time — no history field.
///
/// - Let Go a memory: a clip whose single remaining edge is THIS memory
///   moves to Recently Deleted with it; a clip used elsewhere stays.
/// - Restore is symmetric: the only-here clips come back with the memory.
/// - Detach-from-last-memory does NOT auto-retire (stays unconnected).
@MainActor
@Suite(.serialized)
struct LastReferenceDeletionTests {

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

    private func fetchRef(_ id: UUID, in storage: StorageService) throws -> MediaReference {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try #require(try storage.viewContext.fetch(req).first)
    }

    /// The core rule: Let Go retires the only-here clip, keeps the shared one.
    @Test func recycle_retiresLastReferenceClip_keepsSharedClip() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let memB = try seedMemory(in: storage, title: "B")

        // C_only: single edge to memA. C_shared: edges to memA AND memB.
        let cOnly = try storage.createVoiceFragment(for: memA, audioFilename: "only.caf", transcript: "only")
        let cShared = try storage.createVoiceFragment(for: memA, audioFilename: "shared.caf", transcript: "shared")
        try StorageService.createEdge(from: memB, to: cShared, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        service.recycle(entryId: memA.id)

        // C_only came down with the memory; C_shared stays (used by memB).
        #expect(try fetchRef(cOnly.id, in: storage).recycledAt != nil)
        #expect(try fetchRef(cShared.id, in: storage).recycledAt == nil)
        // The memory itself is recycled.
        #expect(memA.recycledAt != nil)
    }

    /// Restore is symmetric — the only-here clip returns with the memory.
    @Test func restore_bringsBackOnlyHereClip() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let cOnly = try storage.createVoiceFragment(for: memA, audioFilename: "only.caf", transcript: "only")
        try storage.save(context: storage.viewContext)

        service.recycle(entryId: memA.id)
        #expect(try fetchRef(cOnly.id, in: storage).recycledAt != nil)

        service.restore(entryId: memA.id)
        #expect(memA.recycledAt == nil)
        #expect(try fetchRef(cOnly.id, in: storage).recycledAt == nil, "the clip that came down with the memory comes back with it")
    }

    /// Detach-from-last-memory does NOT auto-retire — "not here" ≠ "not
    /// wanted." The clip drops to 0 edges (unconnected on the bench), never
    /// recycled.
    @Test func detachFromLastMemory_doesNotAutoRetire() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let clip = try storage.createVoiceFragment(for: memA, audioFilename: "c.caf", transcript: "c")
        try storage.save(context: storage.viewContext)

        service.removeClipFromMemory(memoryId: memA.id, refId: clip.id)

        let ref = try fetchRef(clip.id, in: storage)
        #expect(ref.recycledAt == nil, "detach never auto-retires")
        #expect(ref.referencingMemoryCount == 0, "the clip is now unconnected on the bench")
    }

    /// A memory whose clips are ALL shared retires nothing on Let Go.
    @Test func recycle_allSharedClips_retiresNothing() throws {
        let (storage, service) = makeStore()
        let memA = try seedMemory(in: storage, title: "A")
        let memB = try seedMemory(in: storage, title: "B")
        let shared = try storage.createVoiceFragment(for: memA, audioFilename: "s.caf", transcript: "s")
        try StorageService.createEdge(from: memB, to: shared, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        service.recycle(entryId: memA.id)
        #expect(try fetchRef(shared.id, in: storage).recycledAt == nil)
    }
}

/// Money tests for the P8 Let Go split-disclosure copy — discloses, never
/// asks; `M == 0` shows only the stay line; `stay == 0` names the count.
@Suite
struct LetGoFootnoteTests {

    @Test func bothSides_pluralized() {
        let s = BottomDeleteButton.letGoFootnote(stayCount: 8, moveCount: 5)
        #expect(s == "8 clips are also used elsewhere and will stay · 5 are only here and move to Recently Deleted for 30 days.")
    }

    @Test func moveZero_showsOnlyStay() {
        let s = BottomDeleteButton.letGoFootnote(stayCount: 3, moveCount: 0)
        #expect(!s.contains("Recently Deleted"))
        #expect(s.contains("will stay"))
    }

    @Test func stayZero_namesTheMovingCount() {
        let s = BottomDeleteButton.letGoFootnote(stayCount: 0, moveCount: 4)
        #expect(s == "4 clips are only here and move to Recently Deleted for 30 days.")
    }

    @Test func singular_stayAndMove() {
        let s = BottomDeleteButton.letGoFootnote(stayCount: 1, moveCount: 1)
        #expect(s == "1 clip is also used elsewhere and will stay · 1 is only here and moves to Recently Deleted for 30 days.")
    }

    @Test func noClips_fallsBackToMemoryNet() {
        let s = BottomDeleteButton.letGoFootnote(stayCount: 0, moveCount: 0)
        #expect(s == "Moves to Recently Deleted · kept for 30 days.")
    }
}
