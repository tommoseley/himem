import SwiftUI

/// Review-state **label** for an `OrganizePass`. Two variants:
///
///   1. **Draft organized** — sparkle icon + label. Pass exists but
///      the user hasn't reviewed it yet.
///   2. **Organized** — check icon + label. The user has dismissed
///      or accepted the review surface.
///
/// Per `docs/design/CLAUDE.md` (June 8 2026 lock — "one affordance
/// vocabulary, three signals"): **status is never dressed as a
/// button.** This chip is a quiet status label — icon + text, no
/// border, no pill, not tappable. The Memory-Detail "Draft organized"
/// cluster is the origin case for the rule: it previously shipped as
/// a dashed pill that collided with the dashed `+ Edit` button on
/// the topic row. Resolution: this label communicates state, and a
/// separate full-width primary button next to it (in
/// `OrganizeMemorySection`) carries the actual review action.
///
/// Dashed borders are reserved for *add / incomplete / provisional*
/// affordances (e.g. `+ Edit`, `NEW` topic chips) — never for
/// status. That's why the draft variant here is a label, not a
/// dashed pill.
///
/// The chip tracks **review state, not tier** — a Plus auto-organize
/// pass also reads as "Draft organized" until the user engages with
/// it. Stale (memory has new clips since last organize) is **not** a
/// chip variant; it surfaces as a separate warning banner alongside.
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

        var accessibilityLabel: String {
            switch self {
            case .draftOrganized: return "Draft organized"
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
                .font(.system(size: 11, weight: .semibold))
            Text(variant.labelText)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.1)
        }
        .foregroundStyle(Crucible.Color.aiBlue)
        .accessibilityLabel(variant.accessibilityLabel)
        // Intentionally NO background, NO border. Per the June 8
        // affordance-vocabulary lock, status is a quiet label —
        // never dressed to look tappable.
    }
}
