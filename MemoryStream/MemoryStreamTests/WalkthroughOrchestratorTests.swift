import Testing
import Foundation
@testable import HiMem

/// F8 / F10 / F13 · money tests for the guided-walkthrough state machine.
///
/// The pipeline beats (record / makeMemory / openMemory / organize) advance ONLY
/// on the real signal, never on a tap — guidance can't get ahead of the user.
/// F13 rebuild: the flow is five TASK steps (record · saved · make it a memory ·
/// let the app write a title and summary · done); the model-teaching beats
/// (`concept`, `ontology`) are retired and beat 1 drops its parts preamble. F10:
/// three channels — progress (`stepNumber`/`progressLabel`), confirmation
/// (`isConfirmation`), deviation (`deviationMessage`, observed wrong actions only).
///
/// `.serialized` — the orchestrator is a shared singleton with a
/// UserDefaults-backed `completed` flag; `skip()`/`finish()` also touch
/// `TutorialOrchestrator` (F9), so keep these ordered and isolated.
@MainActor
@Suite(.serialized)
struct WalkthroughOrchestratorTests {

    private typealias Beat = WalkthroughOrchestrator.Beat
    private var o: WalkthroughOrchestrator { .shared }

    /// Reset the singleton to a clean not-run, not-completed state.
    private func reset() {
        o.skip()                       // clears activeBeat, sets completed
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        o.activeBeat = nil
    }

    // MARK: - Lifecycle

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

    // MARK: - The five-step arc

    @Test func happyPath_advancesThroughTheFiveStepsInOrder() {
        reset()
        o.offerIfFirstRun();      #expect(o.activeBeat == .offer)
        o.beginFromOffer();       #expect(o.activeBeat == .record, "step 1 · record")
        o.recordingDidStart();    #expect(o.activeBeat == .onARoll, "mic hot → on-a-roll tip (un-numbered)")
        o.clipDidLand();          #expect(o.activeBeat == .clipLanded, "step 2 · saved")
        o.advance();              #expect(o.activeBeat == .makeMemory, "step 3 · make it a memory (concept beat retired)")
        o.memoryDidStart();       #expect(o.activeBeat == .openMemory, "still step 3 — the View bridge, not organize")
        o.memoryDidOpen(alreadyOrganized: false); #expect(o.activeBeat == .organize, "step 4 · let the app write (Free)")
        o.organizeDidComplete();  #expect(o.activeBeat == .done, "step 5 · done")
        o.advance();              #expect(o.activeBeat == nil && o.hasCompleted, "done → finish (ontology beat retired)")
        reset()
    }

