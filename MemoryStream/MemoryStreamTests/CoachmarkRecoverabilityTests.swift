import Testing
import Foundation
@testable import HiMem

/// Money tests for F2b · coachmark recoverability (2026-07-26). The testable
/// seam per the directive: "Show me around" clears every per-tab seen flag and
/// re-arms the current tab's coachmark — WITHOUT resetting the session counter
/// (the user is past the second-session gate; a manual restore must re-coach
/// now, not wait for a cold launch). Card copy/placement is visual (device).
///
/// `.serialized` — mutates the `CoachmarkOrchestrator.shared` singleton and its
/// UserDefaults-backed flags.
@MainActor
@Suite(.serialized)
struct CoachmarkRecoverabilityTests {

    private var orchestrator: CoachmarkOrchestrator { .shared }

    @Test func restoreTour_clearsEverySeenFlag_andArms() {
        let o = orchestrator
        o.debugResetAll()
        // Simulate a user who has dismissed all three tabs' coachmarks.
        for kind in CoachmarkOrchestrator.Kind.allCases { o.dismiss(kind) }
        #expect(CoachmarkOrchestrator.Kind.allCases.allSatisfy { o.hasSeen($0) })

        o.restoreTour()

        #expect(CoachmarkOrchestrator.Kind.allCases.allSatisfy { !o.hasSeen($0) },
                "every per-tab seen flag is cleared — each tab re-coaches on first visit")
        #expect(o.restorePending, "the current tab's re-fire is armed for the hub to close")
        o.debugResetAll()
    }

    @Test func restoreTour_preservesSessionCounter() {
        let o = orchestrator
        o.debugResetAll()               // counter → 0
        o.armSession(); o.armSession()  // two cold launches → 2
        #expect(o.sessionCount == 2)

        o.restoreTour()

        #expect(o.sessionCount == 2,
                "restore must NOT reset the session gate — the user is past it")
        o.debugResetAll()
    }

    @Test func consumeRestore_firesCurrentTab_clearsPending() {
        let o = orchestrator
        o.debugResetAll()
        o.restoreTour()
        #expect(o.restorePending)

        o.consumeRestore(currentTab: .memories)

        #expect(o.visible == .memories, "the current tab's coachmark fires now")
        #expect(!o.restorePending, "pending consumed")
        o.debugResetAll()
    }

    /// The explicit-request path bypasses the session/content gate `tryFire`
    /// enforces — the user asked for the tour by name.
    @Test func forceFire_bypassesSessionAndContentGate() {
        let o = orchestrator
        o.debugResetAll()                 // sessionCount == 0, nothing seen
        // tryFire would NOT fire: gate requires sessionCount >= 2 OR content.
        o.tryFire(.projects, tabHasContent: false)
        #expect(o.visible == nil, "gate holds for the passive trigger")

        o.forceFire(.projects)
        #expect(o.visible == .projects, "explicit restore fires regardless of gate")
        o.debugResetAll()
    }

    /// After a restore, a passive first-visit re-coaches too (the user is past
    /// the session gate, so `tryFire` passes on the cleared flag).
    @Test func afterRestore_passiveTryFire_reCoachesOtherTabs() {
        let o = orchestrator
        o.debugResetAll()
        o.armSession(); o.armSession()    // past the second-session gate
        o.dismiss(.clips)                 // clips already seen
        o.restoreTour()                   // clears it
        o.consumeRestore(currentTab: .memories)  // current tab fired
        o.dismiss(.memories)              // user dismisses it → visible nil

        // Visiting clips again now re-coaches (flag was cleared by restore).
        o.tryFire(.clips, tabHasContent: false)
        #expect(o.visible == .clips)
        o.debugResetAll()
    }
}
