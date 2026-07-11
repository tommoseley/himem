import Foundation

/// Shared, tab-level state: which project (if any) the user is
/// currently viewing. Wired by `ProjectDetailView.onAppear/onDisappear`
/// and read by `HiMemTabView` to route the FAB per the July 10 2026
/// context-aware-FAB lock.
///
/// From `CLAUDE.md` §Phone line 142:
/// > On Projects, + acts on the unit of the surface you're on: at the
/// > project list level it creates a new project; inside a project it
/// > creates a memory in that project.
///
/// The FAB is at the tab-shell level and can't see JournalView's
/// internal NavigationStack depth. This service is the seam — the
/// only thing FAB code needs is *"is the user inside a project, and
/// if so which one?"*, which is exactly what `currentProjectId`
/// answers.
@MainActor
final class ProjectsNavigationContext: ObservableObject {

    static let shared = ProjectsNavigationContext()

    /// Non-nil while a `ProjectDetailView` is on screen; nil at the
    /// Projects list level (or when the Projects tab isn't active).
    @Published private(set) var currentProjectId: UUID? = nil

    private init() {}

    /// Called from `ProjectDetailView.onAppear`.
    func enter(projectId: UUID) {
        currentProjectId = projectId
    }

    /// Called from `ProjectDetailView.onDisappear`. Only clears when
    /// `projectId` matches the current — SwiftUI can fire the
    /// departing view's disappear AFTER the incoming view's appear
    /// (rapid drill between two projects, or NavigationStack replay
    /// on a parent re-render). A blind clear would clobber the
    /// newly-arrived context and leave the FAB in list mode inside
    /// the actual detail view. See test
    /// `exit_does_not_clear_when_id_differs`.
    func exit(projectId: UUID) {
        if currentProjectId == projectId {
            currentProjectId = nil
        }
    }

    #if DEBUG
    /// Test-only reset. Not exposed in release builds.
    func debugReset() {
        currentProjectId = nil
    }
    #endif
}
