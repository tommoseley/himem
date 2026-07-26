import Foundation

/// Per-tab first-arrival anchored coachmark trigger — the "Take a
/// tour of the screen" surface that fires **once per tab, ever**.
///
/// Guardrails locked in `docs/design/Tutorials · triggers spec.md`
/// §"Per-tab coachmark on first arrival (locked July 9 2026)":
///
/// 1. **Once ever per tab.** Persisted per-tab `seenCoachmark_<tab>`
///    flag; three tabs → at most three lifetime auto-fires.
/// 2. **Anchored coachmark, not a full-pager** — the presentation
///    layer (`CoachmarkView`) handles this.
/// 3. **Suppress the Clips coachmark when arriving from a capture.**
///    Recording returns to Clips; a tour there is interrupting
///    creation. Defer to the next *neutral* arrival at Clips.
/// 4. **Never on cold first launch.** Per-tab coachmarks begin on the
///    second session, or once a tab has content to anchor to —
///    whichever is first.
/// 5. **Skip is always present and always instant** — dismissed
///    entries mark seen immediately.
@MainActor
final class CoachmarkOrchestrator: ObservableObject {
    static let shared = CoachmarkOrchestrator()

    /// The tabs that carry a first-arrival coachmark. Order matches
    /// `HiMemTabView.Tab` for wiring symmetry. `Identifiable` so
    /// `.fullScreenCover(item:)` accepts the published value.
    enum Kind: String, CaseIterable, Identifiable {
        case clips
        case memories
        case projects

        var id: String { rawValue }
        fileprivate var seenKey: String { "himem.coachmark.\(rawValue).seen" }
    }

    /// Currently-visible coachmark, if any. Published so
    /// `HiMemTabView`'s overlay can fullScreenCover it and route
    /// dismiss back through `dismiss(_:)`.
    @Published var visible: Kind? = nil

    /// Persistent session counter — the "second session" gate. Bumped
    /// once per cold launch by `armSession()`.
    private let sessionCounterKey = "himem.session.counter"

    private init() {}

    /// Call once per cold launch (from the app root's `.onAppear` or
    /// scene lifecycle). Bumps the session counter that gates guard
    /// #4. Idempotent within a session because it only runs at cold
    /// launch — `HiMemTabView.onAppear` on tab switches is not called
    /// on the app-level cold launch.
    func armSession() {
        let current = UserDefaults.standard.integer(forKey: sessionCounterKey)
        UserDefaults.standard.set(current + 1, forKey: sessionCounterKey)
    }

    /// Current session count. Cold launch #1 → 1; cold launch #2 → 2.
    var sessionCount: Int {
        UserDefaults.standard.integer(forKey: sessionCounterKey)
    }

    /// Whether the user has already dismissed (or already saw) this
    /// tab's coachmark.
    func hasSeen(_ kind: Kind) -> Bool {
        UserDefaults.standard.bool(forKey: kind.seenKey)
    }

    /// Trigger surface calls on tab arrival. Silent no-op unless every
    /// gate passes.
    ///
    /// - `tabHasContent`: is there anything to anchor to? Used with
    ///   `sessionCount >= 2` as the "not cold-first-launch" gate.
    /// - `suppressedByCaptureArrival`: only meaningful for Clips —
    ///   defers when the user just landed here from a capture.
    func tryFire(
        _ kind: Kind,
        tabHasContent: Bool,
        suppressedByCaptureArrival: Bool = false
    ) {
        guard !hasSeen(kind) else { return }
        guard !suppressedByCaptureArrival else { return }
        guard sessionCount >= 2 || tabHasContent else { return }
        guard visible == nil else { return } // already showing one
        visible = kind
    }

    /// Called by the overlay when the user taps Skip, Got it, or the
    /// scrim. Marks seen immediately (guardrail #5 — skip is
    /// instant + permanent).
    func dismiss(_ kind: Kind) {
        UserDefaults.standard.set(true, forKey: kind.seenKey)
        if visible == kind { visible = nil }
    }

    // MARK: - Recoverability ("Show me around", F2b · 2026-07-26)

    /// Set by `restoreTour()`; `HiMemTabView` observes it, waits for the Learn
    /// hub to finish popping, then re-fires the current tab's coachmark via
    /// `consumeRestore(currentTab:)`. The two-step (flag → consume) exists
    /// because the coachmark's `fullScreenCover` can't present until the hub's
    /// navigation pop settles.
    @Published var restorePending = false

    /// "Show me around" (Learn hub) → restore the anchored tour. Clears every
    /// per-tab seen flag so each tab re-coaches on first visit, exactly like a
    /// fresh install — but deliberately does **not** touch the session counter:
    /// the user is well past the second-session gate, and a manual restore must
    /// re-coach now, not wait for a cold launch. Sets `restorePending` so the
    /// current tab re-fires once the hub closes. Spec: `Tutorials · triggers
    /// spec.md` §"Coachmark recoverability".
    func restoreTour() {
        for kind in Kind.allCases {
            UserDefaults.standard.removeObject(forKey: kind.seenKey)
        }
        restorePending = true
    }

    /// Consume a pending restore: fire `currentTab`'s coachmark now. Called by
    /// `HiMemTabView` after the hub has popped. The explicit-request path, so
    /// it bypasses the session/content gate `tryFire` enforces — the user asked
    /// for the tour by name.
    func consumeRestore(currentTab: Kind) {
        restorePending = false
        forceFire(currentTab)
    }

    /// Fire `kind` unconditionally (no session/content gate) unless a coachmark
    /// is already showing. Backs the explicit "Show me around" re-fire.
    func forceFire(_ kind: Kind) {
        guard visible == nil else { return }
        visible = kind
    }

    // MARK: - Debug helpers

    /// Reset every coachmark's seen flag AND the session counter AND
    /// the transient `visible` state. Wired to Settings → Debug so
    /// the tour can be rehearsed; also used by tests for isolation.
    func debugResetAll() {
        for kind in Kind.allCases {
            UserDefaults.standard.removeObject(forKey: kind.seenKey)
        }
        UserDefaults.standard.removeObject(forKey: sessionCounterKey)
        restorePending = false
        visible = nil
    }
}
