import SwiftUI

/// Reusable Cancel · ✓ Done bar that anchors **directly below** an
/// in-place text editor (title, summary, or clip transcript). Per
/// `docs/design/Memory Detail · unified editing model.md` §"Committing
/// an edit (accept / cancel) — by weight" (Tom 2026-06-09):
///
/// - The bar is a **real row in flow** — it reserves its own height and
///   pushes siblings down. **Never** a floating layer over the next
///   clip (that was the June-9 build bug the spec calls out by name).
/// - **Cancel** is plain ink — no border, no pill. Cancelling an edit
///   destroys nothing, so red is wrong (red = destruction, swipe-only).
/// - **Done** is an ochre pill with a leading check glyph. Ochre = the
///   "you act" color; green is reserved for confirmed-status.
/// - Both targets clear the 44pt hit-target floor (the visible bar is
///   40pt tall, but `frame(minHeight: 44)` on each button overrides).
struct EditCommitBar: View {
    let onCancel: () -> Void
    let onDone: () -> Void
    var doneLabel: String = "Done"
    /// Optional left-aligned `Delete clip` affordance per
    /// `Memory Detail · unified editing model.md` §"Interaction with
    /// the Full ⇄ Compact transcript toggle" (June 12 2026): a clip
    /// has no Delete in its view state — destruction surfaces only
    /// while editing the transcript, as a red text+icon on the left
    /// of this bar. Pass `nil` for title/summary/project edits where
    /// no clip is being acted on.
    var onDelete: (() -> Void)? = nil
    var deleteLabel: String = "Delete clip"

    var body: some View {
        HStack(spacing: 14) {
            if let onDelete {
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                        Text(deleteLabel)
                            .font(.system(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(Crucible.Color.danger)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Crucible.Color.danger, lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(deleteLabel)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink2)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel edit")

            Button(action: onDone) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(doneLabel)
                        .font(.system(size: 14.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel("Commit edit")
        }
        .padding(.top, 2)
    }
}
