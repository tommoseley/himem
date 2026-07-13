import Foundation

/// Session-scoped signal: "open Memory Detail for this memory."
/// Emitted by any surface that has just created / promoted a memory
/// out of the Clips → Sessions flow (`CreateMemoryFromClipsSheet`
/// on tap-Create), consumed by `HiMemTabView` (switch to Memories
/// tab) and by the memories-instance `JournalView` (push into
/// `EntryExpandedView`).
///
/// **Why a bus, not a direct push.** The create-flow lives inside
/// the Clips tab's navigation stack; the target detail view lives
/// inside the Memories tab's navigation stack. There's no shared
/// navigation path between them — the tab shell owns the switch,
/// each tab's `JournalView` owns its own `selectedEntryId`
/// `.navigationDestination(item:)`. This bus is the simplest
/// coordination point.
///
/// **Semantics.** A non-nil `pendingOpenMemoryId` means "the user
/// just materialised this memory and expects to land on it." The
/// consumer clears the id after routing so a subsequent identical
/// id can fire again (a rare but real case: user creates memory,
/// backs out, creates again).
///
/// Fixes the July 12 dogfood bug Tom reported: "The 'Create one
/// memory' button calls up the new memory, but when tap create,
/// nothing creates." The memory *was* being created; the user just
/// had no visible signal because the sheet dismissed back to the
/// calm Clips list.
@MainActor
final class MemoryNavigationBus: ObservableObject {
    static let shared = MemoryNavigationBus()

    /// Non-nil = a memory was just materialised from a session and the
    /// **"Memory created" toast** should show on Clips. The user stays
    /// on the Clips list per `Clip model · spec.md` §Start a Memory
    /// (July 12 2026 point 3): "Pop back to the Clips list. The
    /// session no longer exists as a session." The toast is the
    /// feedback; navigation is opt-in via its View button.
    @Published var justCreatedMemoryId: UUID? = nil

    /// Non-nil = the user explicitly asked to open Memory Detail for
    /// this id — currently only fired when they tap **View** on the
    /// created-memory toast. This is the signal `HiMemTabView`
    /// (switches to Memories) and `JournalView` (pushes
    /// `EntryExpandedView`) observe.
    @Published var pendingOpenMemoryId: UUID? = nil

    private init() {}
}
