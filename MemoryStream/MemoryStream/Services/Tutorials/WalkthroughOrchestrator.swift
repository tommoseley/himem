import Foundation
import SwiftUI

/// F8 · the guided first walkthrough — a **do-it-with-me** sequence. The user
/// records a real first capture with guidance at each beat, on the ad-hoc path
/// (Clips **+** → bench → Start a Memory).
///
/// **F10 + F13 rebuild (2026-07-28).** Round-2 dogfood regressed to "you
/// abandoned me after step one." Two changes, one rebuild:
///
/// 1. **Teach the task, not the ontology (F13).** The old flow taught our model
///    — a "concept" card ("a memory is made of one or more parts"), an
///    "ontology" closer ("that's the shape of HiMem"), and a parts-preamble on
///    beat 1. All cut. The ontology stays invisible; its copy moves to pulled
///    homes (the section-`?` `memoryClip` panel; the `projectsConcept`
///    coachmark). The flow is now five *task* steps:
///      1 Record · 2 Saved · 3 Make it a memory · 4 Let the app write a title
///      and summary · 5 Done. ("Start a Memory → View" is one intention, so it
///      is one numbered step spanning two taps — Tom 2026-07-28.)
/// 2. **Three channels she named (F10).** The old flow was silent between beats,
///    so any pause read as abandonment. Added: **progress** (`stepNumber` /
///    `progressLabel` — a quiet "Step N of 5", never a scold), **confirmation**
///    (the Saved / Done beats say a step landed — she twice missed the organize
///    moment), and **deviation feedback** (`deviationMessage`, set ONLY on an
///    observed wrong action — the FAB-illustration tap, a discarded recording —
///    never on idle time, no timers).
///
/// **Pipeline invariant (unchanged, money-tested).** `record` / `onARoll` /
/// `makeMemory` / `openMemory` / `organize` advance ONLY on a real pipeline
/// signal, never on a tap — guidance never gets ahead of the user. `offer` /
/// `clipLanded` / `done` (and `organize` once it's already done on Plus) advance
/// on a tap. `rolling` is a silent hold.
///
/// The state machine is the spine (this file). The anchored overlay UI and the
/// signal wiring that calls `recordingDidStart()` / `nextClipStarted()` /
/// `recordingDidCancel()` / `clipDidLand()` / `memoryDidStart()` /
/// `memoryDidOpen()` / `organizeDidComplete()` live in `WalkthroughOverlay` +
/// `VoiceCaptureScreen` + `EntryExpandedView`. Beat 1b (`onARoll`) renders
/// in-composer (the recording screen is presented over the root overlay) and is
/// an **un-numbered tip inside the Record step** (Tom 2026-07-28), not a step of
/// its own.
///
/// Spec: `Handoff · punch list · 2026-07-25.md` §§F8, F10, F13. Copy is
/// design-authority, **drafted cold for Judi per F7e — not declared clear**; no
/// "evidence" (F7g).
@MainActor
final class WalkthroughOrchestrator: ObservableObject {
    static let shared = WalkthroughOrchestrator()

    /// The beats, in order. Numbered task steps map many→one onto the five the
    /// progress channel shows (see `stepNumber`). `concept` and `ontology` (the
    /// old model-teaching beats) are retired.
    enum Beat: Int, CaseIterable, Identifiable {
        case offer       // pre-flow invite (no step number)
        case record      // step 1 — "record something you don't want to forget"
        case onARoll     // in-composer, UN-numbered tip inside step 1 (1b)
        case rolling     // silent hold (still step 1) — retired after a Next tap
        case clipLanded  // step 2 — "Saved. Here it is." (confirmation)
        case makeMemory  // step 3 — "Open your clip and tap Start a Memory"
        case openMemory  // step 3 — "Tap View" (same intention, second tap)
        /// step 3, ALTERNATIVE anchor to `openMemory` — not a later step. F16:
        /// she missed the View toast and landed on the Memories list with her
        /// new memory unhighlighted, guessing which row she'd just made. Fires
        /// only if the list appears while step 3 is still open; if she taps
        /// View it never fires, because she doesn't need it. Sequencing it
        /// after `openMemory` would mean sending her back to the list, which
        /// the no-navigation rule forbids.
        case memoryInList
        /// UN-numbered orientation beat on Memory Detail arrival (F16). Not a
        /// step — there is nothing to do — so it carries no step number, same
        /// treatment as `onARoll`.
        case detailTour
        case organize    // step 4 — "let the app write a title and summary"
        case done        // step 5 — "that's a memory · find it under Memories"

