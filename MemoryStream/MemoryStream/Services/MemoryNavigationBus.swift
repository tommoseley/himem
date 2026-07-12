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

    @Published var pendingOpenMemoryId: UUID? = nil

    private init() {}
}
