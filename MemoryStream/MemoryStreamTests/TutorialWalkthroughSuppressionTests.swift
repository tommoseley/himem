import Testing
import Foundation
@testable import HiMem

/// F9 · money tests (2026-07-28). The F8 guided walkthrough OWNS first-run
/// teaching, so the legacy auto-fire one-pager tutorials must NOT fire while it
/// runs, and are retired once it ends.
///
/// Root cause of "you abandoned me after step one": on the walkthrough's
/// `record` beat the composer opens and its `onAppear` calls
/// `TutorialOrchestrator.tryFire(.capture)`. Nothing suppressed the legacy
/// tutorial, so `visible` became `.capture`; the composer's auto-boot is gated
/// on `tutorialOrchestrator.visible == nil`, so recording never started and
/// beat 1 was terminal. Suppressing the legacy fire while the walkthrough runs
/// keeps `visible` nil → the recorder boots immediately, identical to the
/// non-walkthrough path.
///
/// Ruling (Tom 2026-07-28): suppress during the run, and mark `.capture` /
/// `.organizing` seen on completion OR abandonment — they stay pulled in
/// Settings → Learn.
///
/// `.serialized` — both orchestrators are shared singletons (UserDefaults- and
/// session-backed); see F6 (ambient global state) in the punch list. NOTE the
/// setup order in each test: `resetWalkthrough()` calls `skip()`, which now
/// retires the one-pagers, so `openTutorialGates()` (which clears seen) must run
/// AFTER it.
@MainActor
@Suite(.serialized)
struct TutorialWalkthroughSuppressionTests {

    /// Open every legacy-tutorial gate so only the walkthrough rule is under
    /// test: armed, unseen, no session/day cap, nothing visible. Call AFTER
    /// `resetWalkthrough()` (whose `skip()` marks the one-pagers seen).
    private func openTutorialGates() {
        let t = TutorialOrchestrator.shared
        t.debugResetAll()        // clears every hasSeen flag + session/day caps
        t.visible = nil
        t.armForReadyState()     // isArmed = true (post-onboarding)
    }

    private func resetWalkthrough() {
        let w = WalkthroughOrchestrator.shared
        w.skip()                 // clears activeBeat, sets completed, retires one-pagers
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        w.activeBeat = nil
    }

    /// RED before the F9 fix: `tryFire(.capture)` set `visible = .capture`
    /// during the walkthrough, stranding the composer's boot gate so recording
    /// never started.
    @Test func captureTutorial_suppressed_whileWalkthroughRuns() {
        resetWalkthrough()
        openTutorialGates()                                    // capture UNSEEN, armed
        WalkthroughOrchestrator.shared.activeBeat = .record    // walkthrough running

        TutorialOrchestrator.shared.tryFire(.capture)

        #expect(TutorialOrchestrator.shared.visible == nil,
                "the legacy capture one-pager must not fire during the F8 walkthrough — a non-nil `visible` strands the composer auto-boot (F9)")
        resetWalkthrough()
        TutorialOrchestrator.shared.visible = nil
    }

    /// The non-walkthrough path is unchanged: walkthrough idle + all gates open
    /// → the capture one-pager still fires exactly as before.
    @Test func captureTutorial_stillFires_whenWalkthroughIdle() {
        resetWalkthrough()          // walkthrough NOT running (activeBeat == nil)
        openTutorialGates()

        TutorialOrchestrator.shared.tryFire(.capture)

        #expect(TutorialOrchestrator.shared.visible == .capture,
                "outside the walkthrough the legacy auto-fire behavior is preserved")
        TutorialOrchestrator.shared.visible = nil
    }

    /// Completing the walkthrough retires the one-pagers it replaced — they
    /// never auto-fire again (pulled-only in Learn).
    @Test func completingWalkthrough_retiresCaptureAndOrganizing() {
        let w = WalkthroughOrchestrator.shared
        let t = TutorialOrchestrator.shared
        resetWalkthrough()
        t.debugResetAll()           // capture + organizing now UNSEEN
        w.activeBeat = .done
        w.advance()                 // done → ontology
        w.advance()                 // ontology → finish()

        #expect(w.activeBeat == nil, "walkthrough finished")
        #expect(t.hasSeen(.capture), "completing F8 retires the capture one-pager")
        #expect(t.hasSeen(.organizing), "completing F8 retires the organizing one-pager")
        resetWalkthrough()
    }

    /// Abandoning the walkthrough partway ALSO retires them — she chose out of
    /// guided teaching; a surprise one-pager later is the same confusion in
    /// reverse (Tom 2026-07-28).
    @Test func abandoningWalkthrough_alsoRetiresOnePagers() {
        let w = WalkthroughOrchestrator.shared
        let t = TutorialOrchestrator.shared
        resetWalkthrough()
        t.debugResetAll()           // UNSEEN
        w.activeBeat = .record       // partway through
        w.skip()                     // abandon

        #expect(w.activeBeat == nil, "abandoned")
        #expect(t.hasSeen(.capture) && t.hasSeen(.organizing),
                "abandoning F8 retires the one-pagers too")
        resetWalkthrough()
    }

    /// Beat 1b (on-a-roll) arms ONLY on the real `recordingDidStart()` signal —
    /// never on a card tap and never on mere composer appearance. A `gotIt()` on
    /// the record banner retires the card but leaves the walkthrough armed on
    /// `.record`; `advance()` (a tap) is a no-op. So beat 1b can't fire until the
    /// mic is actually hot.
    @Test func beat1b_armsOnlyOnRecordingStart_notOnTapOrAppearance() {
        resetWalkthrough()
        let w = WalkthroughOrchestrator.shared
        w.activeBeat = .record

        w.gotIt()
        #expect(w.activeBeat == .record && w.currentBannerRetired,
                "Got it retires the record banner but never advances a signal beat")
        w.advance()
        #expect(w.activeBeat == .record, "a tap can't fire beat 1b")

        w.recordingDidStart()
        #expect(w.activeBeat == .onARoll, "only the real mic-hot signal arms beat 1b")
        resetWalkthrough()
    }
}
