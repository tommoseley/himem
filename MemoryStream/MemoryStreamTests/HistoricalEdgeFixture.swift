import Foundation
import CoreData
@testable import HiMem

/// Builds a `MemoryClipEdge` **without** going through
/// `StorageService.createEdge`, so a test can construct a part that belongs to
/// more than one memory.
///
/// # This represents PRE-INVARIANT DATA. Never use it to test a new attachment.
///
/// F2 (Tom, 2026-09-16) made *a part belongs to exactly one memory* a
/// **write-side** invariant: `createEdge` refuses a second live memory. The
/// ruling deliberately preserves what is already stored — existing multi-memory
/// rows stay, there is no migration and no Production CloudKit deploy — so a
/// real device still carries parts with several memories, and the behaviour
/// that reads them (Let Go keeping shared clips, the P8 last-reference rule,
/// the honest connection count, the *"in N memories"* copy) must keep being
/// testable.
///
/// That is the only thing this helper is for: **manufacturing history**.
///
/// - Use it when the subject under test is how the app *reads or deletes*
///   data that already has several memories.
/// - **Do not** use it to set up an attachment the app would make today. A
///   test that wants a new edge must call `StorageService.createEdge` and get
///   the invariant enforced; routing around the guard to make a test pass is
///   how a guard stops guarding.
///
/// It exists as one shared helper rather than a private copy in each suite
/// because thirteen near-duplicate procedures is precisely the defect
/// `Handoff · punch list` F6a names — and thirteen copies of a route *around*
/// an invariant is the worst shape that defect takes.
enum HistoricalEdgeFixture {

    /// Attach `ref` to `entry` the way the store looks for data created before
    /// F2. Mirrors `StorageService.createEdge`'s field writes exactly, minus
    /// the guards, so the resulting row is indistinguishable from a real one.
    ///
    /// `annotation` is left nil: F2 also stopped the annotation being written,
    /// and a fixture should not manufacture a field production no longer
    /// produces. Tests that genuinely need a historical annotation should set
    /// it explicitly on the returned edge and say why.
    @discardableResult
    static func attach(
        _ ref: MediaReference,
        to entry: JournalEntry,
        in ctx: NSManagedObjectContext,
        linkedAt: Date = Date()
    ) throws -> MemoryClipEdge {
        let edge = MemoryClipEdge(context: ctx)
        edge.id = UUID()
        edge.clipId = ref.id
        edge.memoryId = entry.id
        edge.clip = ref
        edge.memory = entry
        edge.orderInMemory = Int16(entry.edgesArray.count)
        edge.linkedAt = linkedAt
        edge.annotation = nil
        try ctx.save()
        return edge
    }
}
