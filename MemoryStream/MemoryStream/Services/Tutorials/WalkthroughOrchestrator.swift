import Foundation
import SwiftUI

/// F8 · the guided first walkthrough — a **do-it-with-me** sequence, not a card
/// tour. The user records a real first capture with guidance at each beat and
/// learns the ontology (a clip becomes a memory) by watching it happen, on the
/// **ad-hoc path** (Clips **+** → bench → Start a Memory — the only path that
/// *shows* the clip→memory relationship; the direct Memories composer hides it).
///
/// Offered once on first run (post-onboarding), skippable, and **re-runnable
/// from ? → Show me around** — the same recoverability F2b built, repointed
/// from restoring coachmarks to relaunching this. It **replaced** the per-tab
/// coachmark cards, retired 2026-07-27 once F8 + F7c (section-?) covered the
/// ground.
///
/// The state machine is the spine (this file). The anchored overlay UI and the
/// pipeline-signal wiring that calls `recordingDidStart()` / `nextClipStarted()`
/// / `recordingDidCancel()` / `clipDidLand()` / `memoryDidStart()` /
/// `memoryDidOpen()` / `organizeDidComplete()` live in the overlay +
/// `VoiceCaptureScreen` + `EntryExpandedView`. Two beats render outside the
/// root overlay's reach: `onARoll` (1b) in-composer (the recording screen is a
/// `fullScreenCover`); the `organize`/`done` beats only arm once
/// `EntryExpandedView` reports the memory opened (`memoryDidOpen`), because
/// Start a Memory returns to Clips without navigating to Memory Detail.
///
/// Spec: `Handoff · punch list · 2026-07-25.md` §F8. Copy is design-authority
/// (drafted for cold validation per F7e; no "evidence" per F7g).
@MainActor
final class WalkthroughOrchestrator: ObservableObject {
    static let shared = WalkthroughOrchestrator()

    /// The beats, in order. `record` / `onARoll` / `makeMemory` / `organize`
    /// advance on a REAL pipeline signal (the user actually acts); `offer` /
    /// `clipLanded` / `concept` / `done` advance on a tap. `rolling` is a silent
    /// holding state (see `onARoll`).
    enum Beat: Int, CaseIterable, Identifiable {
        case offer       // "make your first memory together?"
        case record      // spotlight the +, "say something out loud — this is a clip"
        case onARoll     // shown WHILE recording, anchored to Next — "tap Next to keep going" (1b)
        case rolling     // silent: onARoll retired after a Next tap, still awaiting the clip to land
        case clipLanded  // spotlight the bench card, "clips are the building blocks of memories"
        case concept     // centered card, "a memory is made of one or more clips" (F7b)
        case makeMemory  // spotlight Start a Memory
        case openMemory  // spotlight the "Memory created · View" toast — bridge Clips → Memory Detail
        case organize    // Free: spotlight Organize · Plus: narrate — on Memory Detail
        case done        // spotlight the title + summary, "clips are what you catch; memories are what they become"

        var id: Int { rawValue }
    }

    /// The active beat; `nil` when the walkthrough isn't running. Published so
    /// the overlay host presents it. Any beat change resets `currentBannerRetired`
    /// so the new beat's card shows fresh.
    @Published var activeBeat: Beat? { didSet { currentBannerRetired = false } }

    /// True when the user tapped "Got it." on the current beat — retires THIS
    /// beat's banner only. No advance, no completion, no new state: the
    /// walkthrough stays armed and the next beat fires on its real signal
    /// (Tom 2026-07-27). Reset automatically on every beat change (didSet above).
    @Published var currentBannerRetired = false

    /// The memory the user created during the walkthrough (set by
    /// `memoryDidStart`). The host watches THIS entry for organize completion —
    /// `lastOrganizedAt` / `inferenceSummary` is not broadcast, so the host
    /// checks it on Core Data change and calls `organizeDidComplete()`.
    private(set) var walkthroughMemoryId: UUID?

    private let completedKey = "himem.walkthrough.completed"

    private init() {}

    var isRunning: Bool { activeBeat != nil }

    /// Persisted so first-run offers it exactly once (skip counts as done — a
    /// declined offer isn't re-nagged; it's always retrievable from the hub).
    var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    // MARK: - Lifecycle

    /// Offer on first run — once, after onboarding, unless already completed or
    /// skipped. No-op if a walkthrough is already active.
    func offerIfFirstRun() {
        guard !hasCompleted, activeBeat == nil else { return }
        activeBeat = .offer
    }

    /// Explicit relaunch from "? → Show me around". Always starts fresh at the
    /// offer beat, regardless of `hasCompleted`.
    func start() { activeBeat = .offer }

    /// The user accepted the offer → begin the guided capture.
    func beginFromOffer() { if activeBeat == .offer { activeBeat = .record } }

    /// Skip / dismiss at any beat. Marks complete so first-run won't re-offer;
    /// the walkthrough stays retrievable from the hub.
    func skip() { finish() }

