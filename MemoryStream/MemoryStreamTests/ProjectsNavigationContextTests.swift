import Testing
import Foundation
@testable import HiMem

/// Money tests for `ProjectsNavigationContext` — the shared, tab-level
/// signal that lets `HiMemTabView` know whether the user is currently
/// viewing a specific project detail.
///
/// Rationale (per `CLAUDE.md:142` July 10 lock): the Projects tab FAB
/// routes by *whether the user is inside a project*:
///   · At the project list → + opens New Project sheet
///   · Inside a project → + creates a memory in that project
///
/// The FAB lives at HiMemTabView; the project detail lives deep
/// inside `JournalView(initialMode: .projects) → ProjectListView →
/// ProjectDetailView`. This service is the seam so the FAB can see
/// what the JournalView navigation stack knows.
@MainActor
@Suite(.serialized)
struct ProjectsNavigationContextTests {

    private func withFreshContext(_ body: () throws -> Void) rethrows {
        let ctx = ProjectsNavigationContext.shared
        ctx.debugReset()
        defer { ctx.debugReset() }
        try body()
    }

    @Test func enter_sets_currentProjectId() throws {
        try withFreshContext {
            let id = UUID()
            let ctx = ProjectsNavigationContext.shared
            #expect(ctx.currentProjectId == nil)
            ctx.enter(projectId: id)
            #expect(ctx.currentProjectId == id)
        }
    }

    @Test func exit_clears_matching_projectId() throws {
        try withFreshContext {
            let id = UUID()
            let ctx = ProjectsNavigationContext.shared
            ctx.enter(projectId: id)
            ctx.exit(projectId: id)
            #expect(ctx.currentProjectId == nil)
        }
    }

    /// SwiftUI can fire `onDisappear` for a departing detail view
    /// AFTER `onAppear` fires for the incoming one (rapid drill
    /// between two projects, or NavigationStack replay on parent
    /// re-render). If exit clobbered blindly, the incoming project's
    /// context would be lost. Guard: exit only clears when the id
    /// matches.
    @Test func exit_does_not_clear_when_id_differs() throws {
        try withFreshContext {
            let departing = UUID()
            let incoming = UUID()
            let ctx = ProjectsNavigationContext.shared
            ctx.enter(projectId: incoming)
            ctx.exit(projectId: departing)
            #expect(ctx.currentProjectId == incoming,
                    "exit for a stale project must not clear the current one")
        }
    }
}
