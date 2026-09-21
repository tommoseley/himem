import Foundation
import CoreData
@testable import HiMem

/// Builds a `MemoryClipEdge` directly, without going through
/// `StorageService.createEdge`.
///
/// **THE NAME IS NOW HISTORICAL IN A SECOND SENSE — read this before using it.**
///
/// It was written for F2 (Tom, 2026-09-16), which made *a part belongs to
/// exactly one memory* a write-side invariant: `createEdge` refused a second
/// live memory, so a test that needed a part in two memories had to route
/// around the guard, and this was the one sanctioned way to do it. Its
/// docstring said, in bold, never to use it for a new attachment.
///
/// **F2 retired 2026-09-21** — `The descoping · synopsis.md` walks many-to-many
/// back explicitly, and nothing refuses a second memory any more. So there is
/// no longer any such thing as "pre-invariant data": a part in several memories
/// is **ordinary data**, and `createEdge` will make one for you.
///
/// It is kept because ten-plus suites build fixtures with it and rewriting
/// those call sites would be churn with no behavioural content. But:
///
/// - **Prefer `StorageService.createEdge` in new tests.** It exercises the
///   production path, including the pair idempotency that did *not* retire
///   with F2, and this helper skips it.
/// - **The old warning no longer applies**, and is removed rather than left to
///   be obeyed out of habit — an instruction that has stopped being true is
///   worse than none, because it is followed with confidence.
/// - The name is left alone on purpose: renaming it would touch every call
///   site, which is the churn keeping it was meant to avoid. This paragraph is
///   the correction.
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