    /// The teaching card's "Got it." — retires THIS beat's banner, nothing more.
    /// One button, one meaning on every beat: "I've read this card." It never
    /// abandons the walkthrough. On the tap-gated read beats (clipLanded /
    /// concept / done) the card IS the gate, so retiring it is their existing
    /// continue (unchanged behavior). On the signal beats (record / makeMemory /
    /// openMemory / organize) it just hides the card; the walkthrough stays
    /// armed and the next beat fires on its real signal — the pipeline-beat
    /// invariant is untouched (Tom 2026-07-27).
    func gotIt() {
        switch activeBeat {
        case .clipLanded, .concept, .done:
            advance()
        case .record, .makeMemory, .openMemory, .organize:
            currentBannerRetired = true
        case .offer, .onARoll, .rolling, .none:
            break
        }
    }

    private func finish() {
        activeBeat = nil
        walkthroughMemoryId = nil
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Tap-advance for the read-only beats (`concept`, `done`). The pipeline
    /// beats (`record`, `onARoll`, `makeMemory`, `organize`) and the silent
    /// `rolling` beat ignore taps — they wait for the real signal below so
    /// guidance never gets ahead of the user.
    func advance() {
        switch activeBeat {
        case .offer:      activeBeat = .record   // also reachable via beginFromOffer
        case .clipLanded: activeBeat = .concept
        case .concept:    activeBeat = .makeMemory
        case .done:       finish()
        case .record, .onARoll, .rolling, .makeMemory, .openMemory, .organize, .none: break
        }
    }

    // MARK: - Real-pipeline advance signals (called by the F8 wiring commit)

    /// Recording actually began (mic hot). Moves off the "tap Voice" prompt into
    /// the **on-a-roll** beat, shown in-composer anchored to Next — the root
    /// overlay can't reach over the composer's `fullScreenCover`, so
    /// `VoiceCaptureScreen` renders this beat itself.
    func recordingDidStart() { if activeBeat == .record { activeBeat = .onARoll } }

    /// The user tapped **Next** (started a fresh clip without stopping). The
    /// on-a-roll teaching has landed, so retire its banner — but stay armed:
    /// `rolling` is silent and still awaits the clip to land on the bench.
    func nextClipStarted() { if activeBeat == .onARoll { activeBeat = .rolling } }

    /// The user discarded the recording (✕ / cancel) without producing a clip.
    /// Return to the `record` prompt so the walkthrough isn't left stuck on an
    /// in-composer beat once the composer dismisses.
    func recordingDidCancel() {
        if activeBeat == .onARoll || activeBeat == .rolling { activeBeat = .record }
    }

    /// The clip finished recording and returned to Clips + materialized on the
    /// bench (`CaptureLandingBus.pendingReturnToClips` / arrival materialize).
    /// Reachable from `record` (stopped before the on-a-roll beat rendered — a
    /// defensive path), `onARoll` (stopped without ever tapping Next), or
    /// `rolling` (tapped Next, then stopped).
    func clipDidLand() {
        switch activeBeat {
        case .record, .onARoll, .rolling: activeBeat = .clipLanded
        default: break
        }
    }

    /// The user created a memory from the clip (Start a Memory). `id` is the new
    /// memory — tracked so the host can watch it for organize completion.
    ///
    /// Advances to `openMemory`, NOT straight to `organize` — Start a Memory
    /// dismisses to the calm Clips list with a "Memory created · View" toast
    /// (the locked "no teleport" spec); the organize/done beats point at
    /// controls that only exist on Memory Detail, so they must wait until the
    /// user actually opens it (`memoryDidOpen`). Arming `organize` here would
    /// display it against a control that isn't on screen (device pass 2026-07-26,
    /// beats 5/6 never fired on Memory Detail).
    func memoryDidStart(id: UUID? = nil) {
        if activeBeat == .makeMemory {
            walkthroughMemoryId = id
            activeBeat = .openMemory
        }
    }

    /// The walkthrough's memory opened on Memory Detail (its `EntryExpandedView`
    /// appeared, by any route). Only now — with Organize and the title/summary
    /// on screen — do the organize/done beats arm.
    ///
    /// `alreadyOrganized` skips straight to `done`: on Plus the memory
    /// auto-organizes at creation (`processEntry`), so by the time the user
    /// opens it the title + summary already exist and there's no Organize to
    /// point at — `done` names the result. On Free (manual organize) it's
    /// false, so `organize` arms and waits for the user's Organize tap.
    func memoryDidOpen(alreadyOrganized: Bool) {
        guard activeBeat == .openMemory else { return }
        activeBeat = alreadyOrganized ? .done : .organize
    }

    /// The memory's organize pass completed — its title + summary now exist
    /// (`entry.lastOrganizedAt` + `inferenceSummary`). On Free this fires after
    /// the user taps Organize; on Plus, if the auto-organize finishes *after*
    /// the user opened the memory, it advances the narration to `done`.
    func organizeDidComplete() { if activeBeat == .organize { activeBeat = .done } }
}

// MARK: - Copy (design-authority · drafted for cold validation, F7e · no "evidence", F7g)

extension WalkthroughOrchestrator.Beat {
    /// The card headline for each beat (nil where the beat is a bare spotlight
    /// prompt carried entirely by `body`).
    var title: String? {
        switch self {
        case .offer:   return "Want to walk through it together?"
        case .concept: return "Clips become memories"
        case .done:    return "That's a memory"
        default:       return nil
        }
    }