    /// Beats 3/4 must anchor to Memory-Detail *arrival*, not memory creation —
    /// Start a Memory returns to the Clips list (no teleport), so organize points
    /// at a control that only exists once the memory is open.
    @Test func organizeArmsOnlyOnMemoryOpen_notCreation() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart(); o.clipDidLand()
        o.advance()                              // clipLanded → makeMemory
        #expect(o.activeBeat == .makeMemory)
        o.memoryDidStart(id: UUID())
        #expect(o.activeBeat == .openMemory, "creation bridges to open-your-memory, not organize")
        o.advance(); #expect(o.activeBeat == .openMemory, "openMemory ignores taps — waits for the real open signal")
        o.memoryDidOpen(alreadyOrganized: false)
        #expect(o.activeBeat == .organize, "organize arms only once Memory Detail is on screen")
        reset()
    }

    /// Plus auto-organizes at creation, so step 4 shows as a CONFIRMATION the
    /// user taps through — NOT skipped (skipping 3→5 would break the progress
    /// count). `organizeAlreadyDone` flips the beat from instruction to
    /// confirmation and lets a tap advance it.
    @Test func memoryOpen_whenAlreadyOrganized_showsStep4AsConfirmation() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart(); o.clipDidLand()
        o.advance(); o.memoryDidStart(id: UUID())
        #expect(o.activeBeat == .openMemory)
        o.memoryDidOpen(alreadyOrganized: true)
        #expect(o.activeBeat == .organize, "step 4 still shows on Plus (progress stays 1→5)")
        #expect(o.organizeAlreadyDone, "flagged as already done → confirmation, not instruction")
        o.gotIt(); #expect(o.activeBeat == .done, "Plus: organize is a confirmation the user taps through")
        reset()
    }

    // MARK: - On-a-roll

    @Test func onARollPath_nextTapRetiresBannerThenClipLands() {
        reset()
        o.start(); o.beginFromOffer()
        o.recordingDidStart();  #expect(o.activeBeat == .onARoll)
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "Next retires the tip but stays armed")
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "further Next taps are no-ops")
        o.clipDidLand();        #expect(o.activeBeat == .clipLanded, "rolling → clipLanded when the clip lands")
        reset()
    }

    @Test func onARollBeat_ignoresTaps_waitsForRealSignal() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        #expect(o.activeBeat == .onARoll)
        o.advance(); #expect(o.activeBeat == .onARoll, "onARoll ignores taps")
        reset()
    }

    // MARK: - Pipeline invariant (the load-bearing one)

    @Test func pipelineBeats_ignoreTaps_waitForRealSignal() {
        reset()
        o.start(); o.beginFromOffer()
        #expect(o.activeBeat == .record)
        o.advance(); #expect(o.activeBeat == .record, "record ignores taps — waits for clipDidLand")
        o.clipDidLand(); o.advance()      // clipLanded → makeMemory
        #expect(o.activeBeat == .makeMemory)
        o.advance(); #expect(o.activeBeat == .makeMemory, "makeMemory ignores taps — waits for memoryDidStart")
        o.memoryDidStart()
        #expect(o.activeBeat == .openMemory)
        o.advance(); #expect(o.activeBeat == .openMemory, "openMemory ignores taps — waits for memoryDidOpen")
        o.memoryDidOpen(alreadyOrganized: false)
        #expect(o.activeBeat == .organize)
        o.advance(); #expect(o.activeBeat == .organize, "organize (Free) ignores taps — waits for organizeDidComplete")
        reset()
    }

    @Test func outOfOrderSignals_areIgnored() {
        reset()
        o.start()
        o.organizeDidComplete()   // not on .organize
        #expect(o.activeBeat == .offer, "a signal for a distant beat does nothing")
        o.clipDidLand()           // not on .record
        #expect(o.activeBeat == .offer)
        reset()
    }

    // MARK: - "Got it." semantics

    @Test func gotIt_onSignalBeat_retiresBannerOnly() {
        reset()
        o.start(); o.beginFromOffer()          // → .record (a signal beat)
        #expect(o.activeBeat == .record)
        o.gotIt()
        #expect(o.currentBannerRetired, "the card is retired")
        #expect(o.activeBeat == .record, "no advance — still armed for the real signal")
        #expect(!o.hasCompleted && o.isRunning, "no completion, not abandoned")
        o.recordingDidStart()                  // the real signal
        #expect(o.activeBeat == .onARoll)
        #expect(!o.currentBannerRetired, "flag resets on the beat change")
        reset()
    }

    @Test func gotIt_onReadBeat_isTheContinue() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart(); o.clipDidLand()  // → .clipLanded
        #expect(o.activeBeat == .clipLanded)
        o.gotIt(); #expect(o.activeBeat == .makeMemory, "clipLanded (read beat) → makeMemory")
        #expect(!o.currentBannerRetired && o.isRunning)
        reset()
    }

    // MARK: - Deviation channel (F10) — observed wrong actions ONLY

    @Test func fabIllustrationTap_triggersDeviation_clearsOnNextBeat() {
        reset()
        o.start(); o.beginFromOffer()          // → .record
        #expect(o.deviationMessage == nil, "no deviation until a wrong action is observed")
        o.observedTappedFabIllustration()
        #expect(o.deviationMessage == Beat.fabIllustrationDeviation,
                "tapping the picture of the button responds instead of doing nothing")
        o.recordingDidStart()                  // the right action → beat change
        #expect(o.deviationMessage == nil, "deviation clears the moment she does the right thing")
        #expect(o.activeBeat == .onARoll)
        reset()
    }

    @Test func fabIllustrationTap_isNoOpOffRecordBeat() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart(); o.clipDidLand()  // .clipLanded
        o.observedTappedFabIllustration()
        #expect(o.deviationMessage == nil, "the illustration only exists on the record beat")
        reset()
    }

    @Test func discardedRecording_isAcknowledged_notSilent() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()   // .onARoll
        o.recordingDidCancel()
        #expect(o.activeBeat == .record, "returns to the record prompt")
        #expect(o.deviationMessage == Beat.discardedDeviation,
                "a discarded recording is named — silence here read as abandonment")
        reset()
    }

    @Test func deviationNeverFiresOnIdleOrTaps() {
        // The deviation channel has NO idle/timer path — it is only ever set by
        // an observed wrong action. A bare tap-advance attempt must not set it.
        reset()
        o.start(); o.beginFromOffer()   // .record
        o.advance()                     // a tap the record beat ignores
        #expect(o.deviationMessage == nil, "ignoring a tap is not a deviation")
        o.gotIt()                       // retire the banner
        #expect(o.deviationMessage == nil, "Got it is not a deviation")
        reset()
    }

    // MARK: - Progress channel (F10)

    @Test func progressMapsBeatsToFiveIntentionSteps() {
        #expect(Beat.totalSteps == 5)
        #expect(Beat.offer.stepNumber == nil, "the invite is pre-flow")
        #expect(Beat.record.stepNumber == 1)
        #expect(Beat.onARoll.stepNumber == 1, "the tip belongs to the record step")
        #expect(Beat.rolling.stepNumber == 1)
        #expect(Beat.clipLanded.stepNumber == 2)
        #expect(Beat.makeMemory.stepNumber == 3)
        #expect(Beat.openMemory.stepNumber == 3, "Start a Memory → View is one intention")
        #expect(Beat.organize.stepNumber == 4)
        #expect(Beat.done.stepNumber == 5)
    }

    @Test func progressLabel_isQuiet_andUnnumberedForTheTip() {
        #expect(Beat.record.progressLabel == "Step 1 of 5")
        #expect(Beat.clipLanded.progressLabel == "Step 2 of 5")
        #expect(Beat.done.progressLabel == "Step 5 of 5")
        #expect(Beat.onARoll.progressLabel == nil, "the on-a-roll tip carries no step number")
        #expect(Beat.offer.progressLabel == nil, "the invite carries no step number")
    }

    // MARK: - Confirmation channel (F10)

    @Test func confirmationMarksTheLandedSteps() {
        #expect(Beat.clipLanded.isConfirmation, "Saved. Here it is. — a step landed")
        #expect(Beat.done.isConfirmation, "That's a memory — the payoff landed")
        #expect(!Beat.record.isConfirmation, "an instruction is not a confirmation")
        #expect(!Beat.makeMemory.isConfirmation)
        #expect(!Beat.organize.isConfirmation, "Free organize is an instruction; Plus confirmation is ORed in via organizeAlreadyDone")
    }

    // MARK: - Copy (F7e / F7g / F13)

    @Test func de_ontology_beat1IsTaskOnly() {
        // F13: beat 1 drops the "a memory is made of one or more parts" preamble —
        // it says what to DO, not what things are.
        let record = Beat.record.body(alreadyOrganized: false).lowercased()
        #expect(!record.contains("part"), "no parts preamble on beat 1")
        #expect(record.contains("voice") && record.contains("record"), "names the task")
        #expect(record.contains("+"), "names the + control")
    }

    @Test func de_ontology_beat2IsConfirmationOnly() {
        // F13: beat 2 stripped to the confirmation — the clip/bench concept moves
        // to pulled homes (memoryClip ?).
        #expect(Beat.clipLanded.body(alreadyOrganized: false) == "Saved. Here it is.")
    }

    @Test func de_ontology_conceptAndOntologyBeatsAreGone() {
        // The nine surviving beats — no `concept`, no `ontology`.
        #expect(Beat.allCases.count == 9)
        let names = Set(Beat.allCases.map { String(describing: $0) })
        #expect(!names.contains("concept") && !names.contains("ontology"),
                "the model-teaching beats are retired (F13)")
    }

    @Test func organizeBeat_isTierAware_honestLabel() {
        let free = Beat.organize.body(alreadyOrganized: false)
        let done = Beat.organize.body(alreadyOrganized: true)
        #expect(free.contains("Tap Organize"), "Free guides the tap")
        #expect(done.contains("already wrote"), "Plus confirms — no button that isn't there")
        #expect(free != done)
        // Honest Label: the app writes those sentences using only the clip.
        #expect(free.contains("only what's in it") && done.contains("only what's in it"),
                "never claims to add anything the clip doesn't contain")
    }

    @Test func noBeatCopyUsesTheWordEvidence() {
        for beat in Beat.allCases {
            let f = beat.body(alreadyOrganized: false).lowercased()
            let t = beat.body(alreadyOrganized: true).lowercased()
            #expect(!f.contains("evidence") && !t.contains("evidence"),
                    "F7g: no user-facing 'evidence' in walkthrough copy — beat \(beat)")
        }
    }

    @Test func onARollBeat_namesNext_tierIndependent() {
        let copy = Beat.onARoll.body(alreadyOrganized: false)
        #expect(copy.contains("Next"), "on-a-roll copy names the Next control")
        #expect(copy == Beat.onARoll.body(alreadyOrganized: true), "tier-independent")
    }

    @Test func openMemoryBeat_namesView() {
        let copy = Beat.openMemory.body(alreadyOrganized: false)
        #expect(copy.contains("View"), "open-memory copy names the View control")
        #expect(copy == Beat.openMemory.body(alreadyOrganized: true), "tier-independent")
    }

    @Test func doneBeat_closingLineKeepsBothPromises() {
        let line = Beat.closingLine
        #expect(line.contains("beside a section"), "names the per-section ? help (F7c)")
        #expect(line.contains("Settings → Learn"), "names the re-run path")
    }

    @Test func offerCopy_promisesTheProcess_noOntology() {
        // F13/F7e: the invite promises the process she asked for, not the model.
        let offer = Beat.offer.body(alreadyOrganized: false).lowercased()
        #expect(!offer.contains("part"), "no ontology in the invite")
        #expect(offer.contains("memory") && offer.contains("step"), "promises step-by-step first memory")
    }
}
