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

/// Session-scoped signal: "navigate to the Memories list filtered by
/// this topic." Emitted when the user taps a topic **read chip** on an
/// opened memory (the unified associations read model — read chips
/// navigate to where each association lives; a topic lives in the
/// Memories-list filter). Consumed by `HiMemTabView` (switch to the
/// Memories tab) and the memories-instance `JournalView` (pop any pushed
/// detail + set `selectedTopic`, driving the already-working filter).
///
/// Mirrors `pendingOpenMemoryId`'s two-observer shape. A topic chip can
/// be tapped on a memory opened from *any* tab (Memories, or a member
/// memory inside a Project), so the bus + tab switch is what makes the
/// navigation uniform regardless of entry point.
///
/// Not persisted. Cleared by the consumer after routing.
@MainActor
final class TopicFilterBus: ObservableObject {
    static let shared = TopicFilterBus()

    /// Non-nil = route to Memories filtered by this topic name. The
    /// memories `JournalView` clears it after applying the filter.
    @Published var pendingTopicFilter: String? = nil

    private init() {}

    func request(_ topic: String) {
        pendingTopicFilter = topic
    }
}

/// Session-scoped signal: "open this project." Emitted when the user taps
/// a project **read chip** on an opened memory (unified associations read
/// model — a project chip navigates to the project it names). Consumed by
/// `HiMemTabView` (switch to the Projects tab) and `ProjectListView`
/// (push `ProjectDetailView` for the id). Mirrors `TopicFilterBus`; works
/// from a memory opened in any tab, since the bus + tab switch is uniform.
///
/// Not persisted. Cleared by the consumer after routing.
@MainActor
final class ProjectOpenBus: ObservableObject {
    static let shared = ProjectOpenBus()

    /// Non-nil = open the project with this id on the Projects tab. The
    /// projects `ProjectListView` clears it after pushing the detail.
    @Published var pendingProjectId: UUID? = nil

    private init() {}

    func request(_ projectId: UUID) {
        pendingProjectId = projectId
    }
}
