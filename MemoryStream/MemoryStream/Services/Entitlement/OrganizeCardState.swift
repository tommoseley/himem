import Foundation

/// State machine for the Memory Detail "Organize this memory" card.
/// Two states after the assist-quota retirement (PR 8c):
///
///   • `.idle` — never organized; show the manual Organize button.
///     Free taps to run on-device; Plus auto-runs and replaces this
///     surface with the review chip + body almost immediately.
///   • `.reorganize(newClipCount:)` — already organized but new
///     clips have arrived. Compact dashed callout offering to fold
///     them in via another pass.
///
/// Retired in this PR: `.exhausted(ExhaustedVariant)` and
/// `.stale(StaleVariant)` — both modeled tier-aware exhaustion
/// (STARTER USED / MONTHLY USED), which no longer exists in the
/// Capture · Connect · Create model. Stale is now surfaced as a
/// separate warning banner per `pricing-screens-lifecycle.jsx`
/// Stage 3st, not as a card variant.
enum OrganizeCardState: Equatable {
    case idle
    case reorganize(newClipCount: Int)
    /// A previous organize attempt failed and produced no pass (Ruling 2,
    /// 2026-07-25). An honest, retryable card — never a silent reset to idle.
    /// `offline` picks the copy ("Tap to try again." vs "try again when you're
    /// back online"). Tapping re-runs organize; no auto-retry.
    case failed(offline: Bool)
}
