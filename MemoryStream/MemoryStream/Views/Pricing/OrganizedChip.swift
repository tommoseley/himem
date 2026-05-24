import SwiftUI

/// Variant-aware "Organized" chip — the collapsed state of the
/// AISuggestionsCard. Variants by precedence (highest first):
///
///   1. **Stale + has assists** → "✦ Organized · refresh"
///      (orange tint; tap to unfold reveals the refresh affordance)
///   2. **Stale + no assists**  → "✦ Organized · stale"
///      (orange tint; tap to unfold reveals "Resets [date]")
///   3. **Has next steps**      → "✦ Organized · N next steps"
///      (default tint; surfaces the unread item count)
///   4. **Default**             → "✦ Organized · review"
///      (default tint; just a fold toggle)
///
/// The chip is purely a label — its tap behavior is wired by the
/// caller (typically toggling local @State for accordion unfold of the
/// card immediately below).
struct OrganizedChip: View {
    let pass: OrganizePass
    let isStale: Bool
    let canRefresh: Bool

    /// Variant selection — pulled into a pure enum + factory so the
    /// precedence logic is unit-testable without mounting the view.
    /// Public-internal so `@testable import` reaches it.
    enum Variant {
        case refreshStale     // stale + has assists
        case staleNoAssists   // stale + no assists
        case nextStepsCount   // has next steps, not stale
        case `default`        // post-dismiss with nothing to surface

        /// Resolves the variant for the three input bits. Tested
        /// directly in `PricingV5DecisionTests.chip_*`.
        static func resolve(isStale: Bool, canRefresh: Bool, nextStepsCount: Int) -> Variant {
            if isStale {
                return canRefresh ? .refreshStale : .staleNoAssists
            }
            if nextStepsCount > 0 {
                return .nextStepsCount
            }
            return .default
        }

        /// Renders the user-facing chip copy for a variant + count.
        /// `count` is only consulted for `.nextStepsCount`.
        func labelText(nextStepsCount: Int) -> String {
            switch self {
            case .refreshStale:    return "Organized · refresh"
            case .staleNoAssists:  return "Organized · stale"
            case .nextStepsCount:
                let n = nextStepsCount
                return "Organized · \(n) next step\(n == 1 ? "" : "s")"
            case .default:         return "Organized · review"
            }
        }
    }

    private var variant: Variant {
        Variant.resolve(
            isStale: isStale,
            canRefresh: canRefresh,
            nextStepsCount: pass.nextStepsItems.count
        )
    }

    private var labelText: String {
        variant.labelText(nextStepsCount: pass.nextStepsItems.count)
    }

    private var tint: Color {
        switch variant {
        // Stale variants keep warning amber — status signaling
        // (memory has changed since last organize), not AI
        // attribution. AI moments themselves wear blue (Crucible
        // 2026-05 sweep).
        case .refreshStale, .staleNoAssists: return Crucible.Color.warning
        case .nextStepsCount, .default:      return Crucible.Color.aiBlue
        }
    }

    private var tintBackground: Color {
        switch variant {
        case .refreshStale, .staleNoAssists: return Color(red: 0.96, green: 0.91, blue: 0.82)
        case .nextStepsCount, .default:      return Crucible.Color.aiBlueTint
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text(labelText)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.05)
            // chevron.down — "expands inline." `chevron.right` reads
            // as iOS navigation ("pushes to another screen"), which
            // is the wrong signal: tapping folds down in place. The
            // expanded chip-header uses `chevron.up`; they're the
            // same control in two states.
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
        }
        .foregroundStyle(tint)
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .padding(.vertical, 7)
        .background(tintBackground)
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch variant {
        case .refreshStale:    return "AI suggestions are stale, refresh available"
        case .staleNoAssists:  return "AI suggestions are stale, resets next period"
        case .nextStepsCount:  return "\(pass.nextStepsItems.count) next steps from AI"
        case .default:         return "AI suggestions, tap to review"
        }
    }
}
