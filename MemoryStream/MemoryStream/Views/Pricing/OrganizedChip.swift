import SwiftUI

/// Review-state label for an `OrganizePass`. Two variants, per
/// `docs/design/pricing-screens-lifecycle.jsx` and `AI Organize · spec.md`
/// §2b/§9:
///
///   1. **Draft organized** — dashed AI-blue chip + sparkle icon.
///      Pass exists but the user hasn't reviewed it yet.
///      *"This is a first draft. Give it a glance."*
///   2. **Organized** — solid AI-blue chip + check icon. The user
///      has dismissed or accepted the review surface.
///
/// The chip tracks **review state, not tier** — a Plus auto-organize
/// pass also reads as "Draft organized" until the user engages with
/// it. Stale (memory has new clips since last organize) is **not** a
/// chip variant; it surfaces as a separate warning banner alongside.
///
/// Replaces the assist-quota chip variants (refreshStale,
/// staleNoAssists, nextStepsCount, default) retired in PR 8c.
struct OrganizedChip: View {
    let pass: OrganizePass

    enum Variant: Equatable {
        case draftOrganized
        case organized

        /// Pure factory — tested directly via `pass.isReviewed`.
        static func resolve(isReviewed: Bool) -> Variant {
            isReviewed ? .organized : .draftOrganized
        }

        var labelText: String {
            switch self {
            case .draftOrganized: return "Draft organized"
            case .organized:      return "Organized"
            }
        }

        var iconName: String {
            switch self {
            case .draftOrganized: return "sparkles"
            case .organized:      return "checkmark"
            }
        }

        /// Dashed border on draft; solid on organized. The dashed
        /// edge is the design's "this is not yet authoritative"
        /// signal — paired with the "Draft" label so the visual
        /// reinforces the copy.
        var isDashed: Bool { self == .draftOrganized }

        var accessibilityLabel: String {
            switch self {
            case .draftOrganized: return "Draft organized, tap to review"
            case .organized:      return "Organized"
            }
        }
    }

    private var variant: Variant {
        Variant.resolve(isReviewed: pass.isReviewed)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: variant.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(variant.labelText)
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.1)
        }
        .foregroundStyle(Crucible.Color.aiBlue)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Crucible.Color.aiBlueTint)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(
                    Crucible.Color.aiBlue,
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: variant.isDashed ? [3, 2] : []
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityLabel(variant.accessibilityLabel)
    }
}
