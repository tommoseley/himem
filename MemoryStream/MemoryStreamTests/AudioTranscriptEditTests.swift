import Testing
import Foundation
@testable import HiMem

/// P0 money tests (2026-07-16) — "open a clip, tap Done, transcript wiped."
///
/// Root cause: `AudioPlayerSheet` (a separate, non-unified commit path) seeded
/// its draft ASYNCHRONOUSLY via `.task`, leaving the draft empty in the window
/// before the task ran. A Done in that window committed "" over a real
/// transcript. `AudioTranscriptEdit` seeds SYNCHRONOUSLY in `init`, so the
/// draft equals the current transcript from the first render — a no-op Done is
/// deterministically a skip. It also routes the commit through the unified
/// `ClipEditorCommitDecision`, so the sheet and the inline `ClipEditor` share
/// one rule.
@Suite
struct AudioTranscriptEditTests {

    /// THE money test: a freshly-opened editor over transcript "T", committed
    /// with no edit, persists nothing (skip) — so "T" survives. This is only
    /// true because the draft is seeded synchronously to "T"; an empty draft
    /// would commit "" (the wipe — see `emptyDraft_wouldCommitAWipe`).
    @Test func freshlyOpenedEditor_noOpDone_skips() {
        let edit = AudioTranscriptEdit(initial: "Ben said the Basque cheesecake")
        #expect(edit.draft == "Ben said the Basque cheesecake",
                "the draft must be seeded with the current transcript, synchronously")
        #expect(edit.pendingCommit == nil,
                "a no-op Done must skip — the transcript must not be overwritten")
    }

    /// An empty draft against a real transcript now **skips** (wipe guard,
    /// P0 2026-07-16). Even if a stale/empty draft reaches commit, the gate
    /// refuses to blank a non-empty transcript — belt-and-suspenders with the
    /// synchronous seed.
    @Test func emptyDraft_isGuarded_skips() {
        var edit = AudioTranscriptEdit(initial: "real transcript")
        edit.draft = ""   // simulates a stale/empty draft reaching commit
        #expect(edit.pendingCommit == nil,
                "the gate never blanks a non-empty transcript with an empty draft")
    }

    /// A real edit persists the trimmed new value.
    @Test func realEdit_commitsTrimmed() {
        var edit = AudioTranscriptEdit(initial: "hi")
        edit.draft = "  hello world  "
        #expect(edit.pendingCommit == "hello world")
    }

    /// Whitespace-only difference is not a change — skip.
    @Test func whitespaceOnlyDiff_skips() {
        var edit = AudioTranscriptEdit(initial: "hi")
        edit.draft = "  hi\n"
        #expect(edit.pendingCommit == nil)
    }

    /// Erasing to empty is now a **skip** (wipe guard, P0 2026-07-16). An
    /// inline edit never blanks a non-empty field — removing content is
    /// "Delete this Clip", not an edit-to-blank. The buffer can't read intent,
    /// and a stale/empty draft is the wipe bug far more often than a real
    /// erase, so the gate skips it.
    @Test func erasingToEmpty_skips_wipeGuard() {
        var edit = AudioTranscriptEdit(initial: "was here")
        edit.draft = ""
        #expect(edit.pendingCommit == nil)
    }
}
