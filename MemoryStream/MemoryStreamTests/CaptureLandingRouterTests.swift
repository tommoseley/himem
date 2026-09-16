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

    // MARK: - Hands-free (Siri) source
    //
    // **F3 · the answer changed; the question did not** (Tom, 2026-09-16).
    //
    // These tests used to assert `.dropOnBench` for every hands-free capture —
    // the July 2026 lock that ad-hoc capture is *never forced into a memory*,
    // because the bench was the alternative destination. The vocabulary
    // retirement deletes the bench, so that invariant's PREMISE EXPIRED: with
    // no second destination there is nothing left for the rule to protect.
    // (Same shape as D1's expired premise — the rule did not become wrong, the
    // world it described moved.)
    //
    // `StartVoiceRecordingIntent` now creates a memory of one voice part.
    // The subject of these tests — *where does a hands-free capture land?* —
    // is unchanged, so they are REWRITTEN rather than retired; only the
    // expected answer moved.
    //
    // The branch is INVERTED, not deleted. Falling through to the tab would
    // route a Siri recording made on the Projects list to
    // `.openNewProjectSheet` — a sheet that cannot hold a recording, and with
    // the bench gone there is no fallback to catch it. Hands-free capture has
    // one destination, and it is the same one from every screen.

    @Test func handsFree_on_memories_createsAMemory() {
        let intent = CaptureLandingRouter.route(tab: .memories, projectContext: nil, source: .handsFree)
        #expect(intent == .createMemory)
    }

    @Test func handsFree_insideAProject_createsAPlainMemory_notOneInThatProject() {
        // She is not filing; she is catching a thought hands-free. The memory
        // is discovered in the Memories list, newest first — it does not
        // silently join whatever project happened to be on screen.
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: UUID(), source: .handsFree)
        #expect(intent == .createMemory)
    }

    @Test func handsFree_onProjectsList_createsAMemory_neverTheNewProjectSheet() {
        // The hole that makes this an inversion rather than a deletion: a
        // recording cannot land in a name-and-goal sheet.
        let intent = CaptureLandingRouter.route(tab: .projects, projectContext: nil, source: .handsFree)
        #expect(intent == .createMemory)
    }

    @Test func handsFree_hasOneDestinationFromEveryScreen() {
        // The property, stated once: the visible tab does not influence a
        // hands-free landing at all. Enumerated rather than sampled, so a new
        // tab cannot quietly acquire its own hands-free behaviour.
        let everyScreen: [(CaptureLandingRouter.Tab, UUID?)] = [
            (.clips, nil), (.memories, nil), (.projects, nil), (.projects, UUID())
        ]
        for (tab, project) in everyScreen {
            #expect(
                CaptureLandingRouter.route(tab: tab, projectContext: project, source: .handsFree) == .createMemory,
                "hands-free must land identically from every screen; \(tab) differed"
            )
        }
    }

    @Test func manual_source_is_the_default_and_unchanged() {
        // Explicit `.manual` matches the default-param behavior the existing
        // tests exercise — the tab still decides.
        #expect(CaptureLandingRouter.route(tab: .memories, projectContext: nil, source: .manual) == .createMemory)
        #expect(CaptureLandingRouter.route(tab: .memories, projectContext: nil) == .createMemory)
    }
}
