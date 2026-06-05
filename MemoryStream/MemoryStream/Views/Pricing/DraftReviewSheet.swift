import SwiftUI
import CoreData

/// B1 review sheet — replaces the assist-quota-era `AISuggestionsCard`
/// per `docs/design/pricing-screens-lifecycle.jsx` `ScrLifeReviewSheet`.
///
/// Surface:
///
///   • Header chip — "Draft organized" (the dashed `OrganizedChip`).
///   • Title — *"A draft from your device."*
///   • Body — *"Make sure it sounds like you. Keep it as is, or
///     edit anything that's a little off."*
///   • Two read-only field rows: title + summary, showing the
///     on-device draft.
///   • Primary action — *"Looks good"* — applies the title to the
///     entry (when the entry's own title is empty), marks all rows
///     accepted, sets `pass.dismissedAt`. The chip flips to
///     *"Organized"* on the next render.
///   • Secondary action — *"Edit"* — dismisses the sheet without
///     committing the draft title. The user can edit the memory's
///     title and summary via the standard detail edit mode.
///
/// Per `AI Organize · spec.md` §2b/§9: this sheet exists so the
/// on-device draft is never silently treated as authoritative — the
/// user signs off (or chooses to edit) before the chip reads
/// *"Organized"*.
struct DraftReviewSheet: View {
    let pass: OrganizePass
    let entry: JournalEntry
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header chip (provisional state — pass is unreviewed
            // when this sheet is up by construction).
            HStack {
                OrganizedChip(pass: pass)
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

            Text("A draft from your device.")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
                .padding(.top, 12)
                .padding(.horizontal, 20)

            Text("Make sure it sounds like you. Keep it as is, or edit anything that's a little off.")
                .font(.system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.horizontal, 20)

            // Drafted fields, read-only here. The "Edit" button below
            // sends the user back to the entry's normal edit mode for
            // any changes.
            VStack(spacing: 0) {
                if let title = pass.suggestedTitle, !title.isEmpty {
                    fieldRow(label: "Title", value: title, useSerif: true)
                    if pass.summaryText?.isEmpty == false {
                        Divider().background(Crucible.Color.divider)
                    }
                }
                if let summary = pass.summaryText, !summary.isEmpty {
                    fieldRow(label: "Summary", value: SummaryRenderer.renderForOwner(summary), useSerif: false)
                }
            }
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 16)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 8) {
                Button(action: commitLooksGood) {
                    Text("Looks good")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Edit")
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
            .padding(.bottom, 20)
        }
        .background(Crucible.Color.paper)
    }

    @ViewBuilder
    private func fieldRow(label: String, value: String, useSerif: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.aiBlue)
            Text(value)
                .font(useSerif
                      ? .system(size: 14, design: .serif)
                      : .system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Applies the draft to the entry: title if the entry hasn't
    /// got its own, then marks the pass reviewed (dismissedAt +
    /// every row accepted). The chip flips to "Organized" on next
    /// render via `pass.isReviewed`.
    private func commitLooksGood() {
        let ctx = pass.managedObjectContext ?? StorageService.shared.viewContext
        ctx.performAndWait {
            let existing = entry.title ?? ""
            if existing.isEmpty, let suggested = pass.suggestedTitle, !suggested.isEmpty {
                entry.title = suggested
                entry.titleSourcedFromAI = true
            }
            pass.markRowsAccepted([.title, .summary, .topics, .mentions])
            pass.dismissedAt = Date()
            try? ctx.save()
        }
        onDismiss()
    }
}