        var id: Int { rawValue }
    }

    /// The active beat; `nil` when the walkthrough isn't running. Any beat change
    /// resets the per-beat transient channels (`currentBannerRetired`,
    /// `deviationMessage`) so the new beat's card shows fresh.
    @Published var activeBeat: Beat? {
        didSet {
            currentBannerRetired = false
            deviationMessage = nil
        }
    }

    /// True when the user tapped "Got it." on the current beat — retires THIS
    /// beat's banner only. On a signal beat: no advance, no completion; the
    /// walkthrough stays armed and the next beat fires on its real signal (Tom
    /// 2026-07-27). Reset on every beat change (didSet above).
    @Published var currentBannerRetired = false

    /// **Deviation channel (F10).** Non-nil when the user just did an *observed
    /// wrong action* (tapped the FAB illustration, discarded a recording). A
    /// gentle redirect — never blame, never a timer, never idle-triggered.
    /// Cleared on the next beat change (didSet) so it never lingers past the
    /// moment it corrects.
    @Published var deviationMessage: String? = nil

    /// True once the walkthrough's memory is already organized when it opens —
    /// on Plus the organize pass ran automatically at creation, so step 4 is a
    /// *confirmation* the user taps through, not an instruction she performs
    /// (keeps the 5-step progress coherent on both tiers). Set by
    /// `memoryDidOpen(alreadyOrganized:)`.
    private(set) var organizeAlreadyDone = false

    /// The memory the user created during the walkthrough (set by
    /// `memoryDidStart`). The host watches THIS entry for organize completion —
    /// `lastOrganizedAt` / `inferenceSummary` isn't broadcast, so the host
    /// checks it on Core Data change and calls `organizeDidComplete()`.
    private(set) var walkthroughMemoryId: UUID?

    private let completedKey = "himem.walkthrough.completed"

    private init() {}

    /// Set when the walkthrough begins: the flow runs on Clips, because that
    /// is where the pipeline it teaches actually lands (F26). Announced in the
    /// offer copy so she is never teleported without explanation.
    @Published private(set) var pendingClipsTabSwitch = false

    var isRunning: Bool { activeBeat != nil }

    /// Persisted so first-run offers it exactly once (skip counts as done — a
    /// declined offer isn't re-nagged; it's always retrievable from the hub).
    var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    // MARK: - Lifecycle

    /// **`offerIfFirstRun()` IS RETIRED** (2026-08-23, found on device).
    ///
    /// It could never legitimately fire once the intro tour existed: if the
    /// tour is unseen it is about to invite her, and if it has been seen the
    /// offer is suppressed. Worse, its suppression guard read
    /// `!IntroTourStore.hasSeen` — which is FALSE only *after* the tour, so on
    /// a fresh install the tab shell mounted behind the tour, `.onAppear`
    /// fired while `hasSeen` was still false, and `.offer` armed underneath a
    /// tour that was still on screen. Page 7 then no-opped and dismissing the
    /// tour revealed *"Walk through it together?"* — the question she had just
    /// answered by tapping the button.
    ///
    /// A wider guard would have been the wrong fix: the call had no correct
    /// moment left. `.offer` itself stays — "Show me around" in the Learn hub
    /// is its remaining honest use, via `start()`.

