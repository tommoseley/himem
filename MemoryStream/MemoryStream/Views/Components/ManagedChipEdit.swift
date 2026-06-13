import SwiftUI

/// Inline, commit-on-exit chip editor — the "managed chip · edit state"
/// pattern from `docs/design/Memory Detail · unified editing model.md` §2.
///
/// **Rest** is a solid pill with a leading-dot color (`dotTint`) and the
/// `value` as its label — matches the existing mention chip visual.
/// **Edit** swaps the label for an inline `TextField` (ochre caret, user
/// action) and reveals a trailing **✕** *within* the chip. The ✕ has an
/// expanded hit zone via `contentShape` so it clears the 44pt touch floor
/// even though the visible glyph is smaller.
///
/// **Commit-on-exit, not Cancel/Done.** Tokens are trivially reversible
/// (re-tap to fix), so explicit Cancel / Done chrome doesn't belong here —
/// commit fires when the field loses focus or when another editor (any
/// other text-edit on the page, tracked via `TextEditCoordinator`) takes
/// the active id. Empty-commit removes the chip (matches the ✕ semantic).
///
/// Hosts pass three callbacks plus the chip's identity for coordinator
/// scoping. The component owns its own draft + focus + isEditing state —
/// hosts don't manage edit flips.
struct ManagedChipEdit: View {
    /// Stable id used to scope this chip's `TextEditCoordinator` entry —
    /// e.g. `"mention-<uuid>"`. Two chips with the same id would fight
    /// over `activeEditId`; the host guarantees uniqueness.
    let id: String
    let value: String
    let dotTint: Color
    let onCommitRename: (String) -> Void
    let onRemove: () -> Void

    @State private var isEditing: Bool = false
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var editCoordinator = TextEditCoordinator.shared

    var body: some View {
        Group {
            if isEditing {
                editingChip
            } else {
                restChip
            }
        }
        // Cross-editor commit (rule #6 — one edit at a time). If
        // another text editor takes the active id, commit before it
        // takes over. Mirrors the pattern on title / summary / clip
        // transcripts.
        .onChange(of: editCoordinator.activeEditId) { _, newId in
            if isEditing && newId != id {
                commit()
            }
        }
    }

    @ViewBuilder
    private var restChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotTint)
                .frame(width: 5, height: 5)
            Text(value)
        }
        .font(.system(size: 14))
        .fontWeight(.medium)
        .foregroundStyle(Crucible.Color.ink2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Crucible.Color.sunk)
        .clipShape(Capsule())
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .onTapGesture { begin() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value)
        .accessibilityHint("Double tap to rename or remove this mention")
    }

    @ViewBuilder
    private var editingChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotTint)
                .frame(width: 5, height: 5)
            TextField("", text: $draft)
                .font(.system(size: 14))
                .fontWeight(.medium)
                .foregroundStyle(Crucible.Color.ink)
                .tint(Crucible.Color.accent)
                .focused($fieldFocused)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { commit() }
                .frame(minWidth: 40)
                .fixedSize(horizontal: true, vertical: false)
            Button {
                onRemove()
                isEditing = false
                fieldFocused = false
                TextEditCoordinator.shared.end(id: id)
            } label: {
                // 44×44 tap frame meets the management-context floor
                // per CLAUDE.md and keeps the ✕ safely separated from
                // the live TextField (preventing fat-finger commits
                // on the wrong target). The visible glyph stays
                // compact via font size — it's the *tap zone* that
                // grows, not the ink.
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(value)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Crucible.Color.sunk)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Crucible.Color.accent, lineWidth: 1)
        )
        .frame(minHeight: 38)
    }

    private func begin() {
        draft = value
        isEditing = true
        TextEditCoordinator.shared.begin(id: id)
        DispatchQueue.main.async {
            fieldFocused = true
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = value.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        fieldFocused = false
        TextEditCoordinator.shared.end(id: id)
        if trimmed.isEmpty {
            onRemove()
        } else if trimmed != current {
            onCommitRename(trimmed)
        }
    }
}

/// Dashed "+ Add" affordance for adding a new mention chip. Same pattern
/// as the existing "+ Edit"/"+ Add" topic pill — tap to enter inline
/// edit, type a label, commit-on-exit creates the entity.
///
/// Empty commit cancels (no entity is created). The dashed border is
/// the Crucible "add / incomplete / provisional" signal per
/// `docs/design/CLAUDE.md`'s affordance vocabulary lock.
struct ManagedChipAddAffordance: View {
    let id: String
    let onCommit: (String) -> Void

    @State private var isEditing: Bool = false
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var editCoordinator = TextEditCoordinator.shared

    var body: some View {
        Group {
            if isEditing {
                editingChip
            } else {
                restChip
            }
        }
        .onChange(of: editCoordinator.activeEditId) { _, newId in
            if isEditing && newId != id {
                commit()
            }
        }
    }

    @ViewBuilder
    private var restChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
            Text("Add")
        }
        .font(.system(size: 14))
        .fontWeight(.medium)
        // Dashed-ochre = "add / provisional" per the affordance
        // vocabulary lock (CLAUDE.md, June 8 2026). Gray would read
        // as disabled — this is *the* signal the user can add a
        // mention here.
        .foregroundStyle(Crucible.Color.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            Capsule()
                .strokeBorder(
                    Crucible.Color.accent,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        )
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .onTapGesture { begin() }
        .accessibilityLabel("Add a mention")
        .accessibilityHint("Double tap to add a new mention to this memory")
    }

    @ViewBuilder
    private var editingChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Name", text: $draft)
                .font(.system(size: 14))
                .fontWeight(.medium)
                .foregroundStyle(Crucible.Color.ink)
                .tint(Crucible.Color.accent)
                .focused($fieldFocused)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { commit() }
                .frame(minWidth: 60)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            Capsule()
                .strokeBorder(
                    Crucible.Color.accent,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        )
        .frame(minHeight: 38)
    }

    private func begin() {
        draft = ""
        isEditing = true
        TextEditCoordinator.shared.begin(id: id)
        DispatchQueue.main.async {
            fieldFocused = true
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        isEditing = false
        fieldFocused = false
        TextEditCoordinator.shared.end(id: id)
        if !trimmed.isEmpty {
            onCommit(trimmed)
        }
    }
}
