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

    // THE HANDS-FREE SUITE IS RETIRED BY SUPERSESSION (2026-09-18), and this
    // time the SUBJECT went, not just the answer.
    //
    //   handsFree_on_memories_createsAMemory
    //   handsFree_insideAProject_createsAPlainMemory_notOneInThatProject
    //   handsFree_onProjectsList_createsAMemory_neverTheNewProjectSheet
    //   handsFree_hasOneDestinationFromEveryScreen
    //
    // F3 rewrote these rather than retiring them, because the question — *where
    // does a hands-free capture land?* — still had an answer; only the answer
    // had moved. The intent fold removes the question: `StartVoiceRecordingIntent`
    // is now `CreateEntryIntent`, which writes a memory directly and never opens
    // a recorder, so no capture is hands-free and `CaptureSource` is gone.
    //
    // Nothing is left unguarded. A Siri capture's landing is now asserted where
    // it happens — `CreateEntryIntent` calls `createEntry(content:inputType:)`
    // — rather than through a routing table it no longer consults.

    /// The tab decides, and it is the ONLY thing that decides. Kept as the
    /// positive statement of what replaced the source parameter.
    @Test func theTabIsTheOnlyInput() {
        #expect(CaptureLandingRouter.route(tab: .memories, projectContext: nil) == .createMemory)
        #expect(CaptureLandingRouter.route(tab: .clips, projectContext: nil) == .dropOnBench)
    }
}
