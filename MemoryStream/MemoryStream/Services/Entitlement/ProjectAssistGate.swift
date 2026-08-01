import Foundation

/// Pure decision: is the "Find the thread" button (Project Assist)
/// enabled for a project?
///
/// Per the Projects MVP spec (§ Trigger, cost) this activates at **≥1
/// memory**: "with one memory the 'summary' is closer to a paraphrase than a
/// synthesis — fine; the user gets back what they asked for."
///
/// **That is the shipping behaviour.** `allowSingleMemoryThreshold` was
/// flipped to `true` on 2026-06-01, so `minimumMemories` is 1. This header
/// used to say the opposite — "ships with the threshold gated off, production
/// stays on the conservative ≥3" — contradicting the property's own doc four
/// lines below it. Corrected 2026-07-31; the flag survives as the way back to
/// ≥3 if the one-memory output ever reads as thin.
enum ProjectAssistGate {
    /// Set to `true` to use the spec-intended ≥1 memory threshold.
    /// `false` keeps the previous conservative ≥3 behavior for the
    /// "until we're sure it's working well" window. Flipped to `true`
    /// 2026-06-01 ahead of TestFlight QA — the spec is the contract,
    /// and the one-memory paraphrase output is honest per `docs/design
    /// /CLAUDE.md` § Projects.
    static let allowSingleMemoryThreshold: Bool = true

    static var minimumMemories: Int {
        allowSingleMemoryThreshold ? 1 : 3
    }

    static func isEnabled(memoryCount: Int) -> Bool {
        memoryCount >= minimumMemories
    }
}
