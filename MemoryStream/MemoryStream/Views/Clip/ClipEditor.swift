import SwiftUI

// MARK: - Field enum (owns copy, drives eyebrow + a11y verb)

/// Which field of a `ClipDisplayModel` the `ClipEditor` is editing.
/// Enum-with-metadata keeps the eyebrow copy + a11y verb load-bearing
/// on the type — callers can't drift the label by passing a stringly-
/// typed value.
///
/// The two cases are the only two the Clip Model spec allows:
/// **transcript** edits a voice/note clip's words; **description**
/// edits a photo/video clip's words. Both are "the clip's words" —
/// the same act on the same slot — so they route through the same
/// component per `Clip model · spec.md` §Shared components (July 11
/// 2026).
enum ClipEditorField: Equatable {
    case transcript
    case description

    /// Sticky eyebrow above the editing field. Small caps, letter-
    /// spaced 1.3 (Crucible token in the view).
    var eyebrow: String {
        switch self {
        case .transcript: return "TRANSCRIPT"
        case .description: return "DESCRIPTION"
        }
    }

    /// VoiceOver commit-button label. `"Save transcript"` /
    /// `"Save description"` — the noun matches the field so VoiceOver
    /// users hear the actual outcome instead of a generic "Save".
    var accessibilityCommitAction: String {
        switch self {
        case .transcript: return "Save transcript"
        case .description: return "Save description"
        }
    }

    /// Whether committing an empty (trimmed) value is a legitimate change
    /// rather than an accidental wipe. **Descriptions** are a derived,
    /// optional layer — clearing one back to "no description" is a real,
    /// reversible edit and MUST persist. **Transcripts** (spoken words /
    /// note text) are the clip's substance: an inline edit never blanks
    /// them (removal is "Delete this Clip"), so empty stays guarded.
    var allowsEmptyCommit: Bool {
        switch self {
        case .description: return true
        case .transcript:  return false
        }
    }
}

// MARK: - Pure commit decision

/// The result of comparing an in-flight `draft` against the
/// `initial` value when the user taps Done or the editor closes.
/// Extracted as a pure function so the "skip on no-op / whitespace-
/// only diff / trim on commit" contract is tested at value-level
/// (no SwiftUI runtime), and the view stays a thin wrapper around
/// this decision.
enum ClipEditorCommitDecision: Equatable {

    /// The draft has a real change — commit with the trimmed value.
    /// Trimming removes leading/trailing whitespace *and newlines*
    /// (both editors historically emitted trailing newlines from the
    /// multiline TextField).
    case commit(trimmed: String)

    /// The draft has no meaningful change (identical after trimming
    /// both sides). No commit fires; the caller closes silently.
    case skip

    /// Compare an initial value against an in-flight draft. Both
    /// sides are trimmed before comparison so whitespace-only edits
    /// count as "no change" — matches the shipped behavior of
    /// `PhotoDescriptionEditSheet` and `VoiceClipPanel`'s inline
    /// commit path, consolidated here.
    static func decide(initial: String, draft: String, field: ClipEditorField) -> ClipEditorCommitDecision {
        let trimmedInitial = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInitial == trimmedDraft { return .skip }
        // Wipe guard (P0 2026-07-16) — **field-scoped** (2026-07-22): an
        // inline edit never blanks a non-empty *transcript* to empty
        // (that's the transcript-wipe bug — removing a clip's substance is
        // "Delete this Clip", not an edit-to-blank). A **description** is a
        // derived, optional layer, so clearing it IS a real edit and must
        // persist (`field.allowsEmptyCommit`). One gate, field-aware.
        if trimmedDraft.isEmpty && !field.allowsEmptyCommit { return .skip }
        return .commit(trimmed: trimmedDraft)
    }
}

// MARK: - Coordinator-switch outcome

/// What the editor should do when `TextEditCoordinator.activeEditId`
/// changes to a value that isn't ours. Encodes the rule #6
/// invariant of `Memory Detail · unified editing model.md`: another
/// editor stealing focus while our draft has unsaved changes must
/// **commit** ours (never lose the user's work), never `.cancel`.
///
/// Extracted as pure logic so the invariant is testable at value-
/// level without a SwiftUI runtime.
enum ClipEditorSwitchOutcome: Equatable {

    /// Draft has changes — commit them, then close.
    case commitAndClose(trimmed: String)

