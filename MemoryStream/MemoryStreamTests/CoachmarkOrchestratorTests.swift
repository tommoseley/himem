import Testing
import Foundation
@testable import HiMem

/// Money tests for the four locked guardrails on the per-tab
/// coachmark trigger per `docs/design/Tutorials · triggers spec.md`
/// §"Per-tab coachmark on first arrival (locked July 9 2026)."
///
/// The orchestrator is a singleton reading UserDefaults, so each test
/// swaps in a scratch domain to keep state isolated.
@MainActor
@Suite(.serialized)
struct CoachmarkOrchestratorTests {

    /// Fresh scratch UserDefaults suite, wiped for each test.
    private func withScratchDefaults(_ body: () throws -> Void) rethrows {
        let name = "himem.tests.coachmark.\(UUID().uuidString)"
        let scratch = UserDefaults(suiteName: name)!
        scratch.removePersistentDomain(forName: name)
        let previous = UserDefaults.standard
        // No public swap on singleton; instead, prime + verify keys
        // against the shared UserDefaults but restore at the end.
        let keys = [
            "himem.session.counter",
            CoachmarkOrchestrator.Kind.clips.rawValue,
            CoachmarkOrchestrator.Kind.memories.rawValue,
            CoachmarkOrchestrator.Kind.projects.rawValue,
        ]
        let backup = keys.reduce(into: [String: Any]()) { $0[$1] = previous.object(forKey: $1) }
        for k in keys { previous.removeObject(forKey: k) }
        defer {
            for k in keys { previous.removeObject(forKey: k) }
            for (k, v) in backup { previous.set(v, forKey: k) }
            // Reset orchestrator's transient state
            CoachmarkOrchestrator.shared.debugResetAll()
        }
        // Reset transient
        CoachmarkOrchestrator.shared.debugResetAll()
        UserDefaults.standard.removeObject(forKey: "himem.session.counter")
        try body()
    }

    // MARK: - Guardrail #4 · never on cold first launch

    /// On the first cold launch (`sessionCount == 1`) with no content,
    /// tryFire must NOT surface a coachmark. The empty-home hand-off
    /// stays the first-launch behavior.
    @Test func doesNotFireOnFirstColdLaunchWithNoContent() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession() // session 1
            o.tryFire(.memories, tabHasContent: false, suppressedByCaptureArrival: false)
            #expect(o.visible == nil)
        }
    }

    /// First cold launch but the tab has content (rare but possible on
    /// reinstall from iCloud restore): a tour anchored to content is
    /// fair game per the spec.
    @Test func firesOnFirstColdLaunchIfTabHasContent() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession() // session 1
            o.tryFire(.memories, tabHasContent: true, suppressedByCaptureArrival: false)
            #expect(o.visible == .memories)
        }
    }

    /// Second session eligibility — even with no content on this tab,
    /// the session gate has been met.
    @Test func firesOnSecondSessionEvenWithoutContent() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession() // 1
            o.armSession() // 2
            o.tryFire(.memories, tabHasContent: false, suppressedByCaptureArrival: false)
            #expect(o.visible == .memories)
        }
    }

    // MARK: - Guardrail #1 · once ever per tab

    /// After a dismiss, subsequent tryFires for the same tab are
    /// no-ops (the persisted `seenCoachmark_<tab>` flag holds).
    @Test func neverFiresTwiceForSameTab() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession()
            o.armSession()
            o.tryFire(.clips, tabHasContent: true, suppressedByCaptureArrival: false)
            #expect(o.visible == .clips)
            o.dismiss(.clips)
            #expect(o.visible == nil)
            #expect(o.hasSeen(.clips))
            // Second attempt: silent no-op
            o.tryFire(.clips, tabHasContent: true, suppressedByCaptureArrival: false)
            #expect(o.visible == nil)
        }
    }

    // MARK: - Guardrail #3 · suppress Clips when arriving from capture

    /// Landing on Clips right after a capture commit must NOT surface
    /// the Clips coachmark — the user is mid-thought. Skip until a
    /// neutral arrival.
    @Test func clipsCoachmarkIsSuppressedWhenArrivingFromCapture() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession()
            o.armSession()
            o.tryFire(.clips, tabHasContent: true, suppressedByCaptureArrival: true)
            #expect(o.visible == nil)
            #expect(o.hasSeen(.clips) == false, "Suppression must NOT count as seen — the next neutral arrival still fires it.")
        }
    }

    /// After a suppressed arrival, the next neutral arrival at Clips
    /// does surface the coachmark.
    @Test func clipsCoachmarkFiresOnNextNeutralArrival() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession()
            o.armSession()
            // Arrival #1 — suppressed
            o.tryFire(.clips, tabHasContent: true, suppressedByCaptureArrival: true)
            #expect(o.visible == nil)
            // Arrival #2 — neutral
            o.tryFire(.clips, tabHasContent: true, suppressedByCaptureArrival: false)
            #expect(o.visible == .clips)
        }
    }

    // MARK: - Guardrail #5 · Skip marks seen instantly

    @Test func dismissMarksSeenImmediately() throws {
        try withScratchDefaults {
            let o = CoachmarkOrchestrator.shared
            o.armSession()
            o.armSession()
            o.tryFire(.projects, tabHasContent: true, suppressedByCaptureArrival: false)
            #expect(o.visible == .projects)
            o.dismiss(.projects)
            #expect(o.hasSeen(.projects))
            #expect(o.visible == nil)
        }
    }
}
