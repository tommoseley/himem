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

    /// **`firstRun_offersOnce_thenNotAfterComplete` is RETIRED** (2026-08-23).
    /// It guarded "a first run offers the walkthrough once", which the intro
    /// tour retired by ruling: the tour is the invitation, and
    /// `offerIfFirstRun()` no longer exists. The half worth keeping — that
    /// skip completes and closes — is asserted here; the seam it used to cover
    /// is now `IntroTourHandoffTests`, which asserts the CALLER ordering that
    /// this test could not see.
    @Test func skip_completesAndCloses() {
        reset()
        o.start()
        #expect(o.activeBeat == .offer)

        o.skip()
        #expect(o.activeBeat == nil && o.hasCompleted, "skip completes + closes")
        reset()
    }

    @Test func showMeAround_relaunches_evenAfterComplete() {
        reset()
        o.skip()                       // completed
        o.start()                      // "? → Show me around"
        #expect(o.activeBeat == .offer, "relaunch ignores the completed flag")
        reset()
    }

    // MARK: - The four-step arc

    @Test func happyPath_advancesThroughTheFourStepsInOrder() {
        reset()
        o.start();                #expect(o.activeBeat == .offer)   // "Show me around" — offerIfFirstRun retired
        o.beginFromOffer();       #expect(o.activeBeat == .record, "step 1 · record")
        o.recordingDidStart();    #expect(o.activeBeat == .onARoll, "mic hot → on-a-roll tip (un-numbered)")
        o.memoryDidStart();       #expect(o.activeBeat == .openMemory, "step 2 · the capture IS the memory (I3: no saved/promote beats)")
        o.memoryDidOpen(alreadyOrganized: false); #expect(o.activeBeat == .detailTour, "F16 · orient her to the screen on arrival, before asking for the tap")
        o.advance();              #expect(o.activeBeat == .organize, "step 3 · let the app write (Free)")
        o.organizeDidComplete();  #expect(o.activeBeat == .done, "step 4 · done")
        o.advance();              #expect(o.activeBeat == nil && o.hasCompleted, "done → finish (ontology beat retired)")
        reset()
    }

    /// Organize must anchor to Memory-Detail *arrival*, not memory creation —
    /// capture leaves her on the Memories list (no teleport), so organize points
    /// at a control that only exists once the memory is open.
    @Test func organizeArmsOnlyOnMemoryOpen_notCreation() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        o.memoryDidStart(id: UUID())
        #expect(o.activeBeat == .openMemory, "creation bridges to open-your-memory, not organize")
        o.advance(); #expect(o.activeBeat == .openMemory, "openMemory ignores taps — waits for the real open signal")
        o.memoryDidOpen(alreadyOrganized: false)
        #expect(o.activeBeat == .detailTour, "arrival opens the orientation beat")
        o.advance()
        #expect(o.activeBeat == .organize, "organize arms only once Memory Detail is on screen")
        reset()
    }

    /// Plus auto-organizes at creation, so step 3 shows as a CONFIRMATION the
    /// user taps through — NOT skipped (skipping it would break the progress
    /// count). `organizeAlreadyDone` flips the beat from instruction to
    /// confirmation and lets a tap advance it.
    @Test func memoryOpen_whenAlreadyOrganized_showsOrganizeAsConfirmation() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        o.memoryDidStart(id: UUID())
        #expect(o.activeBeat == .openMemory)
        o.memoryDidOpen(alreadyOrganized: true)
        #expect(o.activeBeat == .detailTour, "Plus gets the same orientation beat")
        o.advance()
        #expect(o.activeBeat == .organize, "step 3 still shows on Plus (progress stays 1→4)")
        #expect(o.organizeAlreadyDone, "flagged as already done → confirmation, not instruction")
        o.gotIt(); #expect(o.activeBeat == .done, "Plus: organize is a confirmation the user taps through")
        reset()
    }

    // MARK: - F16 · the ending that stopped abandoning her

    // Dogfood round 3: she completed the flow, the memory landed in the list
    // unhighlighted (she had to guess which row she'd just made), and Memory
    // Detail gave her no orientation. Root cause was NOT a regressed bridge —
    // `memoryDidOpen` survived intact. It is that the overlay has no anchoring
    // primitive at all, so every beat is a floating claim about something on
    // screen. Beats work while the referent is unambiguous (the FAB, Stop &
    // save) and fail the moment it is one of many. Fix: the target identifies
    // itself (ring on her row), and arrival orients her before asking for a tap.

    // `memoriesList_reAnchorsStepThreeToHerRow`, `memoryInList_reachesDetailAndOrients`
    // and `tappingView_neverShowsTheListBeat` are RETIRED BY SUPERSESSION
    // (I3, Tom 2026-09-16), not deleted for convenience.
    //
    // All three guarded step 3 having TWO anchors: the "Memory created · View"
    // toast and — if she reached the list without tapping it — her ringed row.
    // Capture now lands in a memory directly, so there is no toast, no second
    // path, and nothing to re-anchor between. They guarded a MECHANISM THE
    // RULING REMOVES, not a promise it preserves.
    //
    // The promise underneath them — *she must never have to guess which row she
    // just made* — did not retire. It is carried by the ring, which renders off
    // `walkthroughMemoryId` and is asserted below.

    /// The ring's id must be captured at creation, because the ring is now the
    /// ONLY thing that marks her row — the toast that used to carry her there
    /// is gone with the promotion arc.
    @Test func creationCapturesTheRingId() {
        reset()
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        let id = UUID()
        o.memoryDidStart(id: id)
        #expect(o.activeBeat == .openMemory)
        #expect(o.walkthroughMemoryId == id, "the ring needs the id to mark HER row")
        #expect(o.activeBeat?.stepNumber == 2)
        reset()
    }

    /// The orientation beat is un-numbered: there is nothing to do on it, so it
    /// must not inflate the 4-step progress she is counting against.
    @Test func detailTour_isUnnumbered_andTapAdvances() {
        reset()
        o.start(); o.beginFromOffer()
        o.recordingDidStart()
        o.memoryDidStart(id: UUID()); o.memoryDidOpen(alreadyOrganized: false)
        #expect(o.activeBeat?.stepNumber == nil, "orientation carries no step number")
        #expect(o.activeBeat?.progressLabel == nil, "and no 'Step N of 4' label")
        o.advance(); #expect(o.activeBeat == .organize, "the card IS the gate — Got it. continues")
        reset()
    }

    /// Progress counts to FOUR (I3): the promotion arc's two steps collapsed
    /// into one, and the un-numbered orientation beat still does not inflate it.
    @Test func progress_countsToFour() {
        #expect(WalkthroughOrchestrator.Beat.totalSteps == 4)
        #expect(WalkthroughOrchestrator.Beat.openMemory.stepNumber == 2)
        #expect(WalkthroughOrchestrator.Beat.detailTour.stepNumber == nil)
        #expect(WalkthroughOrchestrator.Beat.organize.stepNumber == 3)
        #expect(WalkthroughOrchestrator.Beat.done.stepNumber == 4)
    }

    // MARK: - On-a-roll

    @Test func onARollPath_nextTapRetiresBannerThenMemoryLands() {
        reset()
        o.start(); o.beginFromOffer()
        o.recordingDidStart();  #expect(o.activeBeat == .onARoll)
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "Next retires the tip but stays armed")
        o.nextClipStarted();    #expect(o.activeBeat == .rolling, "further Next taps are no-ops")
        o.memoryDidStart();     #expect(o.activeBeat == .openMemory, "rolling → step 2 when the memory lands")
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
        o.advance(); #expect(o.activeBeat == .record, "record ignores taps — waits for memoryDidStart")
        o.memoryDidStart()
        #expect(o.activeBeat == .openMemory)
        o.advance(); #expect(o.activeBeat == .openMemory, "openMemory ignores taps — waits for memoryDidOpen")
        o.memoryDidOpen(alreadyOrganized: false)
        #expect(o.activeBeat == .detailTour, "arrival orients before instructing (F16)")
        o.advance()
        #expect(o.activeBeat == .organize)
        o.advance(); #expect(o.activeBeat == .organize, "organize (Free) ignores taps — waits for organizeDidComplete")
        reset()
    }

    @Test func outOfOrderSignals_areIgnored() {
        reset()
        o.start()
        o.organizeDidComplete()   // not on .organize
        #expect(o.activeBeat == .offer, "a signal for a distant beat does nothing")
        o.memoryDidOpen(alreadyOrganized: false)   // not on .openMemory
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
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        o.memoryDidStart(id: UUID()); o.memoryDidOpen(alreadyOrganized: false)  // → .detailTour
        #expect(o.activeBeat == .detailTour)
        o.gotIt(); #expect(o.activeBeat == .organize, "detailTour (read beat) → organize")
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
        o.start(); o.beginFromOffer(); o.recordingDidStart()
        o.memoryDidStart(id: UUID())           // → .openMemory
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

    @Test func progressMapsBeatsToFourIntentionSteps() {
        #expect(Beat.totalSteps == 4)
        #expect(Beat.offer.stepNumber == nil, "the invite is pre-flow")
        #expect(Beat.record.stepNumber == 1)
        #expect(Beat.onARoll.stepNumber == 1, "the tip belongs to the record step")
        #expect(Beat.rolling.stepNumber == 1)
        #expect(Beat.openMemory.stepNumber == 2)
        #expect(Beat.detailTour.stepNumber == nil, "orientation is not a step")
        #expect(Beat.organize.stepNumber == 3)
        #expect(Beat.done.stepNumber == 4)
    }

    @Test func progressLabel_isQuiet_andUnnumberedForTheTip() {
        #expect(Beat.record.progressLabel == "Step 1 of 4")
        #expect(Beat.openMemory.progressLabel == "Step 2 of 4")
        #expect(Beat.done.progressLabel == "Step 4 of 4")
        #expect(Beat.onARoll.progressLabel == nil, "the on-a-roll tip carries no step number")
        #expect(Beat.offer.progressLabel == nil, "the invite carries no step number")
    }

    // MARK: - Confirmation channel (F10)

    @Test func confirmationMarksTheLandedSteps() {
        // I3 · `clipLanded` ("Saved. Here it is.") was the other confirmation
        // and retired with the promotion arc. Done is the only one left.
        #expect(Beat.done.isConfirmation, "That's a memory — the payoff landed")
        #expect(!Beat.record.isConfirmation, "an instruction is not a confirmation")
        #expect(!Beat.openMemory.isConfirmation)
        #expect(!Beat.organize.isConfirmation, "Free organize is an instruction; Plus confirmation is ORed in via organizeAlreadyDone")
    }

    // MARK: - Copy (F7e / F7g / F13)

    @Test func de_ontology_beat1IsTaskOnly() {
        // F13: beat 1 drops the "a memory is made of one or more parts" preamble —
        // it says what to DO, not what things are. THAT is what this guards.
        //
        // **The modality moved, the rule did not (2026-09-18).** This asserted
        // `contains("voice") && contains("record")` — using the specific tool as
        // a proxy for "names a task". Beat 1 now teaches WRITING, because voice
        // is a recording mechanism rather than the product's centre of gravity.
        // Pinning the tool made an emphasis decision look like a copy
        // regression, so the assertion now pins the PROPERTY: a concrete verb,
        // the control that starts it, and no ontology.
        let record = Beat.record.body(alreadyOrganized: false).lowercased()
        #expect(!record.contains("part"), "no parts preamble on beat 1")
        #expect(!record.contains("clip"), "'clip' has left the user's vernacular")
        #expect(record.contains("+"), "names the + control")

        // Names one concrete thing to do. Enumerated rather than sampled so a
        // future reword cannot quietly leave the beat with no verb at all —
        // which is the failure F13 exists to prevent.
        let verbs = ["write", "record", "type", "photograph"]
        #expect(verbs.contains { record.contains($0) },
                "beat 1 must name an action she performs; got: \(record)")
    }

    @Test func de_ontology_conceptAndOntologyBeatsAreGone() {
        // **THE GUARD'S SUBJECT IS UNCHANGED; ONLY THE ARITHMETIC MOVED.**
        // `concept` and `ontology` stay retired and F13 still holds — this
        // still asserts exactly that. The count went 11 → 8 because I3 removed
        // three beats for an unrelated reason: `clipLanded` and `makeMemory`
        // (the promotion arc the vocabulary retirement deletes) and
        // `memoryInList` (folded into `openMemory` with the toast it existed to
        // cover). None of the three was a model-teaching beat.
        //
        // The reason is attached deliberately. A count guard whose number
        // changes reads as the guard eroding unless the change carries its
        // justification — and this one has now moved twice (9 → 11 at F16,
        // 11 → 8 at I3) without F13 ever being reversed.
        #expect(Beat.allCases.count == 8)
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
        // Honest Label: the app writes those sentences using only her own
        // recordings. Wording moved to the plural at F16 (on-a-roll can leave
        // several), so match the invariant rather than one phrasing.
        #expect(free.contains("only what's in them"), "Free names the limit")
        #expect(done.contains("only what's in your recordings"), "Plus names the limit")
        #expect(free.contains("Nothing happens until you ask"),
                "F16 · she decides when it runs")
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

    /// **Was `openMemoryBeat_namesView`, and the rename is the point.** It
    /// pinned the literal `"View"` because step 2's referent used to be the
    /// "Memory created · View" toast. I3 removed that toast with the promotion
    /// arc, so the MEANING moved, not the phrasing — which per CLAUDE.md
    /// § *Assert the Meaning, Not the Phrasing* makes it a design change with a
    /// ruling behind it (Tom, 2026-09-16), not a test to update reflexively.
    ///
    /// What replaces it is the surviving promise: the beat identifies her row
    /// **by her own action**, and names no control at all — the ring does the
    /// pointing. The negative assertion is the load-bearing half: naming a
    /// control that no longer exists is the phantom-copy shape.
    @Test func openMemoryBeat_pointsAtHerRow_namingNoDeadControl() {
        let copy = Beat.openMemory.body(alreadyOrganized: false)
        #expect(copy.lowercased().contains("just made"),
                "it identifies the row by what she did, not by our noun for it")
        #expect(!copy.contains("View"),
                "the View toast is gone with the promotion arc; naming it would be phantom copy")
        #expect(!copy.lowercased().contains("clip"),
                "'clip' has left the user's vernacular")
        #expect(copy == Beat.openMemory.body(alreadyOrganized: true), "tier-independent")
    }

    /// **This is a MEANING test, not a phrasing test** (CLAUDE.md § "Assert
    /// the Meaning, Not the Phrasing"). A failure here means one of the two
    /// promises was DROPPED, not that the sentence was reworded.
    ///
    /// It failed once, on F27 (2026-08-01), and the diagnosis was exactly the
    /// distinction the rule exists for: the second assertion pinned the
    /// literal `"Settings → Learn"` while its own message said it was
    /// guarding *"names the re-run path."* The path moved to the nearer,
    /// control-naming route (`Learn → Show me around`) and the promise was
    /// intact — so the assertion was rewritten to pin the promise. It now
    /// binds to the SHIPPED row title rather than any literal, so copy and
    /// control cannot drift apart.
    @Test func doneBeat_closingLineKeepsBothPromises() {
        let line = Beat.closingLine
        #expect(line.contains("beside a section"), "names the per-section ? help (F7c)")
        #expect(line.contains(TutorialCatalog.tour.title),
                "names the re-run path by the control that ships (\(TutorialCatalog.tour.title))")
    }

    @Test func offerCopy_promisesTheProcess_noOntology() {
        // F13/F7e: the invite promises the process she asked for, not the model.
        let offer = Beat.offer.body(alreadyOrganized: false).lowercased()
        #expect(!offer.contains("part"), "no ontology in the invite")
        #expect(offer.contains("memory") && offer.contains("step"), "promises step-by-step first memory")
    }
}