    /// The coaching sentence. `isPlus` only changes the `organize` beat: on Free
    /// the user taps Organize; on Plus it already ran, so we narrate instead of
    /// pointing at a button that isn't there.
    func body(isPlus: Bool) -> String {
        switch self {
        case .offer:
            // Honest from ANY tab — "make your first memory" wrong-foots a user
            // launching from Clips (they're looking at parts). Name the arc
            // instead (Tom 2026-07-27). The title carries the invite question.
            return "You'll catch a part, then turn it into a memory. About a minute — I'll point at each step."
        case .record:
            // Beat 1 is the first concept moment — state the whole model (a
            // memory = one-or-more parts; the + adds parts/memories) BEFORE
            // naming the tap, so it doesn't silently teach "memory = voice" or
            // name "Voice" before the user has seen the FAB stack. Longest
            // banner in the flow, intentionally (Tom, 2026-07-27). "parts" not
            // "evidence" (F7g). The banner also carries the FAB-stack
            // illustration (see the overlay) so "tap +, tap Voice" points at
            // something recognizable.
            return "A memory is made up of one or more parts — voice notes or text notes, photos, video. The + button, which you'll see in various places, adds parts or memories, as applicable. Tap it and you'll see the options.\n\nFor now: tap +, tap Voice, and start your first memory with your first part."
        case .onARoll:
            // 1b — shown WHILE recording, anchored to Next. Introduces the
            // on-a-roll affordance a first-time user would otherwise tap-and-
            // wonder about. Tier-independent (drafted for cold validation, F7e).
            return "Still talking? Tap Next to start a new clip without stopping. They'll stay together."
        case .rolling:
            // Silent holding state — never rendered (retired after a Next tap,
            // awaiting the clip to land). No copy.
            return ""
        case .clipLanded:
            // Beat 2 · the load-bearing concept moment for Clips — the user is
            // on the bench looking at their first clip. Teach the whole clip
            // concept: a clip is a PART of a memory, and the bench exists so
            // you capture now and decide later. Second-longest banner after
            // beat 1, intentionally. "parts" per F7g. (Tom 2026-07-27.)
            return "There's your clip — a part, saved on the bench. Parts are what you catch in the moment; you decide what they become later. Nothing's lost while it waits here."
        case .concept:
            // "parts" for the concept (F7g); "clip" where it's her concrete one.
            return "A memory is made of one or more parts. You have one clip now. Next you'll turn it into a memory."
        case .makeMemory:
            return "Open your clip and tap Start a Memory. Your clip becomes the first part of that memory."
        case .openMemory:
            // Bridges Clips → Memory Detail. The app doesn't teleport you there
            // (locked no-teleport spec), so name the toast's control. Tier-
            // independent. (F7e — draft, not declared clear.)
            return "Your memory is saved. Tap View to open it."
        case .organize:
            // Honest Label (Tom 2026-07-27): the AI writes the title/summary —
            // they're the app's sentences, not the user's words. Name that it
            // draws only on the clip and adds nothing; never "your own words."
            return isPlus
                ? "The app already read your clip and wrote a title and summary, using only what's in it — nothing added."
                : "Tap Organize — the app reads your clip and writes a title and summary, using only what's in it."
        case .done:
            return "That's a memory: your clip, plus a title and summary the app wrote using only what's in it. Clips are what you catch; memories are what they become."
        }
    }

    /// The single closing line on the final beat — the exhale should feel
    /// light, so both promises fold into one line rather than a wall of three
    /// text blocks (Tom, 2026-07-27). Names the per-section `?` help (F7c,
    /// Option B — no screen-level nav `?`) and the re-run path (Settings → Learn,
    /// where the walkthrough lives — no new affordance just to make copy true).
    /// Copy approved.
    static let closingLine = "Anytime: tap ? beside a section for help, or run this walkthrough again from Settings → Learn."

    /// The breadcrumb shown beside Skip so a bare "Skip" never drops the user
    /// with nowhere to go — the multi-beat walkthrough is the one place a skip
    /// belongs, and it must say where the coaching went (Tom, 2026-07-27). Not
    /// shown on the final beat, which already carries `closingLine`.
    static let skipBreadcrumb = "You'll find this again in Settings → Learn."
}
