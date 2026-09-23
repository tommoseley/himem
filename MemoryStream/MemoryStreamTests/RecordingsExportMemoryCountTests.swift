import Testing
import Foundation
import CoreData
@testable import HiMem

/// Which memories a recording counts as belonging to.
///
/// Its own file because it builds a Core Data stack, and
/// `CoreDataSuiteIsolationGuardTests` requires any suite that does to be
/// `@MainActor` — `RecordingsExportTests` is otherwise pure and stays that
/// way rather than being annotated to accommodate one test.
@MainActor
@Suite(.serialized)
struct RecordingsExportMemoryCountTests {

    /// **An edge whose memory row is gone must not count as a memory.**
    ///
    /// The snapshot read `$0.memory?.isRecycled == true ? nil : $0.memoryId`.
    /// When `memory` is nil the optional chain yields nil, `nil == true` is
    /// false, and the id was kept — so every orphaned edge inflated the count
    /// and `index.json` could call a recording "in 2 memories" when both had
    /// been destroyed.
    ///
    /// That number is what a recovery decision gets made on: it decides
    /// whether a lost recording was referenced user data or an orphan, which
    /// on 2026-09-23 was the difference between "a data-loss defect" and
    /// "test data behaving as designed".
    @Test("an edge whose memory is gone does not count as a memory")
    func orphanedEdgesDoNotCount() throws {
        let storage = StorageService(inMemory: true)
        let live = try storage.createEntry(content: "still here", inputType: .typed)
        let ref = try storage.createVoiceFragment(for: live, audioFilename: "a.caf", transcript: "words")
        try storage.viewContext.save()

        // A second edge with NO memory behind it — the shape a CloudKit
        // import produces when the edge lands before (or without) its memory.
        let orphan = MemoryClipEdge(context: storage.viewContext)
        orphan.id = UUID()
        orphan.clipId = ref.id
        orphan.memoryId = UUID()      // points at nothing
        orphan.clip = ref
        orphan.memory = nil
        orphan.linkedAt = Date()
        try storage.viewContext.save()
        #expect(ref.edgeCount == 2, "precondition: two edges, one of them orphaned")

        let snap = RecordingsExport.snapshot(context: storage.viewContext, manifestClips: [])
        let rec = try #require(snap.recordings.first { $0.id == ref.id })
        #expect(rec.memoryIds == [live.id], """
            The orphaned edge was counted as a memory. A recording's memory             count decides whether its loss is referenced data or an orphan.
            """)
    }
}
