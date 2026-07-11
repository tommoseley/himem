import SwiftUI

/// The single deletion affordance per `HiMem · Buttons & Actions.html` §3
/// and `Memory Detail · unified editing model.md` (June 12 2026):
/// destruction is a full-width red button at the **bottom of an opened
/// item**, below all its content. The scroll to reach it *is* the
/// deliberation — no confirm dialog, no swipe. Recently Deleted (30 days)
/// is the safety net.
///
/// Two variants share the same shape so the colour-code rule holds:
/// - `.delete(noun:)` — danger red, trash icon, "Moves to Recently
///   Deleted · kept for 30 days." Destroys the thing.
/// - `.removeFromProject` — same danger shape, recycle icon, "The memory
///   stays in your library." Unlinks; the thing survives.
///
/// Visual spec mirrors `.delbtn` in the canvas: 50pt min height, 14pt
/// corner, 1.5pt danger border on a transparent fill, 15.5pt semibold
/// label with -0.1 tracking, 9pt icon↔label gap, ink3 footnote 11.5pt
/// centered 8pt below.
struct BottomDeleteButton: View {

    enum Kind {
        case delete(noun: String) // "memory" / "clip" / "project" / "session"
        case removeFromProject

        var label: String {
            switch self {
            case .delete(let noun): return "Delete \(noun)"
            case .removeFromProject: return "Remove from project"
            }
        }

        var systemImage: String {
            switch self {
            case .delete:            return "trash"
            case .removeFromProject: return "arrow.triangle.2.circlepath"
            }
        }

        var footnote: String {
            switch self {
            case .delete:            return "Moves to Recently Deleted · kept for 30 days."
            case .removeFromProject: return "The memory stays in your library."
            }
        }
    }

    let kind: Kind
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 9) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 16, weight: .regular))
                    Text(kind.label)
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.1)
                }
                .foregroundStyle(Crucible.Color.danger)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Crucible.Color.danger, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind.label)

            Text(kind.footnote)
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    VStack(spacing: 28) {
        BottomDeleteButton(kind: .delete(noun: "memory"), action: {})
        BottomDeleteButton(kind: .delete(noun: "clip"), action: {})
        BottomDeleteButton(kind: .delete(noun: "project"), action: {})
        BottomDeleteButton(kind: .removeFromProject, action: {})
    }
    .padding()
    .background(Crucible.Color.paper)
}
