import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for TestFlight #4a (2026-07-25): a **recycled memory is not a
/// live connection**. A clip whose only memory is in Recently Deleted was
/// stranding in Clips/All, advertising an invisible "Untitled memory", because
/// `memoriesArray`/`referencingMemoryCount` counted the trashed edge. The edge
/// is now preserved (so restoring the memory reunites them) but no longer reads
/// as a connection — the clip surfaces on the Unconnected bench instead.
@MainActor
@Suite(.serialized)
struct RecycledMemoryConnectionTests {

    /// A clip whose only memory is recycled → reads Unconnected (zero advertised
    /// memories), edge intact, clip itself still live.
    @Test func clipWhoseOnlyMemoryRecycled_readsUnconnected_edgeIntact() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .typed, title: "Untitled memory")
        let ref = try storage.createVoiceFragment(for: entry, audioFilename: "a.caf", transcript: "hi")
        try storage.viewContext.save()

        // While the memory is live, the clip is connected.
        #expect(ref.referencingMemoryCount == 1)
        #expect(ref.memoriesArray.count == 1)

        // Recycle the memory; the clip stays live (the observed sync state:
        // isRecycled synced, the clip's recycledAt did not).
        entry.isRecycled = true
        try storage.viewContext.save()

        #expect(ref.memoriesArray.isEmpty, "a recycled memory is not surfaced")
        #expect(ref.referencingMemoryCount == 0, "the clip reads as Unconnected")
        #expect(ref.edgeCount == 1, "the edge is preserved for a later reunite")
        #expect(ref.recycledAt == nil, "the clip itself stays live")

        // It surfaces on the Unconnected lens.
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = MediaReference.noLiveMemoryConnectionPredicate
        #expect(try storage.viewContext.fetch(req).contains(ref), "surfaces on the Unconnected bench")
    }

    /// Restoring that memory reunites the clip — it reads as evidence again and
    /// leaves the Unconnected lens.
    @Test func restoringMemory_reunitesClipAsEvidence() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .typed, title: "Untitled memory")
        let ref = try storage.createVoiceFragment(for: entry, audioFilename: "a.caf", transcript: "hi")
        entry.isRecycled = true
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 0)

        entry.isRecycled = false // restore the container
        try storage.viewContext.save()

        #expect(ref.memoriesArray.count == 1, "the clip reappears as evidence")
        #expect(ref.referencingMemoryCount == 1)
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = MediaReference.noLiveMemoryConnectionPredicate
        #expect(!(try storage.viewContext.fetch(req).contains(ref)), "no longer Unconnected")
    }

    /// A live memory keeps its clip connected even when the same clip also has
    /// an edge to a recycled memory — only the live edge counts.
    @Test func clipWithLiveAndRecycledMemories_countsOnlyLive() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let live = try storage.createEntry(content: "", inputType: .typed, title: "Live")
        let ref = try storage.createVoiceFragment(for: live, audioFilename: "a.caf", transcript: "hi")

        // Second edge to a recycled memory.
        let trashed = try storage.createEntry(content: "", inputType: .typed, title: "Trashed")
        let edge = MemoryClipEdge(context: ctx)
        edge.id = UUID()
        edge.clip = ref
        edge.memory = trashed
        edge.clipId = ref.id
        edge.memoryId = trashed.id
        edge.linkedAt = Date()
        trashed.isRecycled = true
        try ctx.save()

        #expect(ref.edgeCount == 2, "both edges are preserved")
        #expect(ref.referencingMemoryCount == 1, "only the live memory counts")
        #expect(ref.memoriesArray.map { $0.title } == ["Live"])
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = MediaReference.noLiveMemoryConnectionPredicate
        #expect(!(try ctx.fetch(req).contains(ref)), "still connected — not Unconnected")
    }
}
