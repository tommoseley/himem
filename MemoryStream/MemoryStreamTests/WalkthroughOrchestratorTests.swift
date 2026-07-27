import Testing
import Foundation
@testable import HiMem

/// F8 · money tests for the guided-walkthrough state machine. The pipeline
/// beats (record / makeMemory / organize) must advance ONLY on the real signal,
/// never on a tap — so guidance can't get ahead of the user. First-run offers
/// once; skip and complete both mark it done; "Show me around" always relaunches.
///
/// `.serialized` — the orchestrator is a shared singleton with a
/// UserDefaults-backed `completed` flag.
@MainActor
@Suite(.serialized)
struct WalkthroughOrchestratorTests {

    private var o: WalkthroughOrchestrator { .shared }

    /// Reset the singleton to a clean not-run, not-completed state.
    private func reset() {
        o.skip()                       // clears activeBeat, sets completed
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        o.activeBeat = nil
    }

    @Test func firstRun_offersOnce_thenNotAfterComplete() {
        reset()
        o.offerIfFirstRun()
        #expect(o.activeBeat == .offer, "first run offers the walkthrough")

        o.skip()
        #expect(o.activeBeat == nil && o.hasCompleted, "skip completes + closes")

        o.offerIfFirstRun()
        #expect(o.activeBeat == nil, "not re-offered once completed/skipped")
    }

    @Test func showMeAround_relaunches_evenAfterComplete() {
        reset()
        o.skip()                       // completed
        o.start()                      // "? → Show me around"
        #expect(o.activeBeat == .offer, "relaunch ignores the completed flag")
        reset()
    }

    @Test func happyPath_advancesThroughEveryBeatInOrder() {
        reset()
        o.offerIfFirstRun();      #expect(o.activeBeat == .offer)
        o.beginFromOffer();       #expect(o.activeBeat == .record)
        o.clipDidLand();          #expect(o.activeBeat == .clipLanded)
        o.advance();              #expect(o.activeBeat == .concept)
        o.advance();              #expect(o.activeBeat == .makeMemory)
        o.memoryDidStart();       #expect(o.activeBeat == .organize)
        o.organizeDidComplete();  #expect(o.activeBeat == .done)
        o.advance();              #expect(o.activeBeat == nil && o.hasCompleted)
        reset()
    }

    /// The load-bearing invariant: a pipeline beat NEVER advances on a tap — it
    /// waits for the real signal, so the coaching can't run ahead of the user.
    @Test func pipelineBeats_ignoreTaps_waitForRealSignal() {
        reset()
        o.start(); o.beginFromOffer()
        #expect(o.activeBeat == .record)
        o.advance(); #expect(o.activeBeat == .record, "record ignores taps — waits for clipDidLand")
        o.clipDidLand(); o.advance()      // clipLanded → concept
        o.advance()                       // concept → makeMemory
        #expect(o.activeBeat == .makeMemory)
        o.advance(); #expect(o.activeBeat == .makeMemory, "makeMemory ignores taps — waits for memoryDidStart")
        o.memoryDidStart()
        #expect(o.activeBeat == .organize)
        o.advance(); #expect(o.activeBeat == .organize, "organize ignores taps — waits for organizeDidComplete")
        reset()
    }

    /// A stale signal for a beat we're not on is ignored (no jumping).
    @Test func outOfOrderSignals_areIgnored() {
        reset()
        o.start()
        o.organizeDidComplete()   // not on .organize
        #expect(o.activeBeat == .offer, "a signal for a distant beat does nothing")
        o.clipDidLand()           // not on .record
        #expect(o.activeBeat == .offer)
        reset()
    }

    // MARK: - Copy (F7e / F7g)

    @Test func organizeBeat_isTierAware() {
        let free = WalkthroughOrchestrator.Beat.organize.body(isPlus: false)
        let plus = WalkthroughOrchestrator.Beat.organize.body(isPlus: true)
        #expect(free.contains("Tap Organize"), "Free guides the tap")
        #expect(plus.contains("already read"), "Plus narrates — no button that isn't there")
        #expect(free != plus)
    }

    @Test func noBeatCopyUsesTheWordEvidence() {
        for beat in WalkthroughOrchestrator.Beat.allCases {
            let f = beat.body(isPlus: false).lowercased()
            let p = beat.body(isPlus: true).lowercased()
            #expect(!f.contains("evidence") && !p.contains("evidence"),
                    "F7g: no user-facing 'evidence' in walkthrough copy — beat \(beat)")
        }
    }

    @Test func conceptBeat_carriesTheLoadBearingSentence() {
        #expect(WalkthroughOrchestrator.Beat.concept.body(isPlus: false)
            .contains("A memory is made of one or more clips"))
        // And beat 2 says it at the moment of evidence (Tom's added change).
        #expect(WalkthroughOrchestrator.Beat.clipLanded.body(isPlus: false)
            .contains("Clips are the building blocks of memories"))
    }
}
