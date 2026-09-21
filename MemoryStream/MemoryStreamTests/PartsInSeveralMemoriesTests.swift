import Testing
import Foundation
import CoreData
@testable import HiMem

/// **A part can belong to several memories** — and the properties that must
/// hold when it does.
///
/// ## What this suite replaced
///
/// `SingleMemoryPerPartTests` pinned F2, *a part belongs to exactly one
/// memory* (Tom, 2026-09-16), enforced write-side in `StorageService.createEdge`.
/// `The descoping · synopsis.md` walks that back explicitly, and is dated after
/// the ruling it supersedes:
///
/// > **Many-to-many stays.** This document claimed M:M existed *because* clips
/// > were independently viewable. That was wrong. One photograph legitimately
/// > belongs to both "our retirement trip" and "Judi at 70" — that is reality,
/// > not an artifact of the removed UI.
///
/// So the **subject** retired, not just the answer — the same shape as the
/// hands-free block in `CaptureLandingRouterTests`. The question *"is a second
/// memory refused?"* no longer has an answer, because nothing refuses.
///
/// ## Why this is not simply a deletion
///
/// Four of that suite's seven tests never asserted the invariant. They asserted
/// that a part with several memories **reads, counts, saves and re-attaches
/// correctly** — written to stop anyone turning F2 into a read-side assertion,
/// since real devices already carried such parts. With M:M restored those are
/// no longer a boundary around a rule; they are the **ordinary behaviour of the
/// data model**, and they are more load-bearing now than when they were
/// written. Deleting them with the suite would have cut live coverage to
/// retire a rule they were never testing.
///
/// Retired with the rule, and not carried over:
///   - `secondMemoryIsRefused` — the invariant itself.
///   - `letGoReleasesThePart` — it asserted that the *guard* did not count
///     recycled memories as occupancy. With no guard there is no occupancy to
///     miscount. The Let Go promise it protected is asserted where it lives,
///     in `DeletionSemanticsTests`.
///   - `loosePartAttaches` — a plain attach, covered many times over.
///
/// Edges are built directly here rather than through `HistoricalEdgeFixture`:
/// that helper exists to manufacture *pre-invariant* data, and after this
/// retirement there is no such thing — a part in two memories is ordinary data
/// made the ordinary way.
@MainActor
@Suite(.serialized)
struct PartsInSeveralMemoriesTests {

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

    // MARK: - The rule that replaced F2

    /// **The money test for the retirement.** Under F2 this threw.
    @Test("a part already in one memory can join a second")
    func aPartCanJoinASecondMemory() throws {
        let storage = makeStorage()
        let trip = try makeEntry(storage, title: "Our retirement trip")
        let birthday = try makeEntry(storage, title: "Judi at 70")
        let photo = try makeLooseRef(storage, filename: "photo.heic")

        try StorageService.createEdge(from: trip, to: photo, linkedAt: Date(), in: storage.viewContext)
        #expect(throws: Never.self) {
            try StorageService.createEdge(from: birthday, to: photo, linkedAt: Date(), in: storage.viewContext)
        }
        try storage.viewContext.save()

        #expect(photo.edgeCount == 2)
        #expect(photo.referencingMemoryCount == 2)
    }

    // MARK: - What survived F2's retirement

    /// Pair idempotency is NOT part of F2 and did not retire with it. Asking
    /// for an edge that already exists is a no-op because the desired end state
    /// already holds; turning it into a throw would break every re-invoked
    /// commit path, which is the "duplicate transcript rows on Memory Detail"
    /// defect (CD 2026-07-09).
    @Test("re-adding to the SAME memory stays a silent no-op, not a throw")
    func samePairRemainsIdempotent() throws {
        let storage = makeStorage()
        let entry = try makeEntry(storage, title: "Dinner")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: entry, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()
        #expect(ref.edgeCount == 1)
    }

    /// A part in two memories must render and count correctly from both sides.
    /// Written under F2 to stop the invariant becoming read-side; now simply
    /// the model's ordinary behaviour, and the reason M:M was described as
    /// costing nothing.
    @Test("a part in two memories reads and counts from both sides")
    func multiMemoryPartReadsCorrectly() throws {
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: second, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()

        #expect(ref.edgeCount == 2)
        #expect(ref.referencingMemoryCount == 2, "both live memories must count")
        #expect(ref.memoriesArray.count == 2)
        #expect(first.edgesArray.count == 1)
        #expect(second.edgesArray.count == 1)
    }

    @Test("an unrelated write on a multi-memory part still succeeds")
    func unrelatedWriteOnMultiMemoryPartSucceeds() throws {
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: second, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()

        ref.transcript = "edited words"
        ref.isAccessible = false
        #expect(throws: Never.self) { try storage.viewContext.save() }
        #expect(ref.transcript == "edited words")
    }

    @Test("re-adding to a memory it is already in stays idempotent when multi-edge")
    func idempotencyHoldsWhenMultiEdge() throws {
        let storage = makeStorage()
        let first = try makeEntry(storage, title: "Dinner")
        let second = try makeEntry(storage, title: "Drive home")
        let ref = try makeLooseRef(storage)

        try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        try StorageService.createEdge(from: second, to: ref, linkedAt: Date(), in: storage.viewContext)
        try storage.viewContext.save()

        #expect(throws: Never.self) {
            try StorageService.createEdge(from: first, to: ref, linkedAt: Date(), in: storage.viewContext)
        }
        #expect(ref.edgeCount == 2, "no new edge, and none removed")
    }
}
