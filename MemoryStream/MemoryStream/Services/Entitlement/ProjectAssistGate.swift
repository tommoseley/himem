import Foundation

/// Pure decision: is the "Find the thread" button (Project Assist)
/// enabled for a project?
///
/// Spec intent (Projects MVP spec § Trigger, cost) is to activate
/// at ≥1 memory: "with one memory the 'summary' is closer to a
/// paraphrase than a synthesis — fine; the user gets back what
/// they asked for." Until we've validated the 1-memory output
/// feels honest in TestFlight, this ships with the threshold gated
/// off — production stays on the conservative ≥3 behavior.
///
/// Flip `allowSingleMemoryThreshold` to `true` when ready; the
/// spec-intended behavior takes over with no other code changes.
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
