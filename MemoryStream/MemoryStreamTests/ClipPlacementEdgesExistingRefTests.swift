import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for P0-3 piece C — placement EDGES the existing ref, never
/// re-materializes (`docs/architecture/2026-07-25-clip-sync-single-source-of-
/// truth.md`). Post-B a bench clip is already a CloudKit-synced zero-edge
/// `MediaReference`; the old move+mint placement path would now mint a SECOND
/// ref (new UUID) and leave the clip on the bench — the double-ref bug. These
/// lock that placement attaches the SAME ref (id == clipId) and mints nothing.
@MainActor
@Suite(.serialized)
struct ClipPlacementEdgesExistingRefTests {

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        return (storage, EntryLifecycleService(storage: storage, processingEngine: nil))
    }

    /// Mint a zero-edge voice ref exactly as `ArrivedClipMaterializer` would
    /// (id == clipId), so placement has a materialized clip to edge.
    @discardableResult
    private func seedRef(id: UUID, in ctx: NSManagedObjectContext, filename: String = "clip.m4a") throws -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = id
        ref.osIdentifier = filename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        ref.transcript = "hello there"
        try ctx.save()
        return ref
    }

    private func refCount(in ctx: NSManagedObjectContext) throws -> Int {
        try ctx.count(for: NSFetchRequest<MediaReference>(entityName: "MediaReference"))
    }

    // MARK: - New memory

    @Test func newMemory_fromExistingClip_edgesSameRef_noDuplicate() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let clipId = UUID()
        let ref = try seedRef(id: clipId, in: ctx)
        #expect(ref.referencingMemoryCount == 0, "starts zero-edge")

        let newId = service.createMemoryFromExistingClips(clipIds: [clipId])
        #expect(newId != nil, "a memory was created")
        #expect(try refCount(in: ctx) == 1, "NO duplicate ref minted — the existing one was edged")
        #expect(ref.referencingMemoryCount == 1, "the existing ref now belongs to the new memory")
    }

    @Test func newMemory_noResolvableClips_returnsNil_leavesNoEmptyMemory() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let before = try ctx.count(for: NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))

        // A clipId with no backing ref (never materialized) resolves to nothing.
        let newId = service.createMemoryFromExistingClips(clipIds: [UUID()])
        #expect(newId == nil, "nothing to attach → no memory")

        let after = try ctx.count(for: NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))
        #expect(after == before, "no empty memory left stranded (July 12 symptom)")
    }

    // MARK: - Existing memory

    @Test func existingMemory_attachExisting_edgesSameRef_noDuplicate() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let target = try storage.createEntry(content: "", inputType: .typed, title: "Target")
        try ctx.save()

        let clipId = UUID()
        let ref = try seedRef(id: clipId, in: ctx)
        let attached = service.attachExistingClips(entryId: target.id, clipIds: [clipId])

        #expect(attached == 1, "the existing ref was edged into the memory")
        #expect(try refCount(in: ctx) == 1, "NO duplicate ref minted")
        #expect(ref.referencingMemoryCount == 1, "the ref belongs to the target memory")
    }

    /// The multi-clip session case: N bench refs → one new memory, exactly N
    /// edges, zero new refs (the whole-session Start-a-Memory path).
    @Test func newMemory_fromSession_attachesAllRefs_mintsNone() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let ids = [UUID(), UUID(), UUID()]
        for (i, id) in ids.enumerated() { try seedRef(id: id, in: ctx, filename: "clip-\(i).m4a") }
        #expect(try refCount(in: ctx) == 3)

        let newId = try #require(service.createMemoryFromExistingClips(clipIds: ids))
        #expect(try refCount(in: ctx) == 3, "still 3 refs — none minted")
        let entry = try #require(try ctx.fetch({
            let r = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            r.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
            return r
        }()).first)
        #expect(entry.edgesArray.count == 3, "all three refs edged onto the memory")
    }
}
