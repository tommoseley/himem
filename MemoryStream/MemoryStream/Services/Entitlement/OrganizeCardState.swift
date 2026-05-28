import Foundation

/// State machine for the Memory Detail AI zone. Pure data type — no
/// SwiftUI dependency — so the entitlement → presentation mapping
/// can be derived and tested in the controller layer instead of
/// inside view files. Per Tom's 2026-05-28 note: business logic
/// belongs in models / controllers, not in UX.
///
/// The view (`OrganizeMemoryCard`) takes one of these and renders
/// it; the resolver functions below pick the right variant from
/// `EntitlementService` state.
enum OrganizeCardState: Equatable {
    case idle
    case reorganize(newClipCount: Int)
    /// Never-organized memory, user is out of assists. Variant
    /// carries the tier-specific pill, body, and CTA route per
    /// pricing spec A3 (free) + C3 (plus). The swap must read
    /// identically to the `.stale` variants so the user sees a
    /// consistent exhaustion treatment across first-pass and
    /// reorganize cards.
    case exhausted(ExhaustedVariant)
    /// Memory has been organized but new clips arrived since the
    /// last pass. Same shape as `.idle` but titled "Reorganize
    /// with AI". The variant carries tier-specific pill copy +
    /// body + CTA route per pricing spec § 16:
    ///   • `.available`        → ochre `1 ASSIST` pill, refresh CTA
    ///   • `.freeExhausted`    → amber `STARTER USED` badge, See options → Upgrade Hub
    ///   • `.plusExhausted`    → amber `MONTHLY USED` badge, Get more → pack modal
    case stale(StaleVariant)

    enum StaleVariant: Equatable {
        case available
        case freeExhausted
        case plusExhausted(resetDate: Date?)
    }

    enum ExhaustedVariant: Equatable {
        case freeExhausted
        case plusExhausted(resetDate: Date?)
    }

    // MARK: - State resolution (pure, testable)

    /// Picks idle vs. exhausted for a never-organized memory based
    /// on the entitlement values. Free → `.exhausted(.freeExhausted)`;
    /// Plus → `.exhausted(.plusExhausted)` with reset date. Per QA
    /// script Part A (free) + Part C (plus). Pure so tests can
    /// assert the mapping without rendering.
    static func idleOrExhausted(
        hasAssists: Bool,
        isPlus: Bool,
        monthlyResetDate: Date?
    ) -> OrganizeCardState {
        if hasAssists { return .idle }
        return isPlus
            ? .exhausted(.plusExhausted(resetDate: monthlyResetDate))
            : .exhausted(.freeExhausted)
    }

    /// Picks the stale variant given refresh capability + tier. Per
    /// QA script § 16. Same shape as `idleOrExhausted` so the pill +
    /// body swap reads identically across first-pass and reorganize
    /// cards (F3 invariant).
    static func staleVariant(
        canRefresh: Bool,
        isPlus: Bool,
        monthlyResetDate: Date?
    ) -> StaleVariant {
        if canRefresh { return .available }
        return isPlus
            ? .plusExhausted(resetDate: monthlyResetDate)
            : .freeExhausted
    }
}
