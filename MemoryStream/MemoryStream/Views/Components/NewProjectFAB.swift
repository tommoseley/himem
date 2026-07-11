import SwiftUI
import UIKit

/// Projects-tab (list level) variant of the tab-shell FAB. Same
/// closed-state appearance as `AppendFAB` (ochre 60pt circle with a
/// centered `+`), same positioning, but the tap opens the New Project
/// sheet directly — no modality-picker stack.
///
/// Rationale per `CLAUDE.md:142` (July 10 2026 context-aware-FAB
/// lock): the Projects-list + is the one place + is *not* capturing a
/// thought. It creates an empty container (name + goal). Forcing it
/// through the voice/photo/note picker would misrepresent the
/// action; showing an ad-hoc modality picker on Projects list would
/// contradict the generalizing rule "+ creates one of whatever
/// you're looking at a collection of."
struct NewProjectFAB: View {
    let onTap: () -> Void

    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false

    private var alignment: Alignment {
        fabHandednessLeft ? .bottomLeading : .bottomTrailing
    }
    private var anchorPaddingEdge: Edge.Set {
        fabHandednessLeft ? .leading : .trailing
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(Crucible.Color.accent)
                        .frame(width: 60, height: 60)
                        .shadow(color: Crucible.Color.accent.opacity(0.32), radius: 16, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New project")
            .accessibilityHint("Creates a new project with a name and goal.")
            .padding(anchorPaddingEdge, 22)
            .padding(.bottom, 28)
        }
    }
}
