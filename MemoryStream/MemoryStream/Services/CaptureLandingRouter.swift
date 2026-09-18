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

// `CaptureSource` RETIRED 2026-09-18, and it collapsed rather than shrank.
//
// It had two cases. `.handsFree` marked a Siri capture, and did two unrelated
// jobs: it forced the landing (bench first, then — after F3 — a memory from
// every screen), and it gated the walk-away recording cap. The intent fold
// removed the only producer of `.handsFree`: `StartVoiceRecordingIntent` is
// now `CreateEntryIntent`, which writes a memory directly and never opens a
// recorder, so no capture is hands-free any more.
//
// **A one-valued enum threaded through the router is a decoy the moment it
// exists** (Tom, 2026-09-18), so the parameter went with the case rather than
// being left defaulted. The routing is the tab's alone again.

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
    static func route(tab: Tab, projectContext: UUID?) -> CaptureLandingIntent {
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
