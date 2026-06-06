import SwiftUI
import CoreData

/// The post-Reorganize review surface per
/// `docs/design/pricing-screens-lifecycle.jsx` `ScrLifeReorganizeSheet`
/// and `AI Organize · spec.md` §8.0 (June 6 2026).
///
/// Two stacked-pair rows (Title, Summary) — each defaults to the
/// **current** value (2px ochre border, check, *"Current · kept"*).
/// The new AI suggestion sits below in AI-blue chrome (hollow ring,
/// *"New suggestion · tap to use"*); tapping it opts that field into
/// the new wording. Nothing changes silently — even fields the user
/// never hand-edited require explicit consent.
///
/// Topics and mentions are intentionally absent — reorganize scope is
/// title + summary only; the fact fields are user-managed.
///
/// Footer:
///   • **Keep this version** — primary; commits the per-field choices.
///   • **Reorganize again** — secondary; regenerates a fresh pass.
///     Per spec: the per-field selections reset; "try again" means try
///     again, not "give me a hybrid."
///
/// This sheet handles only the per-field state and the buttons. The
/// commit (writing the chosen values back to the entry and the
/// `OrganizePass`) and the regenerate (firing another
/// `ProcessingEngine.processReorganize`) are delegated to the parent
/// via callbacks.
struct ReorganizeReviewSheet: View {
    let currentTitle: String
    let newTitle: String
    let currentSummary: String
    let newSummary: String
    var onKeep: (_ titleChoice: ReorgFieldChoice, _ summaryChoice: ReorgFieldChoice) -> Void
    var onReorganizeAgain: () -> Void
    var onDismiss: () -> Void

    @State private var titleChoice: ReorgFieldChoice = .current
    @State private var summaryChoice: ReorgFieldChoice = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("A fresh take.")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(.top, 12)

                    Text("Reorganize rethinks the title and summary. Keep what you have, or adopt the new wording — your call on each.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ReorgFieldRow(
                            label: "TITLE",
                            current: currentTitle,
                            newSuggestion: newTitle,
                            valueIsSerif: true,
                            isFirst: true,
                            choice: $titleChoice
                        )
                        Divider()
                            .background(Crucible.Color.divider)
                        ReorgFieldRow(
                            label: "SUMMARY",
                            current: currentSummary,
                            newSuggestion: newSummary,
                            valueIsSerif: false,
                            isFirst: false,
                            choice: $summaryChoice
                        )
                    }
                    .background(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
            }

            footer
        }
        .background(Crucible.Color.paper)
    }

    // MARK: - Header (chip + close)

    @ViewBuilder
    private var header: some View {
        HStack {
            DraftChipBadge()
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(8)
            }
            .accessibilityLabel("Close")
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                onKeep(titleChoice, summaryChoice)
            } label: {
                Text("Keep this version")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Crucible.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                // Reset per-field state so the next sheet open starts
                // fresh — per spec, "try again means try again, not
                // give me a hybrid."
                titleChoice = .current
                summaryChoice = .current
                onReorganizeAgain()
            } label: {
                Text("Reorganize again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

// MARK: - ReorgFieldRow

/// Per-field stacked-pair pattern: Current on top (selected by
/// default), New suggestion below (opt-in). Tap a card to make that
/// the field's choice.
struct ReorgFieldRow: View {
    let label: String
    let current: String
    let newSuggestion: String
    let valueIsSerif: Bool
    let isFirst: Bool
    @Binding var choice: ReorgFieldChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink2)
                .padding(.bottom, 8)

            Button {
                choice = .current
            } label: {
                card(
                    isSelected: choice == .current,
                    selectedAccent: Crucible.Color.accent,
                    unselectedAccent: Crucible.Color.ink3,
                    selectedLabel: "Current · kept",
                    unselectedLabel: "Current · tap to keep",
                    value: current
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 7)

            Button {
                choice = .new
            } label: {
                card(
                    isSelected: choice == .new,
                    selectedAccent: Crucible.Color.accent,
                    unselectedAccent: Crucible.Color.aiBlue,
                    selectedLabel: "New suggestion · kept",
                    unselectedLabel: "New suggestion · tap to use",
                    value: newSuggestion
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func card(
        isSelected: Bool,
        selectedAccent: Color,
        unselectedAccent: Color,
        selectedLabel: String,
        unselectedLabel: String,
        value: String
    ) -> some View {
        let borderColor = isSelected ? selectedAccent : Crucible.Color.hairline
        let borderWidth: CGFloat = isSelected ? 2 : 1
        let labelColor = isSelected ? selectedAccent : unselectedAccent

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                        .frame(width: 11, height: 11)
                } else {
                    Circle()
                        .strokeBorder(unselectedAccent, lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                }
                Text(isSelected ? selectedLabel : unselectedLabel)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(labelColor)
            }
            Text(value)
                .font(valueIsSerif
                      ? .system(size: 12.5, design: .serif)
                      : .system(size: 12.5))
                .foregroundStyle(isSelected ? Crucible.Color.ink : Crucible.Color.ink2)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Helpers

/// Per-field choice on the Reorganize sheet — either keep the current
/// value or opt into the AI's new suggestion. Default `.current` per
/// spec: nothing changes without explicit consent.
enum ReorgFieldChoice: Equatable {
    case current
    case new
}

/// The "Draft organized" chip rendered standalone (without an
/// `OrganizePass`) so the Reorganize sheet's header can show it
/// directly. Visual matches `OrganizedChip` for `Variant.draftOrganized`.
private struct DraftChipBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text("Draft organized")
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
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityLabel("Draft organized")
    }
}

#Preview {
    ReorganizeReviewSheet(
        currentTitle: "On integrity and moral courage",
        newTitle: "Integrity, and standing by what's right",
        currentSummary: "A reminder to myself: do the right thing even when it costs me. Stand with people only while they stand right.",
        newSummary: "You return to a standard you hold yourself to — staying true to what is right over what merely succeeds.",
        onKeep: { _, _ in },
        onReorganizeAgain: { },
        onDismiss: { }
    )
}
