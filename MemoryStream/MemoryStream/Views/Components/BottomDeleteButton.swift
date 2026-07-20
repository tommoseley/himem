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
        case removeFromProject(name: String?) // names the project (F2/F3)

        var label: String {
            switch self {
            case .delete(let noun):
                // July 13 2026 lock — the label names what's destroyed
                // (clips are the atoms, everything else is association):
                // a memory dissolves its derived layer but its clips SURVIVE;
                // a clip destroys the atom across every memory.
                switch noun {
                case "memory":  return "Let Go of this Memory"
                case "clip":    return "Delete this Clip"
                case "project": return "Delete Project"   // title-case, spec §Deleting
                default:        return "Delete \(noun)"   // session
                }
            case .removeFromProject(let name):
                // F2/F3 (2026-07-17): name the project so it's unambiguous
                // which container the memory leaves.
                if let name, !name.isEmpty { return "Remove from \(name)" }
                return "Remove from Project"
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
            case .delete(let noun):
                if noun == "memory" {
                    // July 13 lock: "Let Go" must reassure that the clips
                    // survive — the spec's exact wording (unified editing
                    // model). This is what makes "Let Go" honest vs "Delete".
                    return "The clips stay — they'll be available to start other memories. Moves to Recently Deleted · kept for 30 days."
                }
                if noun == "project" {
                    // Projects · MVP spec §Deleting: deleting the container
                    // never deletes the memories it connected — say so.
                    return "The memories stay in your library. Moves to Recently Deleted · kept for 30 days."
                }
                return "Moves to Recently Deleted · kept for 30 days."
            case .removeFromProject: return "The memory stays in your library."
            }
        }
    }

    let kind: Kind
    /// P8 (July 19 2026): the memory "Let Go" footnote **discloses the
    /// last-reference split** ("N clips are also used elsewhere and will
    /// stay · M are only here and move to Recently Deleted for 30 days"),
    /// computed per-memory at open time. When set, it replaces the static
    /// `kind.footnote`. This is informational disclosure, NOT a confirm
    /// dialog — the deletion rule keeps the open-and-scroll-to-Delete model
    /// (no dialog); the footnote just tells the truth about the clips.
    var footnoteOverride: String? = nil
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

            Text(footnoteOverride ?? kind.footnote)
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
        }
    }

    /// Builds the Let Go split-disclosure footnote (P8). `stayCount` = clips
    /// used elsewhere (edge count > 1); `moveCount` = clips only in this
    /// memory (single edge → move to Recently Deleted). Discloses, never
    /// asks. If nothing moves, it says only that the clips stay; if there
    /// are no clips at all, it falls back to the memory's own 30-day net.
    static func letGoFootnote(stayCount: Int, moveCount: Int) -> String {
        switch (stayCount, moveCount) {
        case (0, 0):
            return "Moves to Recently Deleted · kept for 30 days."
        case (let s, 0):
            let n = s == 1 ? "clip is" : "clips are"
            return "The \(n) also used elsewhere and will stay."
        case (0, let m):
            let subj = m == 1 ? "1 clip is" : "\(m) clips are"
            let verb = m == 1 ? "moves" : "move"
            return "\(subj) only here and \(verb) to Recently Deleted for 30 days."
        case (let s, let m):
            let stay = s == 1 ? "1 clip is" : "\(s) clips are"
            let moveVerb = m == 1 ? "moves" : "move"
            return "\(stay) also used elsewhere and will stay · \(m) \(m == 1 ? "is" : "are") only here and \(moveVerb) to Recently Deleted for 30 days."
        }
    }
}

#Preview {
    VStack(spacing: 28) {
        BottomDeleteButton(kind: .delete(noun: "memory"), action: {})
        BottomDeleteButton(kind: .delete(noun: "clip"), action: {})
        BottomDeleteButton(kind: .delete(noun: "project"), action: {})
        BottomDeleteButton(kind: .removeFromProject(name: "Kingfisher"), action: {})
    }
    .padding()
    .background(Crucible.Color.paper)
}