    /// Draft has no changes — close silently.
    case cancelAndClose

    /// The `activeEditId` change was to our own id (or to `nil`
    /// during a legitimate end) — stay open.
    case stayEditing

    /// - Parameter switchedToOtherEditor: `true` when the
    ///   coordinator's new `activeEditId` is neither ours nor nil
    ///   (i.e., another editor's id). The caller resolves this via
    ///   `newId != editId && newId != nil`.
    static func decide(
        initial: String,
        draft: String,
        field: ClipEditorField,
        switchedToOtherEditor: Bool
    ) -> ClipEditorSwitchOutcome {
        guard switchedToOtherEditor else { return .stayEditing }
        switch ClipEditorCommitDecision.decide(initial: initial, draft: draft, field: field) {
        case .commit(let trimmed): return .commitAndClose(trimmed: trimmed)
        case .skip: return .cancelAndClose
        }
    }
}

// MARK: - Fate row model (presence-of-callback governs visibility)

/// The value passed to the editor's fate row: mandatory `onDelete`
/// (every clip can be deleted from its editor per the spec §
/// destruction rule) + optional `onRelocate` (`Move to…` only shows
/// when a relocation destination is meaningful — inside a memory
/// with siblings, not on a standalone Clip Detail).
///
/// The spec's `showMove` prop maps to Swift's
/// presence-of-callback idiom the codebase already uses everywhere
/// (`onCommitTranscript: ((String) -> Void)?`) — one less bool
/// param, one less place to drift.
struct ClipEditorFateActions {
    let onDelete: () -> Void
    let onRelocate: (() -> Void)?

    /// Non-destructive ejection from the surrounding collection
    /// (locked July 12 2026, spec § "Clip triage — operational
    /// fate actions"). A session clip's Remove sends it back to the
    /// bench as a loose clip; a memory clip's Remove strips its
    /// edge to that memory while the clip itself survives. Parallel
    /// of "Remove from project" for memories. Optional — a
    /// standalone Clip Detail (no collection above it) leaves it
    /// nil and the tier disappears.
    var onRemoveFromCollection: (() -> Void)? = nil

    /// Label for the Remove tier — context-driven per spec:
    /// `"Remove from session"` on a session's clip, `"Remove from
    /// memory"` on a memory's clip. Nil = the tier doesn't render
    /// even if `onRemoveFromCollection` is provided.
    var removeFromCollectionLabel: String? = nil

    /// `true` when a `Move to…` button should render.
    var showsMove: Bool { onRelocate != nil }

    /// `true` when the neutral Remove tier should render — both
    /// the callback and the label must be present.
    var showsRemoveFromCollection: Bool {
        onRemoveFromCollection != nil && removeFromCollectionLabel != nil
    }
}

// MARK: - The view (inline editor)

/// The one clip editor per Slice 2. Inline (not a sheet — see
/// `Memory Detail · unified editing model.md` rules 1–8 for why),
/// participates in `TextEditCoordinator.shared` so the "one edit at
/// a time" invariant is enforced *inside* the component, not per-
/// callsite. Consumers in Slices 7 / 9 swap the atom's read view
/// for this editor when the user taps to edit.
///
/// The view is deliberately a thin wrapper around
/// `ClipEditorCommitDecision` + `ClipEditorSwitchOutcome` + the
/// `ClipEditorFateActions` presence idiom — all four of R3's money
/// tests exercise pure logic so the component's contract is locked
/// at value-level.
struct ClipEditor: View {

    let field: ClipEditorField
    @Binding var draft: String

    /// The last-persisted value. Used to compute the commit
    /// decision on Done / auto-commit-on-switch.
    let initialValue: String

    /// Opaque id for `TextEditCoordinator` — caller supplies a
    /// stable, meaningful id (e.g., `"transcript-\(uuid)"`).
    let editId: String

    /// Media evidence kept visible while editing per spec § "media
    /// evidence kept visible during edit." `.none` for note and
    /// photo (nothing to render); voice/video render a compact
    /// evidence row below the field.
    let evidence: ClipDisplayModel.Evidence?

    /// Fate actions — delete required, relocate optional.
    let fateActions: ClipEditorFateActions

    /// When `false`, the eyebrow section label (`TRANSCRIPT` /
    /// `DESCRIPTION`) is suppressed — for surfaces whose screen
    /// chrome already carries the same label a step up (Clip Detail).
    /// Locked July 12 2026 (`Clip model · spec.md` §Clip triage):
    /// "The editor also must not repeat the `TRANSCRIPT` section
    /// label the screen already shows."
    var showLabel: Bool = true

