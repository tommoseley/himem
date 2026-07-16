import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClipEditor` — Slice 2 of the Clip Model
/// convergence (`docs/architecture/2026-07-11-clip-model-convergence-
/// plan.md`). The one inline editor for both transcript
/// (voice/note) and description (photo/video), replacing the
/// duplicated inline branches in `VoiceClipPanel`, `NotePanel`,
/// `CompactClipRow`, and the `PhotoDescriptionEditSheet` sheet
/// (Slice 9 deletion).
///
/// The four R3-flagged money tests, plus the coordinator
/// participation invariants:
///
///   1. `eyebrowMatchesField` — enum owns copy, not stringly-typed
///      callers.
///   2. `competingEditorCommits` — when the coordinator's active
///      editor switches to a different id while draft ≠ initial,
///      `.commitAndClose(trimmed:)` fires (never `.cancelAndClose`).
///      Rule #6 of `Memory Detail · unified editing model.md` lives
///      inside the component, not per-callsite.
///   3. `doneTrimsAndSkipsWhenUnchanged` — a Done tap on unchanged
///      or whitespace-only-different content yields `.skip`; real
///      changes yield `.commit(trimmed:)`.
///   4. `showMoveGovernsMoveVisibility` — the fate row's `Move to…`
///      button is present iff `onRelocate != nil` (SwiftUI-native
///      presence-of-callback idiom the codebase already uses).
@Suite(.serialized)
struct ClipEditorTests {

    // MARK: - (1) eyebrow + a11y verb mapping

    @Test func transcript_eyebrow_is_TRANSCRIPT() {
        #expect(ClipEditorField.transcript.eyebrow == "TRANSCRIPT")
    }

    @Test func description_eyebrow_is_DESCRIPTION() {
        #expect(ClipEditorField.description.eyebrow == "DESCRIPTION")
    }

    @Test func transcript_commit_a11y_names_transcript() {
        #expect(ClipEditorField.transcript.accessibilityCommitAction == "Save transcript")
    }

    @Test func description_commit_a11y_names_description() {
        #expect(ClipEditorField.description.accessibilityCommitAction == "Save description")
    }

    // MARK: - (3) doneTrimsAndSkipsWhenUnchanged
    //
    // (Testing (3) before (2) because (2) is `.decide` invoked in the
    // switch context, which needs the same underlying decision logic.)

    @Test func decide_identical_returns_skip() {
        let d = ClipEditorCommitDecision.decide(initial: "hi", draft: "hi")
        #expect(d == .skip)
    }

    @Test func decide_whitespace_only_diff_returns_skip() {
        let d = ClipEditorCommitDecision.decide(initial: "hi", draft: "   hi   ")
        #expect(d == .skip, "trailing/leading whitespace does not constitute a change")
    }

    @Test func decide_line_breaks_only_diff_returns_skip() {
        let d = ClipEditorCommitDecision.decide(initial: "hi", draft: "hi\n\n")
        #expect(d == .skip)
    }

    @Test func decide_real_change_returns_commit_with_trimmed_value() {
        let d = ClipEditorCommitDecision.decide(initial: "hi", draft: "  hello world  ")
        #expect(d == .commit(trimmed: "hello world"))
    }

    @Test func decide_empty_to_text_returns_commit() {
        let d = ClipEditorCommitDecision.decide(initial: "", draft: "new")
        #expect(d == .commit(trimmed: "new"))
    }

    /// Text-to-empty is a **skip** (wipe guard, P0 2026-07-16, supersedes
    /// the prior "erase commits empty" rule). An inline edit never blanks a
    /// non-empty field to empty — a stale/empty draft reaching commit was the
    /// transcript-wipe bug, not a real erase. Removing a clip's content is
    /// "Delete this Clip", not an edit-to-blank.
    @Test func decide_text_to_empty_skips_wipeGuard() {
        let d = ClipEditorCommitDecision.decide(initial: "was here", draft: "")
        #expect(d == .skip)
    }

    /// Both-empty (initial = "", draft = "") is a skip — nothing
    /// meaningful to commit. Guards against a bench voice clip's
    /// empty transcript flipping into an edit and then firing a
    /// spurious commit on cancel.
    @Test func decide_both_empty_returns_skip() {
        let d = ClipEditorCommitDecision.decide(initial: "", draft: "")
        #expect(d == .skip)
    }

    // MARK: - (2) competingEditorCommits (auto-commit-on-switch)
    //
    // The rule #6 invariant of `Memory Detail · unified editing
    // model.md`: when the coordinator's `activeEditId` changes to
    // another editor while ours has unsaved changes, we commit and
    // close (never cancel-and-lose-work).

    @Test func switch_with_dirty_draft_commits() {
        let outcome = ClipEditorSwitchOutcome.decide(
            initial: "hi",
            draft: "  hello world ",
            switchedToOtherEditor: true
        )
        #expect(outcome == .commitAndClose(trimmed: "hello world"))
    }

    @Test func switch_with_clean_draft_closes_silently() {
        let outcome = ClipEditorSwitchOutcome.decide(
            initial: "hi",
            draft: "hi",
            switchedToOtherEditor: true
        )
        #expect(outcome == .cancelAndClose,
                "unchanged draft on switch just closes — no spurious commit")
    }

    @Test func no_switch_returns_stay() {
        let outcome = ClipEditorSwitchOutcome.decide(
            initial: "hi",
            draft: "hi world",
            switchedToOtherEditor: false
        )
        #expect(outcome == .stayEditing,
                "an activeEditId change to our own id (or nil) is not a switch")
    }

    // MARK: - (4) showMoveGovernsMoveVisibility

    @Test func fate_row_hides_move_when_onRelocate_is_nil() {
        let actions = ClipEditorFateActions(onDelete: {}, onRelocate: nil)
        #expect(actions.showsMove == false)
    }

    @Test func fate_row_shows_move_when_onRelocate_is_nonNil() {
        let actions = ClipEditorFateActions(onDelete: {}, onRelocate: { })
        #expect(actions.showsMove == true)
    }
}
