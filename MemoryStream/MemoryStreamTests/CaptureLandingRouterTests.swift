import Testing
import Foundation
@testable import HiMem

/// Money tests for `CaptureLandingRouter` — the pure decision that
/// implements the July 10 2026 context-aware-FAB lock. See
/// `CLAUDE.md:142` and `HiMem · evidence and context.md:143`:
///
/// > + creates one of whatever you're looking at a collection of.
///
/// The routing bug the lock retires: pre-July 10, every tab's FAB
/// called `JournalCaptureCoordinator.createNewMemory`, so the Clips-
/// tab + created a hidden JournalEntry (not visible on the bench),
/// the Projects-tab + created a memory with no project association
/// even inside a project detail, and no path led to "new project."
@Suite(.serialized)
struct CaptureLandingRouterTests {

    @Test func clips_tab_drops_on_bench() {
        let intent = CaptureLandingRouter.route(tab: .clips, projectContext: nil)
        #expect(intent == .dropOnBench)
    }

    @Test func clips_tab_ignores_project_context() {
        // Defensive: the project context should never be set while
        // Clips is the active tab, but if it leaks the router still
        // routes Clips to the bench (never creating a memory).
        let intent = CaptureLandingRouter.route(tab: .clips, projectContext: UUID())
        #expect(intent == .dropOnBench)
    }

    @Test func memories_tab_creates_memory() {
        let intent = CaptureLandingRouter.route(tab: .memories, projectContext: nil)
        #expect(intent == .createMemory)
    }

    @Test func projects_tab_at_list_opens_new_project_sheet() {
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: nil)
        #expect(intent == .openNewProjectSheet)
    }

    @Test func projects_tab_inside_project_creates_memory_in_that_project() {
        let projectId = UUID()
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: projectId)
        #expect(intent == .createMemoryInProject(projectId))
    }

    // MARK: - Hands-free (Siri) source — TestFlight #4a-Siri (2026-07-25)
    // Ad-hoc capture is never forced into a memory (locked invariant). A Siri
    // recording lands on the Clips bench regardless of the visible tab — the
    // bug: on the cold-launch default Memories tab it was building a hidden
    // "Untitled memory."

    @Test func handsFree_on_memories_lands_on_bench_not_a_memory() {
        // The money test: this returned `.createMemory` before the fix.
        let intent = CaptureLandingRouter.route(tab: .memories, projectContext: nil, source: .handsFree)
        #expect(intent == .dropOnBench)
    }

    @Test func handsFree_inside_project_lands_on_bench_not_in_project() {
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: UUID(), source: .handsFree)
        #expect(intent == .dropOnBench)
    }

    @Test func handsFree_on_projects_list_lands_on_bench_not_new_project_sheet() {
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: nil, source: .handsFree)
        #expect(intent == .dropOnBench)
    }

    @Test func handsFree_on_clips_still_bench() {
        let intent = CaptureLandingRouter.route(tab: .clips, projectContext: nil, source: .handsFree)
        #expect(intent == .dropOnBench)
    }

    @Test func manual_source_is_the_default_and_unchanged() {
        // Explicit `.manual` matches the default-param behavior the existing
        // tests exercise — the tab still decides.
        #expect(CaptureLandingRouter.route(tab: .memories, projectContext: nil, source: .manual) == .createMemory)
        #expect(CaptureLandingRouter.route(tab: .memories, projectContext: nil) == .createMemory)
    }
}
