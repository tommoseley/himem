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

    /// Hands-free capture (Siri / "Hey Siri" App Intent). Ad-hoc by
    /// definition: it always lands on the Clips bench as a loose clip and is
    /// NEVER forced into a memory, regardless of the visible tab — the locked
    /// invariant "capture never forced into a memory"
    /// (`HiMem · evidence and context.md:143`). Also gates the hands-free
    /// recording cap (Voice Settings).
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
        // Ad-hoc / hands-free capture is never forced into a memory — it always
        // lands on the bench as a loose clip, regardless of the visible tab
        // (locked invariant). Structured intent (a real memory) requires the
        // user to be inside a container on purpose, which Siri capture isn't.
        if source == .handsFree {
            return .dropOnBench
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
