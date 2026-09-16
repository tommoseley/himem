import Foundation

/// Decides what the FAB does per the July 10 2026 context-aware-FAB
/// lock (`CLAUDE.md:142` & `HiMem · evidence and context.md:143`):
///
/// > + creates one of whatever you're looking at a collection of.
/// > Clips list → a clip. Memories list → a memory. Projects list →
/// > a project. Inside a project → a memory-in-that-project.
///
/// Pure decision so the routing contract is unit-testable without
/// spinning up a view. Callers translate the intent into side
/// effects (bench dispatch, memory creation, sheet presentation).
enum CaptureLandingIntent: Equatable {
    /// Clips tab — capture lands as an `InboxClip` on the bench
    /// (voice) or unplaced `MediaReference` (photo/video/note). No
    /// navigation; the FAB and content stay on Clips.
    case dropOnBench

    /// Memories tab — capture creates a `JournalEntry` in the
    /// user's memory box. Structured intent; the composer already
    /// took care of the reflective setup.
    case createMemory

    /// Projects tab, inside a project detail — capture creates a
    /// memory *and* associates it with the current project. The
    /// project was the trigger; filing is automatic.
    case createMemoryInProject(UUID)

    /// Projects tab at the list level — + opens the New Project
    /// sheet (name + goal), the same sheet the "+ New project" row
    /// opens. No capture pipeline; no CapturedItem flows.
    case openNewProjectSheet
}

/// How a capture session was initiated. A property of *intent*, not
/// platform — it decides whether the completed capture is routed by the
/// visible tab (manual) or forced onto the bench (ad-hoc/hands-free).
enum CaptureSource: Equatable {
    /// User-initiated in-app capture — the tab-level FAB or a composer the
    /// user is actively holding. Routes by the visible tab per the July 10
    /// context-aware-FAB lock.
    case manual

    /// Hands-free capture (Siri / "Hey Siri" App Intent). It creates a memory
    /// of one voice part, identically from every screen — the visible tab and
    /// any live project context are ignored (F3, Tom 2026-09-16). It used to
    /// force the capture onto the Clips bench; that rule's premise expired
    /// with the bench.
    ///
    /// **THIS CASE HAS A SECOND JOB, AND IT IS NOT THE ROUTING ONE.** It also
    /// gates the hands-free recording cap — `VoiceCaptureScreen
    /// .shouldAutoSaveAtLimit` caps `.handsFree` and never `.manual`, because a
    /// recording nobody is holding must stop on its own. Do not delete this
    /// case on the grounds that its routing use has changed or gone: that
    /// would silently disable the walk-away cap with every routing test still
    /// green. `RecordingCapTests` is what bites, and it is mutation-verified
    /// against exactly that deletion.
    case handsFree
}

enum CaptureLandingRouter {

    /// The tab identifiers the shell defines. Kept as a local enum
    /// so the router doesn't take a dependency on `HiMemTabView`
    /// (a View), which would drag SwiftUI into the router's tests.
    enum Tab: Equatable {
        case clips
        case memories
        case projects
    }

    /// Return the intent for `tab` given the current project context
    /// (`nil` unless the user has a project detail on screen) and how the
    /// capture was initiated.
    static func route(tab: Tab, projectContext: UUID?, source: CaptureSource = .manual) -> CaptureLandingIntent {
        // **F3 · hands-free capture creates a memory of one voice part** (Tom,
        // 2026-09-16), from every screen, regardless of the visible tab.
        //
        // This branch used to return `.dropOnBench` under the July 2026 lock
        // that ad-hoc capture is *never forced into a memory*. **That rule's
        // premise expired rather than the rule being wrong:** it existed
        // because the bench was the alternative destination, and the
        // vocabulary retirement removes the bench. With no second destination
        // there is nothing left for it to protect. (The same shape as D1 —
        // the world the rule described moved.)
        //
        // INVERTED, not deleted. Falling through to the tab would route a Siri
        // recording made on the Projects list to `.openNewProjectSheet` — a
        // name-and-goal sheet that cannot hold a recording — and with the
        // bench gone there is no fallback to catch it. A live project context
        // is ignored for the same reason it is ignored on the Memories tab:
        // she is catching a thought hands-free, not filing one. The memory is
        // discovered in the Memories list, newest first.
        if source == .handsFree {
            return .createMemory
        }
        switch tab {
        case .clips:
            return .dropOnBench
        case .memories:
            return .createMemory
        case .projects:
            if let projectContext {
                return .createMemoryInProject(projectContext)
            } else {
                return .openNewProjectSheet
            }
        }
    }
}
