import Testing
import Foundation
import CoreData
@testable import HiMem

/// **F2 · a part belongs to exactly one memory — enforced on the WRITE side.**
///
/// The vocabulary retirement supersedes clip↔memory many-to-many: it existed to
/// support a browsable bench of atoms, and that surface is gone (Tom,
/// 2026-09-16). The invariant is enforced where edges are *created*, not in the
/// schema — `MemoryClipEdge` is untouched, existing rows stay, there is no
/// migration and no Production CloudKit deploy. The schema collapse waits for a
/// batch it can ride.
///
/// **THIS SUITE PINS THE BOUNDARY AS MUCH AS THE RULE.** The last three tests
/// exist to stop a future reader turning "one memory per part" into a
/// *read-side* assertion — a fetch-time invariant or a `#expect` on
/// `referencingMemoryCount <= 1` would fail on real historical data that this
/// ruling explicitly preserves.
@MainActor
@Suite(.serialized)
struct SingleMemoryPerPartTests {

    private func makeStorage() -> StorageService { StorageService(inMemory: true) }

    private func makeEntry(_ storage: StorageService, title: String) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        try storage.viewContext.save()
        return entry
    }

    private func makeLooseRef(_ storage: StorageService, filename: String = "clip.caf") throws -> MediaReference {
        let ref = MediaReference(context: storage.viewContext)
        ref.id = UUID()
        ref.osIdentifier = filename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.transcript = "a recording"
        ref.isAccessible = true
        ref.createdAt = Date()
        try storage.viewContext.save()
        return ref
    }

    /// Build an edge WITHOUT going through `createEdge`, so a test can
    /// construct historical multi-memory data the guard would now refuse.
    /// This is how the pre-ruling world looks on a real device.
    private func forceEdge(_ storage: StorageService, from entry: JournalEntry, to ref: MediaReference) throws {
        let edge = MemoryClipEdge(context: storage.viewContext)
        edge.id = UUID()
        edge.clipId = ref.id
        edge.memoryId = entry.id
        edge.clip = ref
        edge.memory = entry
        edge.orderInMemory = Int16(entry.edgesArray.count)
        edge.linkedAt = Date()
        try storage.viewContext.save()
    }

    // MARK: - The rule

    @Test("a part already in one memory is refused by a second")
    func secondMemoryIsRefused() throws {
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 1)

        #expect(throws: (any Error).self) {
            try StorageService.createEdge(from: second, to: ref, linkedAt: Date(), in: storage.viewContext)
        }
        // The refusal must leave nothing behind — no half-made edge.
        #expect(ref.edgeCount == 1, "a refused attach must not create an edge")
        #expect(second.edgesArray.isEmpty, "the second memory must be untouched")
    }

    @Test("a loose part attaches normally")
    func loosePartAttaches() throws {
        let storage = makeStorage()
        let entry = try makeEntry(storage, title: "Dinner")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 1)
    }

    @Test("re-adding to the SAME memory stays a silent no-op, not a throw")
    func samePairRemainsIdempotent() throws {
        // Pre-existing behaviour, deliberately unchanged: the desired end state
        // already holds, so this is idempotency rather than a refusal. Turning
        // it into a throw would break every re-invoked commit path.
        let storage = makeStorage()
        let entry = try makeEntry(storage, title: "Dinner")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.edgeCount == 1)
    }

    // MARK: - Let Go must still release the part

    @Test("a part whose only memory was let go can join another")
    func letGoReleasesThePart() throws {
        // The Let Go lock: "The clips stay — they'll be available to start
        // other memories." If the guard counted edges to RECYCLED memories it
        // would orphan that part forever, which is a data-reachability failure
        // wearing an invariant's clothes.
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        first.isRecycled = true
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 0, "a recycled memory is not a live connection")

        try StorageService.createEdge(from: second, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.referencingMemoryCount == 1)
    }

    // MARK: - THE BOUNDARY — write-side only. Do not make these read-side.

    @Test("historical multi-memory data still reads, and is not retro-refused")
    func historicalMultiEdgeDataStillReads() throws {
        // Ruled explicitly (Tom, 2026-09-16): existing rows stay, no migration.
        // A clip that legitimately has two edges today must keep rendering and
        // counting correctly. If this fails, someone has added a read-side
        // assertion and broken real user data.
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try forceEdge(storage, from: first, to: ref)
        try forceEdge(storage, from: second, to: ref)

        #expect(ref.edgeCount == 2)
        #expect(ref.referencingMemoryCount == 2, "both live memories must still count")
        #expect(ref.memoriesArray.count == 2)
        #expect(first.edgesArray.count == 1)
        #expect(second.edgesArray.count == 1)
    }

    @Test("an unrelated write on a legitimately multi-memory part still succeeds")
    func unrelatedWriteOnMultiMemoryPartSucceeds() throws {
        // The specific regression Tom named: the guard must never make an
        // unrelated write fail on a clip that legitimately has two edges today.
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try forceEdge(storage, from: first, to: ref)
        try forceEdge(storage, from: second, to: ref)

        ref.transcript = "edited words"
        ref.isAccessible = false
        #expect(throws: Never.self) { try storage.viewContext.save() }
        #expect(ref.transcript == "edited words")
    }

    @Test("re-adding to a memory it is ALREADY in stays idempotent even when multi-edge")
    func idempotencyHoldsOnHistoricalMultiEdge() throws {
        // A historical multi-memory part must not become un-writable: asking
        // for an edge that already exists is still a no-op, not a refusal,
        // because the desired end state already holds.
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try forceEdge(storage, from: first, to: ref)
        try forceEdge(storage, from: second, to: ref)

        #expect(throws: Never.self) {
            try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        }
        #expect(ref.edgeCount == 2, "no new edge, and none removed")
    }
}
