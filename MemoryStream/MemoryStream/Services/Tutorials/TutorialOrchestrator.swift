import SwiftUI
import Combine

/// Decides whether an auto-fire tutorial should surface NOW. Surface
/// code calls `tryFire(.organizing)` (etc.) at the natural trigger
/// moment; the orchestrator either returns true (caller presents the
/// tutorial; `markSeen` flips the persisted flag on dismiss) or false
/// (the call is a silent no-op — the unseen flag means the *next*
/// natural trigger re-attempts, satisfying the once-each guarantee
/// without queueing).
///
/// **Locked rules** (per `docs/design/Tutorials · triggers spec.md`,
/// June 11 2026):
/// - Every tutorial fires automatically, **exactly once**. Persisted
///   per-tutorial `hasSeen<Name>` flag; only `markSeen` flips it.
/// - **One auto-tutorial per session, max one per day — by deferral,
///   never cancellation.** A deferred fire keeps its unseen state and
///   re-attempts at its next natural trigger.
/// - Never during onboarding, never on cold launch (≥ 1 user
///   navigation has happened), never mid-task.
/// - Tier-aware: #3 (`findTheThread`) is Plus-only. The orchestrator
///   reads `Entitlement.shared.isPlus` directly.
///
/// **No queue.** There is no "pending tutorials" data structure. The
/// natural trigger event IS the queue — deferred tutorials re-fire
/// the next time the user reaches that surface.
@MainActor
final class TutorialOrchestrator: ObservableObject {
    static let shared = TutorialOrchestrator()

    /// Identifies an auto-fire tutorial. Hub-only rows (Topics,
    /// Storage) do not appear here — they have no orchestrator state.
    enum Tutorial: String, CaseIterable, Identifiable {
        case capture           // #1 — phone voice composer, first run, zero recordings
        case organizing        // #2 — first Draft-organized state (either tier)
        case findTheThread     // #3 — Plus, project detail ≥3 memories, unrun
        case watchStory        // #4 — Captured Clips opened non-empty
        case watchDiscovery    // #5 — WCSession.isPaired && !isWatchAppInstalled
        case siri              // #6 — Today, memoryCount >= 3, both tiers

        var id: String { rawValue }

        var hasSeenKey: String {
            "himem.tutorial.\(rawValue).hasSeen"
        }

        /// Plus-only? Tier check happens before any other gate so a
        /// Free user never even consumes session/day cap on #3.
        var isPlusOnly: Bool { self == .findTheThread }
    }

    /// Currently-visible auto-fire tutorial, if any. Published so a
    /// single root-level overlay (mounted once at the app root) can
    /// present it via `fullScreenCover(item:)` and call `dismiss(_:)`
    /// when the user × or CTA-taps. This keeps every trigger
    /// callsite to a single one-liner — they call `tryFire(.x)` and
    /// trust the root to render.
    @Published var visible: Tutorial? = nil

    /// In-process flag: has this session already shown one auto-fire?
    /// Resets every cold launch (the orchestrator is a singleton, so
    /// this lives as long as the process does).
    private var sessionFiredOne: Bool = false

    /// Date of the last auto-fire (any tutorial). Compared against
    /// `Calendar.current.isDateInToday(_:)` for the max-one-per-day
    /// rule. Persisted across launches.
    private static let lastFireDateKey = "himem.tutorial.lastAutoFireDate"

    /// Suppresses ALL auto-fires until set to true. Cold launch sets
    /// it false; the first user-initiated navigation flips it on.
    /// "Cold launch" is the brief window between app activation and
    /// the user's first meaningful tap — we don't want a tutorial to
    /// land on the launch screen.
    ///
    /// The flag is *post*-onboarding too: PermissionWizardView calls
    /// `armForReadyState()` only when the wizard finishes. If a user
    /// is still in onboarding, this stays false.
    @Published private(set) var isArmed: Bool = false

    /// Flip from `OnboardingComplete` / "user has navigated at least
    /// once after launch". Call this from `LaunchScreenView` when the
    /// main UI takes over.
    func armForReadyState() {
        isArmed = true
    }

    /// True if the user has already dismissed (or already saw) this
    /// tutorial. Reads UserDefaults directly so the value is honest
    /// the moment a trigger asks.
    func hasSeen(_ tutorial: Tutorial) -> Bool {
        UserDefaults.standard.bool(forKey: tutorial.hasSeenKey)
    }

