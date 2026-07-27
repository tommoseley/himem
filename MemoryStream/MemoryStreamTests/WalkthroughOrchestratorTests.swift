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
        o.recordingDidStart();    #expect(o.activeBeat == .onARoll, "mic hot → on-a-roll beat (1b)")
        o.clipDidLand();          #expect(o.activeBeat == .clipLanded, "stop without Next → clip lands")
        o.advance();              #expect(o.activeBeat == .concept)
        o.advance();              #expect(o.activeBeat == .makeMemory)
        o.memoryDidStart();       #expect(o.activeBeat == .organize)
        o.organizeDidComplete();  #expect(o.activeBeat == .done)
        o.advance();              #expect(o.activeBeat == nil && o.hasCompleted)
        reset()
    }

    /// The on-a-roll path: recording starts → 1b → the user taps Next (retires
    /// the banner into the silent `rolling` hold) → stops → the clip lands.
    @Test func onARollPath_nextTapRetiresBannerThenClipLands() {
        reset()
        o.start(); o.beginFromOffer()
        o.recordingDidStart();  #expect(o.activeBeat == .onARoll)
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "Next retires the banner but stays armed")
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "further Next taps are no-ops")
        o.clipDidLand();        #expect(o.activeBeat == .clipLanded, "rolling → clipLanded when the clip lands")
        reset()
    }

    /// Beat 1b never advances on a tap of its banner — only the real signals
    /// (Next tapped, or recording stopped) move it.
    @Test func onARollBeat_ignoresTaps_waitsForRealSignal() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        #expect(o.activeBeat == .onARoll)
        o.advance(); #expect(o.activeBeat == .onARoll, "onARoll ignores taps")
        reset()
    }

    /// Discarding the recording mid-walkthrough returns to the `record` prompt
    /// so the flow isn't stranded on an in-composer beat once the composer
    /// dismisses. Works from both `onARoll` and the silent `rolling` hold.
    @Test func recordingCancel_returnsToRecordPrompt() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        o.recordingDidCancel(); #expect(o.activeBeat == .record, "cancel from onARoll → record")
        o.recordingDidStart(); o.nextClipStarted()
        #expect(o.activeBeat == .rolling)
        o.recordingDidCancel(); #expect(o.activeBeat == .record, "cancel from rolling → record")
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

    @Test func onARollBeat_namesNext() {
        // 1b must name the control it points at (F7e — the banner is anchored
        // to the Next glyph, so "tap here" would have no referent).
        let copy = WalkthroughOrchestrator.Beat.onARoll.body(isPlus: false)
        #expect(copy.contains("Next"), "on-a-roll copy names the Next control")
        // Tier-independent: Free and Plus read identically.
        #expect(copy == WalkthroughOrchestrator.Beat.onARoll.body(isPlus: true))
    }

    @Test func conceptBeat_carriesTheLoadBearingSentence() {
        #expect(WalkthroughOrchestrator.Beat.concept.body(isPlus: false)
            .contains("A memory is made of one or more clips"))
        // And beat 2 says it at the moment of evidence (Tom's added change).
        #expect(WalkthroughOrchestrator.Beat.clipLanded.body(isPlus: false)
            .contains("Clips are the building blocks of memories"))
    }
}
