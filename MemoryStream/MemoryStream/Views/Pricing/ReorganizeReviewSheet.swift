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
/// Observable backing for the reorganize review sheet so "Reorganize again"
/// can swap a freshly-generated pass into the SAME presented sheet — the sheet
/// stays up, shows a working state, then re-renders the new comparison in
/// place. This replaces the old dismiss-then-re-present dance, which raced the
/// dismiss animation against the present and left the sheet closed (2026-07-24).
@MainActor
final class ReorganizeReviewModel: ObservableObject {
    @Published var currentTitle: String
    @Published var newTitle: String
    @Published var currentSummary: String
    @Published var newSummary: String
    /// True while a re-run is in flight. The sheet dims the comparison and
    /// shows "Working…"; the buttons disable. Flips false when the fresh pass
    /// lands via `applyFreshPass`.
    @Published var isWorking: Bool = false

    init(currentTitle: String, newTitle: String, currentSummary: String, newSummary: String) {
        self.currentTitle = currentTitle
        self.newTitle = newTitle
        self.currentSummary = currentSummary
        self.newSummary = newSummary
    }

    /// Swap the new AI suggestion in place after a "Reorganize again" pass.
    /// The Current column is untouched — the user hasn't kept anything yet.
    func applyFreshPass(newTitle: String, newSummary: String) {
        self.newTitle = newTitle
        self.newSummary = newSummary
        self.isWorking = false
    }
}

struct ReorganizeReviewSheet: View {
    @ObservedObject var model: ReorganizeReviewModel
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
                            current: model.currentTitle,
                            newSuggestion: model.newTitle,
                            valueIsSerif: true,
                            isFirst: true,
                            choice: $titleChoice
                        )
                        Divider()
                            .background(Crucible.Color.divider)
                        ReorgFieldRow(
                            label: "SUMMARY",
                            current: model.currentSummary,
                            newSuggestion: model.newSummary,
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
                    // While a re-run is in flight the stale comparison dims and
                    // a working indicator sits over it — the sheet never leaves.
                    .opacity(model.isWorking ? 0.35 : 1)
                    .overlay {
                        if model.isWorking {
                            HStack(spacing: 8) {
                                ProgressView().tint(Crucible.Color.aiBlue)
                                Text("Reorganizing…")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Crucible.Color.aiBlue)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.isWorking)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
            }

            footer
        }
        .background(Crucible.Color.paper)
        // A fresh pass landed → reset the per-field choices ("try again means
        // try again, not a hybrid") so the new suggestion starts unselected.
        .onChange(of: model.newSummary) { _, _ in
            titleChoice = .current
            summaryChoice = .current
        }
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
                // Rank-1 primary per Buttons & Actions: filled
                // ochre, full-width, ≥50pt. User commit ("Keep") =
                // ochre, no sparkle. No "with AI" suffix because
                // the user is the one doing the keeping.
                Text("Keep this version")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Crucible.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
            .opacity(model.isWorking ? 0.5 : 1)

            Button {
                onReorganizeAgain()
            } label: {
                // Rank-2 secondary per Buttons & Actions: hairline
                // bordered, no fill, full-width, same height as
                // primary (≥50pt). Trailing sparkle marks this as an
                // AI-invoking action; the verb "Reorganize again"
                // carries the meaning. While working it shows a spinner
                // and the sheet keeps its place — no dismiss.
                HStack(spacing: 7) {
                    if model.isWorking {
                        ProgressView().tint(Crucible.Color.ink2)
                        Text("Reorganizing…")
                            .font(.system(size: 15.5, weight: .semibold))
                    } else {
                        Text("Reorganize again")
                            .font(.system(size: 15.5, weight: .semibold))
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(Crucible.Color.ink2)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
                // F17 · the pill is stroked, not filled — without this the tap
                // region is only the drawn text. Guarded by ButtonHitRegionTests.
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
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
        // Per Crucible accessibility rule (June 8 lock): **selection
        // = ring; completion = check; don't conflate.** The old card
        // mixed both signals — a check inside the eyebrow plus a
        // colored border. New shape: selection is the ochre 1.5pt
        // ring around the whole card; eyebrow text + color carries
        // the human-readable status; no check, no leading circle.
        // The AI-blue eyebrow on the unselected "New suggestion" row
        // stays — it's an AI status signal, the row is still an AI
        // artifact even when not selected.
        let borderColor = isSelected ? selectedAccent : Crucible.Color.hairline
        let borderWidth: CGFloat = isSelected ? 1.5 : 1
        let labelColor = isSelected ? selectedAccent : unselectedAccent

        VStack(alignment: .leading, spacing: 3) {
            Text(isSelected ? selectedLabel : unselectedLabel)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(labelColor)
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

/// "Draft organized" header label for the Reorganize sheet. Per
/// `HiMem · Buttons & Actions` Section 4: AI status is a quiet
/// label — sparkle + text, **no border, no pill**. The dashed
/// pill form this lived as before the June 8 lock dressed status
/// as a button, which the standard explicitly retires.
private struct DraftChipBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Draft organized")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.1)
        }
        .foregroundStyle(Crucible.Color.aiBlue)
        .accessibilityLabel("Draft organized")
    }
}

#Preview {
    ReorganizeReviewSheet(
        model: ReorganizeReviewModel(
            currentTitle: "On integrity and moral courage",
            newTitle: "Integrity, and standing by what's right",
            currentSummary: "A reminder to myself: do the right thing even when it costs me. Stand with people only while they stand right.",
            newSummary: "You return to a standard you hold yourself to — staying true to what is right over what merely succeeds."
        ),
        onKeep: { _, _ in },
        onReorganizeAgain: { },
        onDismiss: { }
    )
}