    /// Start the walkthrough at **beat 1**, skipping `.offer` entirely.
    ///
    /// The cold entry point for intro-tour page 7's primary action. `.offer`
    /// exists to ask whether she wants guidance; page 7 already asked and she
    /// tapped *"Walk me through it"*, so re-asking would be the double-offer
    /// this was ruled to remove. `beginFromOffer()` cannot serve here — it
    /// guards on `activeBeat == .offer` and would no-op from a cold machine.
    ///
    /// Everything else matches accepting the offer, including the announced
    /// switch to Clips: the script is written for the ad-hoc pipeline (record
    /// → the clip lands on the bench → Start a Memory), and on Memories the
    /// FAB creates a `JournalEntry` directly so `clipDidLand()` would never
    /// fire and the machine would sit on `record` forever (F26).
    /// **Authoritative, not guarded on `nil`** (2026-08-23). It previously
    /// bailed when a beat was already active, which is exactly the state the
    /// retired first-run offer left behind — so the one caller that matters
    /// silently did nothing. Page 7 is an explicit choice; it overrides
    /// whatever the machine was showing.
    func startAtFirstBeat() {
        pendingClipsTabSwitch = true
        currentBannerRetired = false
        activeBeat = .record
    }

    /// Explicit relaunch from "? → Show me around". Always starts fresh at the
    /// offer beat, regardless of `hasCompleted`.
    func start() { activeBeat = .offer }

    /// The user accepted the offer → begin the guided capture **on Clips**.
    ///
    /// F26: the script is written for ONE pipeline — record → the clip lands
    /// on the bench → Start a Memory → View → organize → done — and every
    /// advance signal is wired to it. `clipDidLand()` has a single caller,
    /// inside `.onChange(of: captureLanding.pendingReturnToClips)`, and that
    /// flag is set only by the `.dropOnBench` branch. But the FAB is
    /// context-aware (July 10 lock): on Memories, + creates a `JournalEntry`
    /// directly, so the flag never flips, `clipDidLand()` never fires, and the
    /// machine sits on `record` forever. **Cold launch lands on Memories**, so
    /// the default first-run user started on the one tab where step 2 could
    /// never arrive.
    ///
    /// Ruled 2026-08-01: switch to Clips rather than branch the script — the
    /// walkthrough teaches capture, and capture lands on Clips. The move is
    /// **announced** in the offer copy, never silent.
    func beginFromOffer() {
        guard activeBeat == .offer else { return }
        pendingClipsTabSwitch = true
        activeBeat = .record
    }

    /// Consumed by `HiMemTabView` to put the flow on Clips. One-shot.
    func consumeClipsTabSwitch() -> Bool {
        defer { pendingClipsTabSwitch = false }
        return pendingClipsTabSwitch
    }

    /// Skip / dismiss at any beat. Marks complete so first-run won't re-offer;
    /// the walkthrough stays retrievable from the hub.
    func skip() { finish() }

    /// The teaching card's "Got it." — retires THIS beat's banner, nothing more,
    /// except on the tap-gated read beats where the card IS the gate (its
    /// continue). On the signal beats it just hides the card; the walkthrough
    /// stays armed and the next beat fires on its real signal (pipeline
    /// invariant untouched — Tom 2026-07-27).
    func gotIt() {
        switch activeBeat {
        case .clipLanded, .detailTour, .done:
            advance()
        case .organize:
            // Free: organize is a signal beat (waits for the real Organize tap →
            // `organizeDidComplete`), so Got it only hides the card. Plus: it's
            // already done, so the card is a confirmation the user reads and
            // continues.
            if organizeAlreadyDone { advance() } else { currentBannerRetired = true }
        case .record, .makeMemory, .openMemory, .memoryInList:
            currentBannerRetired = true
        case .offer, .onARoll, .rolling, .none:
            break
        }
    }

    #if DEBUG
    /// Test-only: place the machine at a beat (with an optional ring target)
    /// so termination can be exercised from EVERY state — F26's defect was
    /// that some states had no way out. Mirrors
    /// `ProjectsNavigationContext.debugReset`; not exposed in release.
    func debugForceBeat(_ beat: Beat, memoryId: UUID? = nil) {
        activeBeat = beat
        walkthroughMemoryId = memoryId
    }
    #endif

