import SwiftUI

/// Bottom-aligned undo toast — appears after the user recycles an
/// entry from `JournalView`; tapping Undo restores it via the view
/// model. Extracted from `JournalView.body` in the CRAP audit
/// 2026-05-28 (Batch 1) so the host body shrinks and the toast can
/// gain auto-dismiss or queue semantics independently.
struct JournalUndoToast: View {
    @Binding var isShown: Bool
    let undoEntry: EntryDisplayModel?
    let viewModel: JournalViewModel

    var body: some View {
        if isShown, let entry = undoEntry {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Text("Moved to Recently Deleted")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        viewModel.restoreEntry(entryId: entry.id)
                        withAnimation { isShown = false }
                    } label: {
                        Text("Undo")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Crucible.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Crucible.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
