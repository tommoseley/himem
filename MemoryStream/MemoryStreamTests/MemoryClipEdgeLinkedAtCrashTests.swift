import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the July 11 crash Tom hit in
/// `JournalEntry.edgesArray.getter` at line 203 — a Memory with more
/// than one clip crashed on `lhs.linkedAt < rhs.linkedAt` because
/// `MemoryClipEdge.linkedAt` is declared non-optional (`Date`) in
/// Swift but marked `optional="YES"` in the Core Data model. Any
/// edge row whose `linkedAt` cell is nil at load (older-schema
/// import, partial CloudKit sync, incomplete write) traps the
/// getter with EXC_BREAKPOINT before the `<` even runs.
///
/// This test builds a Memory with two edges, one with a real
/// `linkedAt` and one where it wasn't set (`nil` at the store
/// level). Accessing `entry.edgesArray` must NOT crash — the sort
/// falls back to a nil-safe compare.
@MainActor
@Suite(.serialized)
struct MemoryClipEdgeLinkedAtCrashTests {

    @Test func edgesArray_survives_nil_linkedAt() throws {
        let ctx = try makeInMemoryContext()

        let entry = JournalEntry(context: ctx)
        entry.id = UUID()
        entry.createdAt = Date()

        let clip1 = MediaReference(context: ctx)
        clip1.id = UUID()
        clip1.osIdentifier = "a.m4a"
        clip1.mediaType = MediaReference.MediaType.voice.rawValue
        clip1.createdAt = Date()

        let clip2 = MediaReference(context: ctx)
        clip2.id = UUID()
        clip2.osIdentifier = "b.m4a"
        clip2.mediaType = MediaReference.MediaType.voice.rawValue
        clip2.createdAt = Date()

        // Well-formed edge — carries a linkedAt.
        let e1 = MemoryClipEdge(context: ctx)
        e1.id = UUID()
        e1.clipId = clip1.id
        e1.memoryId = entry.id
        e1.clip = clip1
        e1.memory = entry
        e1.orderInMemory = 0
        e1.linkedAt = Date()

        // Malformed edge — linkedAt intentionally not set. Simulates
        // the partial-write / CloudKit-imported-before-linkedAt-existed
        // state that triggers Tom's crash.
        let e2 = MemoryClipEdge(context: ctx)
        e2.id = UUID()
        e2.clipId = clip2.id
        e2.memoryId = entry.id
        e2.clip = clip2
        e2.memory = entry
        e2.orderInMemory = 1
        // e2.linkedAt intentionally NOT set → nil at the store level

        try ctx.save()

        // The critical read that used to crash. Just accessing the
        // getter is enough — the sort compare inside must be nil-safe.
        let edges = entry.edgesArray
        #expect(edges.count == 2, "both edges must be returned, nil linkedAt included")
    }

    /// Same shape for `MediaReference.referencingMemoriesSortedByLinkedAtDesc`
    /// — the other sort site that reads `edge.linkedAt`.
    @Test func referencingMemoriesSortedByLinkedAtDesc_survives_nil() throws {
        let ctx = try makeInMemoryContext()

        let clip = MediaReference(context: ctx)
        clip.id = UUID()
        clip.osIdentifier = "shared.m4a"
        clip.mediaType = MediaReference.MediaType.voice.rawValue
        clip.createdAt = Date()

        let entry1 = JournalEntry(context: ctx)
        entry1.id = UUID()
        entry1.createdAt = Date()
        let entry2 = JournalEntry(context: ctx)
        entry2.id = UUID()
        entry2.createdAt = Date()

        let e1 = MemoryClipEdge(context: ctx)
        e1.id = UUID()
        e1.clipId = clip.id
        e1.memoryId = entry1.id
        e1.clip = clip
        e1.memory = entry1
        e1.linkedAt = Date()

        let e2 = MemoryClipEdge(context: ctx)
        e2.id = UUID()
        e2.clipId = clip.id
        e2.memoryId = entry2.id
        e2.clip = clip
        e2.memory = entry2
        // linkedAt intentionally nil

        try ctx.save()

        let memories = clip.referencingMemoriesSortedByLinkedAtDesc
        #expect(memories.count == 2, "both memories must return, nil-linkedAt edge included")
    }

    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        // Test-isolation fix (2026-07-15): share the ONE production
        // `cachedModel` via StorageService(inMemory:) instead of a fresh
        // `mergedModel(from:)` — multiple live models for the same entity
        // classes race in Core Data's global registry under parallel @Suite
        // runs. Stores stay per-test isolated; the MODEL shares one instance.
        return StorageService(inMemory: true).viewContext
    }
}