    private func finish() {
        activeBeat = nil
        walkthroughMemoryId = nil
        organizeAlreadyDone = false
        // Every piece of walkthrough state dies here, including an
        // unconsumed tab request — a stale flag surviving termination is the
        // same family as the stuck ring this item exists to fix, and would
        // yank the user to Clips long after the flow ended. (Caught by
        // `beginningTheFlow_requestsTheClipsTab` failing on a dirty
        // singleton, which is the leak reproducing itself.)
        pendingClipsTabSwitch = false
        UserDefaults.standard.set(true, forKey: completedKey)
        // F8 owns first-run teaching. On completion OR abandonment, retire the
        // legacy one-pagers it replaced (.capture / .organizing) so they never
        // re-teach a step just performed — they remain pulled in Settings →
        // Learn (Tom 2026-07-28). Suppression *during* the run lives in
        // `TutorialOrchestrator.tryFire`.
        TutorialOrchestrator.shared.retireOnePagersReplacedByWalkthrough()
    }

    /// Tap-advance for the read-only beats. The pipeline beats wait for their
    /// real signal below so guidance never gets ahead of the user.
    func advance() {
        switch activeBeat {
        case .offer:      activeBeat = .record   // also reachable via beginFromOffer
        case .clipLanded:  activeBeat = .makeMemory
        case .detailTour:  activeBeat = .organize
        case .organize:    if organizeAlreadyDone { activeBeat = .done }
        case .done:        finish()
        case .record, .onARoll, .rolling, .makeMemory, .openMemory,
             .memoryInList, .none: break
        }
    }

    // MARK: - Deviation channel (observed wrong actions only — F10)

    /// The user tapped the FAB **illustration** (a picture of the button) on the
    /// record beat, not the real + — the exact wrong action Judi hit (F10
    /// channel 2 / F11). Respond instead of staying silent. No-op off the record
    /// beat; cleared on the next beat change.
    func observedTappedFabIllustration() {
        guard activeBeat == .record else { return }
        deviationMessage = Beat.fabIllustrationDeviation
    }

    // MARK: - Real-pipeline advance signals (called by the F8 wiring)

    /// Recording actually began (mic hot). Moves off the record prompt into the
    /// on-a-roll tip, shown in-composer.
    func recordingDidStart() { if activeBeat == .record { activeBeat = .onARoll } }

    /// The user tapped **Next**. The on-a-roll tip has landed, so retire its
    /// banner — but stay armed: `rolling` is silent and still awaits the clip.
    func nextClipStarted() { if activeBeat == .onARoll { activeBeat = .rolling } }

    /// The user discarded the recording (✕ / cancel) without producing a clip.
    /// Return to the record prompt and — since silence here is exactly what read
    /// as abandonment — say what happened (deviation channel), set AFTER the beat
    /// change so the didSet reset doesn't wipe it.
    func recordingDidCancel() {
        if activeBeat == .onARoll || activeBeat == .rolling {
            activeBeat = .record
            deviationMessage = Beat.discardedDeviation
        }
    }

    /// The clip finished recording and materialized on the bench. Reachable from
    /// `record` (stopped before the tip rendered — defensive), `onARoll` (stopped
    /// without Next), or `rolling` (Next then stop).
    func clipDidLand() {
        switch activeBeat {
        case .record, .onARoll, .rolling: activeBeat = .clipLanded
        default: break
        }
    }

    /// The user created a memory from the clip (Start a Memory). Advances to
    /// `openMemory` (still step 3) — Start a Memory returns to the calm Clips
    /// list with a "Memory created · View" toast (no-teleport spec); organize/
    /// done point at controls that only exist on Memory Detail, so they wait
    /// until the user opens it (`memoryDidOpen`).
    func memoryDidStart(id: UUID? = nil) {
        if activeBeat == .makeMemory {
            walkthroughMemoryId = id
            activeBeat = .openMemory
        }
    }

    /// The walkthrough's memory opened on Memory Detail. Arms step 4 (`organize`)
    /// on both tiers so the progress stays coherent: on Plus it's a confirmation
    /// (`organizeAlreadyDone`), on Free an instruction that waits for the real
    /// Organize tap.
    func memoryDidOpen(alreadyOrganized: Bool) {
        // Either step-3 anchor may be live: the View toast (`openMemory`) or her
        // ringed row in the list (`memoryInList`). Both mean "she reached the
        // memory", so both hand off here.
        guard activeBeat == .openMemory || activeBeat == .memoryInList else { return }
        organizeAlreadyDone = alreadyOrganized
        // F16: orient her to the screen BEFORE asking for the Organize tap. The
        // tour is un-numbered and tap-advances into step 4.
        activeBeat = .detailTour
    }

