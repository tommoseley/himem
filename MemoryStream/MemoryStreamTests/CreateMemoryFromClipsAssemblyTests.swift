import Testing
import Foundation
import CoreData
@testable import HiMem

/// Assembly invariants for the LIVE "Start a Memory from N clips" primitive,
/// `EntryLifecycleService.createMemoryFromExistingClips` (P0-3).
///
/// **Retired coverage — read before assuming this inherits it.** The old
/// `createMemoryFromVoiceClips` orphan-`.note` guard was deleted with its
/// method in the 2026-07-26 dead-code sweep (Tom's ruling). That guard
/// reproduced a defect — `entry.content` set to a **raw** transcript join,
/// drifting from the cleaned fragments and minting a duplicate `.note` — that
/// **cannot exist on this path**: `createMemoryFromExistingClips` starts with
/// empty content and reconciles from already-cleaned refs, so there is no raw
/// join to orphan. The orphan-note *class* is now covered, from any path, by
/// the render-seam fail-safe `migrateOrphanedContentIfNeeded`
/// (`SynthesizedNoteRenderGuardTests`). The tests below are NOT that guard.
@MainActor
@Suite(.serialized)
struct CreateMemoryFromClipsAssemblyTests {

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    /// A loose (zero-edge) voice ref — a materialized bench clip, the input to
    /// `createMemoryFromExistingClips`.
    @discardableResult
    private func seedLooseVoiceRef(in ctx: NSManagedObjectContext, file: String, transcript: String, createdAt: Date) -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = file
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.createdAt = createdAt
        ref.transcript = transcript
        ref.isAccessible = true
        return ref
    }

    // MARK: - NEW coverage (2026-07-26) — the live-path assembly invariant

    /// **NEW test, not a migrated guard.** A genuine invariant of the LIVE
    /// `createMemoryFromExistingClips` path: N existing refs → exactly N refs
    /// in the memory, no synthesized `.note`, and `entry.content` reconciled to
    /// `joinedContent` (never left empty). This is a *different mechanism* from
    /// the retired orphan-note guard (see the type doc) — it locks that the
    /// live path attaches-and-reconciles, it does not test raw-join drift.
    @Test func createMemoryFromExistingClips_yieldsExactlyNRefs_contentReconciled_notEmpty() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let t0 = Date()
        let a = seedLooseVoiceRef(in: ctx, file: "a.caf", transcript: "first capture", createdAt: t0)
        let b = seedLooseVoiceRef(in: ctx, file: "b.caf", transcript: "second capture", createdAt: t0.addingTimeInterval(10))
        try ctx.save()

        let newId = try #require(service.createMemoryFromExistingClips(clipIds: [a.id, b.id]))
        // Render-seam fires on Memory Detail onAppear — must add nothing.
        service.migrateOrphanedContentIfNeeded(entryId: newId)

        let entry = try #require(fetchEntry(newId, in: storage))
        let refs = entry.mediaReferencesArray
        #expect(refs.filter { $0.mediaTypeEnum == .voice }.count == 2, "exactly the 2 attached voice refs")
        #expect(refs.filter { $0.mediaTypeEnum == .note }.isEmpty, "no synthesized note on the live path")
        #expect(refs.count == 2, "N existing refs → exactly N clips; no synthesis")
        #expect(!entry.content.isEmpty, "content is reconciled from the fragments, never left empty")
        #expect(entry.content == EntryLifecycleService.joinedContent(from: entry), "content reconciled to joinedContent")
    }

    // MARK: - Ordering (re-pointed from the retired createMemoryFromVoiceClips test)

    /// The primitive attaches in `capturedAt` order regardless of the clipId
    /// order handed in — `attachExistingClips` sorts by `createdAt`.
    @Test func createMemoryFromExistingClips_attachesInCapturedAtOrder() throws {
        let (storage, service) = makeService()
        let ctx = storage.viewContext
        let t0 = Date()
        // Seeded out of capturedAt order; passed out of order too.
        let c = seedLooseVoiceRef(in: ctx, file: "clip-c.caf", transcript: "third", createdAt: t0.addingTimeInterval(20))
        let a = seedLooseVoiceRef(in: ctx, file: "clip-a.caf", transcript: "first", createdAt: t0)
        let b = seedLooseVoiceRef(in: ctx, file: "clip-b.caf", transcript: "second", createdAt: t0.addingTimeInterval(10))
        try ctx.save()

        let newId = try #require(service.createMemoryFromExistingClips(clipIds: [c.id, a.id, b.id]))
        let entry = try #require(fetchEntry(newId, in: storage))
        let orderedFiles = entry.edgesArray.map { $0.clip?.osIdentifier }
        #expect(orderedFiles == ["clip-a.caf", "clip-b.caf", "clip-c.caf"],
                "attached in capturedAt order, not the id order given")
    }
}
