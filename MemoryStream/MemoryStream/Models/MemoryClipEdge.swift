import Foundation
import CoreData

/// Associative entity linking a `MediaReference` (evidence) to a
/// `JournalEntry` (memory). One clip can be attached to N memories
/// via N edges; each edge carries its own annotation, ordering, and
/// linkedAt timestamp. Locked v1 ontology — see
/// `docs/design/HiMem · evidence and context.md`.
///
/// **Membership is exclusively encoded on the edge.** Reads walk
/// `memory.edges` or `clip.edges`; never `ref.entry`.
///
/// **Uniqueness is enforced at the application layer**, not by a Core
/// Data uniqueness constraint. NSPersistentCloudKitContainer documents
/// that uniqueness constraints on Cloud-synced entities are ignored,
/// so the constraint would only fire in a Local-only test context —
/// misleading. The migration + write paths dedup by `(clipId, memoryId)`
/// via `MemoryClipEdge.exists(clipId:memoryId:in:)`.
@objc(MemoryClipEdge)
public class MemoryClipEdge: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    /// Denormalized FK to `MediaReference.id`. Redundant with the
    /// `clip` relationship, but present so CloudKit queries and the
    /// uniqueness constraint have a scalar to key on.
    @NSManaged public var clipId: UUID
    /// Denormalized FK to `JournalEntry.id`. Same rationale as `clipId`.
    @NSManaged public var memoryId: UUID
    /// Optional annotation — "why this matters here." Post-v1 UI writes.
    @NSManaged public var annotation: String?
    /// Position within the memory's chronological stream. `0` = first.
    @NSManaged public var orderInMemory: Int16
    /// When this edge was created. Enables "added later" surfacing.
    ///
    /// **Optional in the Core Data model** (`linkedAt` is
    /// `optional="YES"` in `MemoryStream 3.xcdatamodel`), so the
    /// Swift declaration must be `Date?` to match — a non-optional
    /// `@NSManaged` accessor traps with `EXC_BREAKPOINT` when the
    /// underlying cell is nil. This nil-safe declaration retires
    /// the July 11 2026 crash Tom hit at `JournalEntry.edgesArray`
    /// (`edgesArray` was sorting on `lhs.linkedAt < rhs.linkedAt`
    /// and traps mid-comparison the moment either side is nil).
    /// Comparison sites fall back to `.distantPast` — a stable
    /// bottom of the sort so nil-linkedAt edges sink to the end.
    @NSManaged public var linkedAt: Date?
    @NSManaged public var clip: MediaReference?
    @NSManaged public var memory: JournalEntry?
}