    /// Trigger surface calls this at the natural moment. If all
    /// gates pass, the orchestrator publishes the tutorial via
    /// `visible` and the root-level overlay renders it. The trigger
    /// site doesn't need to do anything else.
    ///
    /// Silent no-op if any gate fails — the unseen flag stays put,
    /// so the next natural trigger re-attempts. Satisfies the spec's
    /// once-each-guarantee + max-one-per-session/day-by-deferral
    /// rules without a queue.
    func tryFire(_ tutorial: Tutorial) {
        guard isArmed else { return }
        // F8 owns first-run teaching. While the guided walkthrough runs, the
        // legacy one-pager auto-tutorials must NOT fire: a `.capture` fire lands
        // over the walkthrough's composer and sets `visible`, and the composer's
        // auto-boot is gated on `visible == nil` — so the recorder never starts
        // and beat 1 is terminal (F9, 2026-07-28). They stay reachable from
        // Settings → Learn; on walkthrough end they're marked seen (below).
        guard !WalkthroughOrchestrator.shared.isRunning else { return }
        guard !hasSeen(tutorial) else { return }
        guard !(tutorial.isPlusOnly && !Entitlement.shared.isPlus) else { return }
        guard !sessionFiredOne else { return }
        guard !firedToday else { return }
        guard visible == nil else { return } // already presenting
        sessionFiredOne = true
        UserDefaults.standard.set(Date(), forKey: Self.lastFireDateKey)
        visible = tutorial
    }

    /// Called by the root-level overlay when the user dismisses
    /// (× tap or CTA tap). Marks the tutorial as seen so it never
    /// auto-fires again, and clears the visibility flag.
    func dismiss(_ tutorial: Tutorial) {
        UserDefaults.standard.set(true, forKey: tutorial.hasSeenKey)
        if visible == tutorial { visible = nil }
    }

    /// Called when the F8 guided walkthrough ends — completed OR abandoned. F8
    /// is the single owner of first-run teaching, so the one-pagers it already
    /// covers — `.capture` and `.organizing` — are marked seen and never
    /// auto-fire again: re-teaching a step she just performed is the redundant
    /// push F13 forbids, and a surprise one-pager after she opted out of guided
    /// teaching is the same abandonment-flavored confusion in reverse. Both stay
    /// pulled content in Settings → Learn (Tom 2026-07-28).
    func retireOnePagersReplacedByWalkthrough() {
        UserDefaults.standard.set(true, forKey: Tutorial.capture.hasSeenKey)
        UserDefaults.standard.set(true, forKey: Tutorial.organizing.hasSeenKey)
    }

    /// DEBUG path: clears the persisted seen flag for one tutorial so
    /// the next natural trigger re-fires it.
    func debugReset(_ tutorial: Tutorial) {
        UserDefaults.standard.removeObject(forKey: tutorial.hasSeenKey)
    }

    /// DEBUG path: clears every tutorial's seen flag AND the session/
    /// day caps. The next trigger fires.
    func debugResetAll() {
        for t in Tutorial.allCases {
            UserDefaults.standard.removeObject(forKey: t.hasSeenKey)
        }
        UserDefaults.standard.removeObject(forKey: Self.lastFireDateKey)
        sessionFiredOne = false
    }

    private var firedToday: Bool {
        guard let date = UserDefaults.standard.object(forKey: Self.lastFireDateKey) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    private init() {}
}

/// Mount this once at the app root. It observes the orchestrator's
/// `visible` property and presents the appropriate tutorial as a
/// `fullScreenCover`. Dismissal flows through `orchestrator.dismiss(_:)`
/// which flips the seen flag.
struct TutorialAutoFireOverlay: ViewModifier {
    @ObservedObject private var orchestrator = TutorialOrchestrator.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $orchestrator.visible) { tutorial in
            tutorialView(for: tutorial)
                .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private func tutorialView(for tutorial: TutorialOrchestrator.Tutorial) -> some View {
        // Each concrete view dismisses via its own SwiftUI environment
        // (`@Environment(\.dismiss)`) AND we hook the SwiftUI dismissal
        // back through the orchestrator's `dismiss(_:)` so seen-state
        // updates. The inner views are unchanged — they're the same
        // ones the hub uses for replay; only the dismiss-routing
        // changes via the `.onDisappear` below.
        Group {
            switch tutorial {
            case .capture:        CaptureTutorialView()
            case .organizing:     OrganizingTutorialView()
            case .findTheThread:  FindTheThreadTutorialView()
            case .watchStory:     WatchStoryTutorialView()
            case .watchDiscovery: WatchDiscoveryTutorialView()
            case .siri:           SiriTutorialView()
            }
        }
        .onDisappear {
            // Any dismiss path (× tap, CTA tap, swipe-down) flows
            // through here. Mark seen so the auto-fire never re-fires.
            TutorialOrchestrator.shared.dismiss(tutorial)
        }
    }
}

extension View {
    /// Mounts the auto-fire tutorial overlay. Apply at the app root —
    /// usually wrapping the top-level view that hosts both the
    /// authenticated journal and the onboarding wizard.
    func tutorialAutoFireOverlay() -> some View {
        modifier(TutorialAutoFireOverlay())
    }
}
