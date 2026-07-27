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
/// from restoring coachmarks to relaunching this. Sibling to
/// `CoachmarkOrchestrator`; the per-tab coachmark cards retire once this is
/// device-verified (green-to-green — a later commit).
///
/// The state machine is the spine (this file). The anchored overlay UI and the
/// pipeline-signal wiring that calls `recordingDidStart()` / `nextClipStarted()`
/// / `recordingDidCancel()` / `clipDidLand()` / `memoryDidStart()` /
/// `organizeDidComplete()` live in the overlay + `VoiceCaptureScreen`. The
/// `onARoll` beat (1b) is rendered in-composer because the root overlay can't
/// reach over the recording screen's `fullScreenCover`.
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
        case organize    // Free: spotlight Organize · Plus: narrate
        case done        // spotlight the title + summary, "clips are what you catch; memories are what they become"

        var id: Int { rawValue }
    }

    /// The active beat; `nil` when the walkthrough isn't running. Published so
    /// the overlay host presents it (same pattern as `CoachmarkOrchestrator.visible`).
    @Published var activeBeat: Beat?

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
        case .record, .onARoll, .rolling, .makeMemory, .organize, .none: break
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
    func memoryDidStart(id: UUID? = nil) {
        if activeBeat == .makeMemory {
            walkthroughMemoryId = id
            activeBeat = .organize
        }
    }

    /// The memory's organize pass completed — its title + summary now exist
    /// (`entry.lastOrganizedAt` + `inferenceSummary`). On Plus this fires ~at
    /// once after `memoryDidStart` (beat 5 collapses to a narration); on Free
    /// it fires after the user taps Organize.
    func organizeDidComplete() { if activeBeat == .organize { activeBeat = .done } }
}

// MARK: - Copy (design-authority · drafted for cold validation, F7e · no "evidence", F7g)

extension WalkthroughOrchestrator.Beat {
    /// The card headline for each beat (nil where the beat is a bare spotlight
    /// prompt carried entirely by `body`).
    var title: String? {
        switch self {
        case .offer:   return "Make your first memory"
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
            return "Want to make your first memory together? It takes about a minute — I'll point at each step."
        case .record:
            // Name the control — the banner sits at the top, away from the FAB
            // stack, so "tap here" would have no referent (device pass 2026-07-26).
            return "Tap Voice and say something on your mind — out loud. Anything. This becomes a clip."
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
            return "There's your clip, saved here in Clips. Clips are the building blocks of memories. Clips wait here until you decide where they belong — nothing's lost."
        case .concept:
            return "A memory is made of one or more clips. You have one clip now. Next you'll turn it into a memory."
        case .makeMemory:
            return "Open your clip and tap Start a Memory. Your clip becomes the first part of that memory."
        case .organize:
            return isPlus
                ? "The app already read your clip and wrote a title and summary from your own words."
                : "Tap Organize — the app reads your clip and writes a title and summary from your own words."
        case .done:
            return "That's a memory: your clip, plus a title and summary written from your own words. Clips are what you catch; memories are what they become."
        }
    }

    /// The recoverability line shown on the final beat (verbatim from F2b).
    static let recoverabilityLine = "Bring this walkthrough back any time from ? → Show me around."
}