    /// The Memories list is on screen and the walkthrough's memory is in it —
    /// she reached the list rather than the View toast (F16). Swaps step 3's
    /// anchor from the toast to her ringed row; the ring is rendered by the row
    /// itself (`JournalView`), so this only supplies the confirming copy.
    /// No-op once she's past step 3.
    func memoriesListDidShowWalkthroughMemory() {
        guard activeBeat == .openMemory else { return }
        activeBeat = .memoryInList
    }

    /// The memory's organize pass completed (its title + summary now exist). On
    /// Free this fires after the user taps Organize and advances to `done`.
    func organizeDidComplete() { if activeBeat == .organize { activeBeat = .done } }
}

// MARK: - Progress channel (F10)

extension WalkthroughOrchestrator.Beat {
    /// Total numbered task steps the progress indicator counts.
    static let totalSteps = 5

    /// The numbered task step this beat belongs to (1...5), or nil for the
    /// pre-flow offer. Many beats share one step: `record`/`onARoll`/`rolling`
    /// are all "recording" (step 1); `makeMemory`/`openMemory` are one intention,
    /// "make it a memory" (step 3). The count is intentions, not taps
    /// (Tom 2026-07-28).
    var stepNumber: Int? {
        switch self {
        case .offer:                       return nil
        case .record, .onARoll, .rolling:  return 1
        case .clipLanded:                  return 2
        case .makeMemory, .openMemory,
             .memoryInList:                return 3
        case .detailTour:                  return nil   // orientation, not a step
        case .organize:                    return 4
        case .done:                        return 5
        }
    }

    /// "Step N of 5" — a quiet indicator, never a scold. Nil for the offer and
    /// for the un-numbered in-composer on-a-roll tip (the overlay renders it only
    /// on the numbered root-overlay beats; the composer never shows a number).
    var progressLabel: String? {
        guard self != .onARoll, let n = stepNumber else { return nil }
        return "Step \(n) of \(WalkthroughOrchestrator.Beat.totalSteps)"
    }

    /// Whether this beat *confirms a step just landed* (confirmation channel) —
    /// the Saved beat and the Done beat. The organize beat also reads as a
    /// confirmation once it's already done (Plus); the overlay ORs that in via
    /// `organizeAlreadyDone`.
    var isConfirmation: Bool {
        self == .clipLanded || self == .done
    }

    /// Which edge the banner pins to.
    ///
    /// F26 · step 3's card consumed the whole top of the screen and hid the
    /// very thing it referenced. Its referents all live low — the "Memory
    /// created · View" toast, a clip row, her ringed memory row — so the
    /// step-3 beats pin to the BOTTOM (ruled 2026-08-01). Not a dismissible
    /// variant: one less state, and moving the card near its referent closes
    /// part of the missing-anchoring problem without inventing an anchoring
    /// primitive (which F16 ruled out).
    var pinsToBottom: Bool { stepNumber == 3 }
}

// MARK: - Copy (design-authority · drafted cold for Judi, F7e · no "evidence", F7g)

extension WalkthroughOrchestrator.Beat {
    /// The card headline for each beat (nil where the body carries it).
    var title: String? {
        switch self {
        case .offer: return "Walk through it together?"
        case .done:  return "That's a memory"
        default:     return nil
        }
    }

