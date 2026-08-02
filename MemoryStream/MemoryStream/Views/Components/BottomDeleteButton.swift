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
                // The label names what's destroyed (clips are the atoms,
                // everything else is association): a memory removes its derived
                // layer, its clips handled by the last-reference rule; a clip
                // destroys the atom across every memory. "Delete this Memory"
                // (not the old "Let Go" metaphor) — at the destructive moment a
                // metaphor reads as ambiguity about whether the thing survives;
                // the footnote below carries the nuance (locked Voice principle,
                // 2026-07-28). The disclosure line is what keeps "Delete" honest.
                switch noun {
                case "memory":  return "Delete this Memory"
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
                    // The footnote reassures that the parts survive — the
                    // disclosure line is what makes the literal "Delete this
                    // Memory" honest (locked Voice principle, 2026-07-28). The
                    // user-facing noun is "parts" (F7g); a delete-moment
                    // disclosure is the worst place for a vocabulary
                    // inconsistency (Tom 2026-07-28). Code identifiers stay clip.
                    return "The parts stay — they'll be available to start other memories. Moves to Recently Deleted · kept for 30 days."
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

    /// Builds the memory-deletion split-disclosure footnote (P8). `stayCount` =
    /// parts used elsewhere (edge count > 1); `moveCount` = parts only in this
    /// memory (single edge → move to Recently Deleted). Discloses, never asks.
    /// The user-facing noun is "parts" (F7g) — the worst place for a
    /// clip/parts inconsistency is a delete-moment disclosure (Tom 2026-07-28);
    /// the `letGo` identifier and `clip` code terms are unchanged.
    static func letGoFootnote(stayCount: Int, moveCount: Int) -> String {
        switch (stayCount, moveCount) {
        case (0, 0):
            return "Moves to Recently Deleted · kept for 30 days."
        case (let s, 0):
            let n = s == 1 ? "part is" : "parts are"
            return "The \(n) also used elsewhere and will stay."
        case (0, let m):
            let subj = m == 1 ? "1 part is" : "\(m) parts are"
            let verb = m == 1 ? "moves" : "move"
            return "\(subj) only here and \(verb) to Recently Deleted for 30 days."
        case (let s, let m):
            let stay = s == 1 ? "1 part is" : "\(s) parts are"
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
