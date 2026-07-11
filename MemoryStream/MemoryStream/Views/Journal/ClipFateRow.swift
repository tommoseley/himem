import SwiftUI

/// Two-button "clip fate" row that sits **above** the text commit row
/// (`EditCommitBar`) in a clip transcript's edit state, per
/// `Memory Detail · unified editing model.md:66` (locked July 5 2026):
///
/// > "the edit-state bottom is two rows: a clip-fate management row
/// > — Delete clip (destroy) and Where does this belong? (relocate/
/// > remove) — above the text commit row (Cancel / Done). Four
/// > actions never share one line (44px floor)."
///
/// - **Delete clip** always destroys (→ Recently Deleted).
/// - **Where does this belong?** opens the placement sheet with three
///   destinations: move to another memory, into a new memory, or
///   remove from this memory (clip returns to the Clips bench).
///
/// Both buttons clear the 44pt hit-target floor. Colours follow the
/// buttons lock — danger red border for destruction, ochre border for
/// user action.
struct ClipFateRow: View {
    let onDelete: () -> Void
    let onRelocate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            deleteButton
            Spacer(minLength: 0)
            relocateButton
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text("Delete clip")
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
        .accessibilityLabel("Delete clip")
    }

    private var relocateButton: some View {
        Button(action: onRelocate) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                Text("Where does this belong?")
                    .font(.system(size: 14.5, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Crucible.Color.accent, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Where does this belong?")
    }
}