    /// The coaching sentence. `alreadyOrganized` only changes the `organize`
    /// beat: on Free the user taps Organize; on Plus it already ran, so we
    /// confirm instead of pointing at a button that isn't there.
    func body(alreadyOrganized: Bool) -> String {
        switch self {
        case .offer:
            // Task framing, no ontology (F13): promise the process she asked for
            // ("walk me through the whole process step by step"), name the ~minute
            // and the per-step guidance. No "part".
            // F26 · name the tab move rather than performing it silently
            // (ruled 2026-08-01). "Clips" is a handle she can point at (J1),
            // not an ontology lesson (F13) — it says where we're going and why.
            return "I'll guide you through making your first memory — you record it, then the app writes a title and summary. We'll start on Clips, where your recordings land. About a minute, and I'll point at each step."
        case .record:
            // Step 1. The parts-preamble is CUT (F13) — say what to DO, not what
            // things are. The FAB illustration (see the overlay) makes "tap +,
            // then Voice" recognizable.
            return "Tap +, then Voice, and record something you don't want to forget."
        case .onARoll:
            // 1b — un-numbered tip inside step 1, shown while recording, anchored
            // to Next. Enrichment, not a step (Tom 2026-07-28).
            return "Still talking? Tap Next to start a new clip without stopping. They'll stay together."
        case .rolling:
            return ""   // silent hold — never rendered
        case .clipLanded:
            // Step 2 · confirmation. Stripped to exactly this (F13): the bench /
            // "what a part is" teaching moves to pulled homes; the beat's job is
            // to say the recording landed (F10 confirmation channel).
            return "Saved. Here it is."
        case .makeMemory:
            // Step 3 · the ontology tail ("your clip becomes the first part…") is
            // cut; name the action only.
            return "Open your clip and tap Start a Memory."
        case .openMemory:
            // Step 3, second tap. Names the toast's control (no-teleport spec).
            return "Your memory is saved. Tap View to open it."
        case .memoryInList:
            // Step 3 alternative. The RING on her row does the pointing (the
            // target identifies itself — there is no overlay anchoring
            // primitive and inventing one was ruled out); this copy only
            // confirms what the ring marks. "The one you just made" names it by
            // her action, not by our noun for it.
            return "The one you just made. Tap it to open."
        case .detailTour:
            // Orientation, not curriculum (F13 holds): describes what the
            // screen is FOR in her words. No ontology nouns — "recordings",
            // never "parts", because this beat is describing rather than
            // labelling a thing she'll tap. Section order matches the shipped
            // layout: title/summary → topics → projects → mentions → clips.
            return "The title and summary are up top, then your recordings. Below those: ways to find this again later — topics, projects, and anyone you mentioned."
        case .organize:
            // Step 4. Honest Label: the app writes the title/summary — its
            // sentences, not the user's words; it draws only on the clip.
            return alreadyOrganized
                ? "The app already wrote the title and summary, using only what's in your recordings. You can run it again whenever you want."
                : "Tap Organize when you're ready. The app reads your recordings and writes a title and summary, using only what's in them. Nothing happens until you ask."
        case .done:
            // Step 5 · confirmation + payoff. The title carries "That's a memory";
            // the body names where it lives. `closingLine` (the ? / re-run hand-
            // off) rides this final beat now that the ontology beat is retired.
            return "You'll find it under Memories anytime."
        }
    }

    // MARK: Deviation copy (shown only on an observed wrong action — F10)

    /// She tapped the picture of the button, not the button (F11 / F10 ch.2).
    static let fabIllustrationDeviation = "That's a picture of the button. The real + is in the bottom corner — tap it."

    /// A recording was discarded before it produced a clip — say so rather than
    /// drop her back on the record prompt in silence.
    static let discardedDeviation = "That one didn't save. Tap + to try again whenever you're ready."

    /// The single closing line on the final beat (`done`): the per-section `?`
    /// hand-off (F7c) + the re-run path (Settings → Learn). One light exhale.
    /// F27 · name the CONTROL, not just a location. The old line pointed at
    /// "Settings → Learn" — a real path, but it stopped at the door: what she
    /// taps once inside is a row called **Show me around**, and nothing told
    /// her that. A breadcrumb that names a place but not the thing to press
    /// is how "I have no idea what I'm supposed to do" happens one screen
    /// later. Bound to the shipped row by `WalkthroughBreadcrumbTests`.
    static let closingLine = "Anytime: tap ? beside a section for help, or start this again from Learn → Show me around."

    /// The breadcrumb beside "Got it." so a dismissal never drops the user with
    /// nowhere to go. Not shown on the final beat, which carries `closingLine`.
    /// F27 · names the nearer path and the control. `Settings → Learn` was
    /// true but was the LONGER of two routes — there is a `?` in the toolbar
    /// of the screen she is already on — and it never named the row she has
    /// to recognise when she arrives.
    static let skipBreadcrumb = "You'll find this again in Learn — tap ? at the top, then Show me around."
}