    /// When `false`, the fate-action row (Remove / Move / Delete) is
    /// dropped entirely — for surfaces whose view mode already owns
    /// those actions in a bottom fate stack (Clip Detail). Locked
    /// July 12 2026: "editing words is not a moment to delete or
    /// eject — so those never appear here, which is why Delete clip
    /// must never render twice." The default (`true`) preserves the
    /// pre-July-12 behaviour for every existing memory-detail
    /// call-site.
    var showFates: Bool = true

    let onCancel: () -> Void
    let onDone: (String) -> Void

    @ObservedObject private var coordinator = TextEditCoordinator.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showLabel {
                eyebrowLabel
            }
            editField
            if let evidence {
                evidenceRow(evidence)
                    .opacity(0.7)
            }
            if showFates {
                fateRow
            }
            commitBar
        }
        .padding(.vertical, 6)
        .onAppear {
            coordinator.begin(id: editId)
            focused = true
        }
        .onDisappear {
            coordinator.end(id: editId)
        }
        .onChange(of: coordinator.activeEditId) { _, newId in
            handleCoordinatorChange(newId: newId)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                coordinator.begin(id: editId)
            }
        }
    }

    // MARK: Subviews

    private var eyebrowLabel: some View {
        Text(field.eyebrow)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(Crucible.Color.ink3)
    }

    private var editField: some View {
        TextField("", text: $draft, axis: .vertical)
            .font(.system(size: 15))
            .lineSpacing(2)
            .foregroundStyle(Crucible.Color.ink)
            .focused($focused)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(false)
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: ClipDisplayModel.Evidence) -> some View {
        switch evidence {
        case .audio(let duration):
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Crucible.Color.accent)
                Text(evidenceLabel(prefix: "Original recording", duration: duration))
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        case .video(let duration):
            HStack(spacing: 6) {
                Image(systemName: "video.circle.fill")
                    .foregroundStyle(Crucible.Color.accent)
                Text(evidenceLabel(prefix: "Video", duration: duration))
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private func evidenceLabel(prefix: String, duration: TimeInterval?) -> String {
        guard let duration else { return prefix }
        let total = Int(duration)
        return "\(prefix) · \(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Fate row per spec § "Clip triage" (locked July 12 2026): the
    /// tiers stack top-to-bottom by escalating consequence — Remove
    /// (neutral, if wired) → Move (blue, if wired) → Delete (red,
    /// always, bottom-most). Was a single horizontal row with Delete
    /// beside Move; the spec is explicit that Delete is bottom-most
    /// and Remove sits above Move to keep the eye escalating.
    private var fateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fateActions.showsRemoveFromCollection,
               let onRemove = fateActions.onRemoveFromCollection,
               let removeLabel = fateActions.removeFromCollectionLabel {
                Button(action: onRemove) {
                    Label(removeLabel, systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Crucible.Color.ink2)
            }
            if let onRelocate = fateActions.onRelocate {
                Button(action: onRelocate) {
                    Label("Move to…", systemImage: "arrow.up.forward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Crucible.Color.aiBlue)
            }
            Button(role: .destructive, action: fateActions.onDelete) {
                Label("Delete this Clip", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Crucible.Color.danger)
        }
    }

    private var commitBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .foregroundStyle(Crucible.Color.ink2)
            Spacer()
            Button("Done", action: handleDoneTap)
                .foregroundStyle(Crucible.Color.accent)
                .fontWeight(.semibold)
                .accessibilityLabel(field.accessibilityCommitAction)
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func handleDoneTap() {
        switch ClipEditorCommitDecision.decide(initial: initialValue, draft: draft, field: field) {
        case .commit(let trimmed):
            onDone(trimmed)
        case .skip:
            onCancel()
        }
    }

    private func handleCoordinatorChange(newId: String?) {
        let switched = (newId != nil && newId != editId)
        switch ClipEditorSwitchOutcome.decide(
            initial: initialValue,
            draft: draft,
            field: field,
            switchedToOtherEditor: switched
        ) {
        case .commitAndClose(let trimmed):
            onDone(trimmed)
        case .cancelAndClose:
            onCancel()
        case .stayEditing:
            break
        }
    }
}
