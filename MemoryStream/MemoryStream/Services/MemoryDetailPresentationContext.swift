import Foundation

/// Shared, tab-level state: which memory (if any) the user is
/// currently viewing in `EntryExpandedView`. Wired by
/// `EntryExpandedView.onAppear/onDisappear` and read by
/// `HiMemTabView` so the tab-shell FAB can step aside — Memory
/// Detail has its own `AppendFAB` for the "append to this memory"
/// case, and rendering both stacked is the July 11 2026 "two RABs"
/// bug Tom hit.
///
/// Same pattern as `ProjectsNavigationContext` — see that file for
/// the id-matched enter/exit rationale (prevents a departing view's
/// disappear from clobbering the incoming view's appear during
/// rapid drill-to-drill).
@MainActor
final class MemoryDetailPresentationContext: ObservableObject {

    static let shared = MemoryDetailPresentationContext()

    /// Non-nil while an `EntryExpandedView` is on screen. Nil at
    /// every list-level surface (Memories list, Clips, Projects
    /// list, Project Detail).
    @Published private(set) var currentMemoryId: UUID? = nil

    private init() {}

    func enter(memoryId: UUID) {
        currentMemoryId = memoryId
    }

    /// Only clears when `memoryId` matches the current — see
    /// `ProjectsNavigationContext.exit` for the rapid-drill
    /// rationale.
    func exit(memoryId: UUID) {
        if currentMemoryId == memoryId {
            currentMemoryId = nil
        }
    }

    #if DEBUG
    func debugReset() {
        currentMemoryId = nil
    }
    #endif
}
