import Testing
import Foundation
@testable import HiMem

/// **F25 — the Projects FAB created nothing.**
///
/// From inside a project, + → attach/photo completed and no object
/// existed. Per the July 10 context-aware-FAB lock it must create a
/// memory in that project.
///
/// ROOT CAUSE: the landing was decided at **completion**, from live
/// navigation state that the capture flow itself destroys.
/// `handleCapturedItem` read `ProjectsNavigationContext.currentProjectId`
/// when the capture finished — but the composer is hosted at the tab
/// shell, above the Projects `NavigationStack`, and photo/video present
/// as `fullScreenCover`, which removes the covered `ProjectDetailView`
/// and fires its `.onDisappear` → `exit(projectId:)` → context nil.
/// The route then fell to `.openNewProjectSheet`, whose handler was a
/// bare `break`. The item was dropped on the floor.
///
/// **`CaptureLandingRouter` was correct throughout.** A test of the
/// router alone stays green through the entire defect — the same trap
/// as F24, where the commit gate was right and nobody called it. So the
/// reproduction here is about ORDERING and about the CALLERS, not about
/// the routing table.
@Suite(.serialized)
struct CaptureLandingAtTapTimeTests {

    // MARK: - Characterisation: the trap the fix must survive

    /// Pins the mechanism. The identical inputs route two different ways
    /// either side of a context clear — which is exactly what the
    /// capture flow performs between tap and completion.
    @Test @MainActor func route_flipsToNewProjectSheet_whenContextIsClearedMidFlow() {
        let nav = ProjectsNavigationContext.shared
        nav.debugReset()
        defer { nav.debugReset() }

        let projectId = UUID()
        nav.enter(projectId: projectId)

        // At FAB-tap time, inside the project:
        let atTap = CaptureLandingRouter.route(
            tab: .projects, projectContext: nav.currentProjectId, source: .manual
        )
        #expect(atTap == .createMemoryInProject(projectId))

        // The composer covers ProjectDetailView → its onDisappear fires.
        nav.exit(projectId: projectId)
        #expect(nav.currentProjectId == nil)

        // At completion, same tab, same user intent — different answer.
        let atCompletion = CaptureLandingRouter.route(
            tab: .projects, projectContext: nav.currentProjectId, source: .manual
        )
        #expect(atCompletion == .openNewProjectSheet)
        #expect(atTap != atCompletion, "This inequality IS the defect: routing at completion loses the project.")
    }

    /// The `exit` guard protects against a *different* project's late
    /// disappear, not against the same view being covered and uncovered
    /// — which is why it did not save us here.
    @Test @MainActor func exitGuard_doesNotProtectAgainstSelfCover() {
        let nav = ProjectsNavigationContext.shared
        nav.debugReset()
        defer { nav.debugReset() }

        let projectId = UUID()
        nav.enter(projectId: projectId)
        nav.exit(projectId: UUID())            // a DIFFERENT project — guarded
        #expect(nav.currentProjectId == projectId)
        nav.exit(projectId: projectId)         // the SAME view, covered — clears
        #expect(nav.currentProjectId == nil)
    }

    /// Hands-free capture must keep landing on the bench regardless of
    /// context — the locked "capture is never forced into a memory"
    /// invariant, which the fix must not disturb.
    @Test @MainActor func handsFree_stillLandsOnBench_insideAProject() {
        let nav = ProjectsNavigationContext.shared
        nav.debugReset()
        defer { nav.debugReset() }
        nav.enter(projectId: UUID())
        #expect(
            CaptureLandingRouter.route(
                tab: .projects, projectContext: nav.currentProjectId, source: .handsFree
            ) == .dropOnBench
        )
    }

    // MARK: - Caller guards (the reproduction)

    /// `handleCapturedItem` must prefer the intent captured at tap time.
    @Test func handleCapturedItem_usesTheTapTimeIntent() throws {
        let body = try Self.functionBody(named: "private func handleCapturedItem(", in: Self.shellSource())
        #expect(
            body.contains("pendingLanding ??"),
            """
            `handleCapturedItem` re-derives the landing from live navigation \
            state instead of using the intent captured at tap. That is F25: \
            the capture flow clears the project context before this runs. \
            Body was:
            \(body)
            """
        )
    }

    /// `beginCapture` must pin the landing BEFORE presenting the
    /// composer — after is too late, the composer is what clears it.
    @Test func beginCapture_pinsTheLandingBeforePresenting() throws {
        let body = try Self.functionBody(named: "private func beginCapture(", in: Self.shellSource())
        guard let pinAt = body.range(of: "pendingLanding = CaptureLandingRouter.route")?.lowerBound,
              let presentAt = body.range(of: "activeCaptureModality = modality")?.lowerBound else {
            Issue.record("beginCapture no longer pins the landing and presents a modality.\n\(body)")
            return
        }
        #expect(pinAt < presentAt, "The landing must be pinned before the composer is presented.\n\(body)")
    }

    /// Every FAB path must go through `beginCapture`. Setting the
    /// modality directly from a FAB closure is how a caller silently
    /// stops consulting the decision — the class that has now produced
    /// five defects in eight days.
    @Test func noFabPathBypassesBeginCapture() throws {
        let src = try Self.shellSource()
        let offenders = src
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .filter { _, line in
                line.hasPrefix("onSelect:") && !line.contains("beginCapture")
            }
            .map { "\($0.offset + 1): \($0.element)" }
        #expect(offenders.isEmpty, "FAB onSelect bypasses beginCapture at:\n\(offenders.joined(separator: "\n"))")
    }

    /// The residual `.openNewProjectSheet` case must never silently drop
    /// a CapturedItem again. Loud in DEBUG, bench in release — nothing
    /// is destroyed either way.
    @Test func newProjectSheetCase_neverSilentlyDropsACapture() throws {
        let body = try Self.functionBody(named: "private func handleCapturedItem(", in: Self.shellSource())
        guard let caseAt = body.range(of: "case .openNewProjectSheet:")?.upperBound else {
            Issue.record("The .openNewProjectSheet case is gone — re-verify this guard.\n\(body)")
            return
        }
        let tail = String(body[caseAt...])
        #expect(tail.contains("assertionFailure"), "No assertionFailure — a stray capture would be silent in DEBUG.")
        #expect(tail.contains("PhoneCaptureBenchDispatcher.dispatch"),
                "No bench dispatch — a stray capture would be DESTROYED in release. This is the F25 drop.")
    }

    /// Self-test: the guard must reject the shipped `break`, or it is
    /// not guarding.
    @Test func guard_wouldRejectTheShippedBreak() {
        let shipped = """
                    // Unreachable: FAB variant for this intent never emits a
                    // CapturedItem; it opens the New Project sheet directly.
                    break
        """
        #expect(shipped.contains("assertionFailure") == false)
        #expect(shipped.contains("PhoneCaptureBenchDispatcher.dispatch") == false)
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.functionNotFound(needle)
        }
        var depth = 0
        var started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.functionNotFound(needle)
    }

    static func shellSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/HiMemTabView.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), functionNotFound(String) }
}
