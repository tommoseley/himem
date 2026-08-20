import Testing
import Foundation
import CoreData
@testable import HiMem

/// **B26 — a duplicate edge must never make the app lie at the moment of
/// destruction.**
///
/// A clip attached to one memory twice made `referencingMemoryCount` read **2**,
/// so the delete warning said *"This clip is part of 2 memories. Deleting it
/// removes it from all of them"* when it was one. A confident falsehood at the
/// instant of destruction — the Honest-Label class where it costs most. Ruling 2
/// of 2026-08-19 widened what "Delete session" destroys, so a wrong count in
/// front of that path is more expensive than it was.
///
/// **This fixes the RENDER, deliberately, and that is not hiding the defect.**
/// The write path was investigated first (ruled: no dedupe until it is
/// understood) and turns out to be **correct**: `createEdge`'s guard refuses a
/// duplicate whenever it can see the prior edge, and where it cannot, the
/// shared coordinator's optimistic locking refuses the save outright
/// (`NSCocoaErrorDomain 133020`). Three separate fixtures failed to reproduce a
/// duplicate within one store — two of them by *passing*, which is the
/// dangerous direction.
///
/// The duplicate therefore requires **two genuinely separate stores converging
/// via CloudKit**, where no shared coordinator exists to catch the conflict, and
/// the model cannot forbid it (`NSPersistentCloudKitContainer` allows no
/// uniqueness constraints). So this is not a state we can prevent — it is one we
/// must render honestly. **Corruption that renders honestly is survivable; a
/// confident wrong number in front of a delete is not.**
///
/// The reconcile that actually REMOVES the duplicate is deferred to the
/// C-family (ruled: new machinery on the sync path must not land days before a
/// build reaches the person whose data it would reconcile). Its survivor policy
/// is already ruled and recorded in `DuplicateEdgeConvergenceTests.swift.held`.
@MainActor
@Suite(.serialized)
struct DuplicateEdgeHonestCountTests {

    /// Builds the converged state directly — what the store looks like AFTER a
    /// CloudKit merge. Constructed by hand rather than through `createEdge`,
    /// which correctly refuses: the point is the state, not how it arrived, and
    /// this stays valid once a reconcile exists.
    private func seedDuplicateEdge(
        in storage: StorageService
    ) throws -> (memory: JournalEntry, clip: MediaReference) {
        let memory = try storage.createEntry(content: "", inputType: .typed)
        memory.title = "Harbor Lantern"
        let clip = try storage.createVoiceFragment(
            for: memory,
            audioFilename: "b26-\(UUID().uuidString).caf",
            transcript: "the tide had already turned"
        )
        try storage.save(context: storage.viewContext)

        let dupe = MemoryClipEdge(context: storage.viewContext)
        dupe.id = UUID()
        dupe.clipId = clip.id
        dupe.memoryId = memory.id
        dupe.clip = clip
        dupe.memory = memory
        dupe.linkedAt = Date()
        try storage.save(context: storage.viewContext)
        return (memory, clip)
    }

    /// **The money test.** One memory, counted once.
    @Test
    func aDuplicateEdgeDoesNotInflateTheDeleteWarningsCount() throws {
        let storage = StorageService(inMemory: true)
        let (_, clip) = try seedDuplicateEdge(in: storage)

        #expect(clip.edgeCount == 2, "precondition: the store really is in the converged state")
        #expect(
            clip.referencingMemoryCount == 1,
            "the clip is in ONE memory — this number is read out to the user at the instant of destruction"
        )
    }

    /// The list behind the count, so a right number over a wrong list cannot
    /// pass. Clip Detail's "Referenced in" renders this.
    @Test
    func theReferencedInListNamesEachMemoryOnce() throws {
        let storage = StorageService(inMemory: true)
        let (memory, clip) = try seedDuplicateEdge(in: storage)

        #expect(clip.memoriesArray.map(\.id) == [memory.id])
        #expect(clip.referencingMemoriesSortedByLinkedAtDesc.map(\.id) == [memory.id])
    }

    /// **The count that travels with a deduped row must itself be deduped.**
    ///
    /// The 2026-07-09 fix deduped `EntryMapper`'s `mediaItems` by ref id and
    /// then passed `referencingMemoryCount: ref.referencingMemoryCount` — the
    /// UNDEDUPED number — onto each surviving row. It deduped the rows and left
    /// the count on them wrong: count-describes-a-different-set, inside the fix
    /// for that very class. Fixing the two separately would have repeated it a
    /// third time, so this pins them together.
    @Test
    func theMapperCarriesTheDedupedCountOntoTheDedupedRow() throws {
        let storage = StorageService(inMemory: true)
        let (memory, clip) = try seedDuplicateEdge(in: storage)

        let model = EntryMapper.mapToDisplayModel(memory)
        let rows = model.mediaItems.filter { $0.id == clip.id }

        #expect(rows.count == 1, "the row dedupe is the 2026-07-09 guard and must still hold")
        #expect(
            rows.first?.referencingMemoryCount == 1,
            "and the number ON that row must describe the same set the row does"
        )
    }

    /// A clip genuinely in two memories must still read 2 — the ceiling, not
    /// just the floor. A dedupe that collapsed distinct memories would satisfy
    /// every assertion above while breaking the honest case.
    @Test
    func twoDistinctMemoriesStillCountAsTwo() throws {
        let storage = StorageService(inMemory: true)
        let (_, clip) = try seedDuplicateEdge(in: storage)

        let second = try storage.createEntry(content: "", inputType: .typed)
        second.title = "Thistle Beacon"
        try StorageService.createEdge(from: second, to: clip, linkedAt: Date(), in: storage.viewContext)
        try storage.save(context: storage.viewContext)

        #expect(clip.referencingMemoryCount == 2, "two real memories are two — the dedupe must not collapse distinct ones")
        #expect(Set(clip.memoriesArray.map(\.id)).count == 2)
    }
}
