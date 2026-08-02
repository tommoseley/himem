import Testing
import Foundation
@testable import HiMem

/// **F24 Defect 1 — the top-bar `Done` discarded an open edit.**
///
/// Observed on device (2026-07-31): on a bench clip, typing into the
/// transcript and tapping the top-right **Done** left the text
/// unchanged. Nothing was saved and nothing was said.
///
/// Root cause, and it is the reason this file exists in two halves:
/// `ClipEditorCommitDecision` — the one commit gate — was **correct**.
/// It simply was not called. `commitOpenEdits` set `contentDraft = nil`
/// and `annotationDraft = nil` under a comment asserting *"routed
/// through the same gate via each editor's own onDone … the ClipEditor
/// coordinator commits."* It does not. Nil'ing the draft removes
/// `ClipEditor` from the hierarchy; its only teardown is
/// `.onDisappear { coordinator.end(id: editId) }`, and `end` sets
/// `activeEditId = nil`, so `ClipEditorSwitchOutcome.decide` sees
/// `switchedToOtherEditor == false` and returns `.stayEditing`. No
/// commit, on the most natural gesture in the sheet.
///
/// So a value-level test of the decision proves nothing here — the
/// decision was always right. **The load-bearing test is the caller
/// guard** (`commitOpenEdits_reachesTheDecision`), per CLAUDE.md
/// § "Guard the Caller, Not Just the Owner". Its self-test
/// (`scanner_flagsThePreFixBody`) pins the exact shipped defect shape,
/// so the scanner cannot pass by matching nothing.
@Suite struct ClipEditorTopBarDoneTests {

    // MARK: - The decision the caller must reach

    @Test func openDraft_withRealEdit_commitsTrimmed() {
        #expect(
            ClipEditorModal.openDraftDecision(
                draft: "  the edited transcript  ",
                current: "the original transcript",
                field: .transcript
            ) == .commit(trimmed: "the edited transcript")
        )
    }

    @Test func openDraft_withNoDraftOpen_isNil() {
        #expect(
            ClipEditorModal.openDraftDecision(
                draft: nil, current: "anything", field: .transcript
            ) == nil
        )
    }

    @Test func openDraft_unchanged_skips() {
        #expect(
            ClipEditorModal.openDraftDecision(
                draft: "same text", current: "same text", field: .transcript
            ) == .skip
        )
    }

    /// Done-from-the-top-bar must not become a back door around the
    /// transcript wipe guard: emptying a transcript is "Delete this
    /// Clip", not an edit-to-blank.
    @Test func openDraft_emptiedTranscript_stillGuarded() {
        #expect(
            ClipEditorModal.openDraftDecision(
                draft: "   ", current: "real words", field: .transcript
            ) == .skip
        )
    }

    /// …but a description IS legitimately clearable, and Done must
    /// persist that, same as the editor's own Done.
    @Test func openDraft_clearedDescription_commitsEmpty() {
        #expect(
            ClipEditorModal.openDraftDecision(
                draft: "", current: "a description", field: .description
            ) == .commit(trimmed: "")
        )
    }

    // MARK: - The caller guard (the real money test)

    /// `commitOpenEdits` must *reach* the decision. A correct gate the
    /// caller stopped consulting is exactly what shipped.
    @Test func commitOpenEdits_reachesTheDecision() throws {
        let src = try Self.modalSource()
        let body = try Self.commitOpenEditsBody(in: src)
        #expect(
            Self.discardsWithoutCommitting(body: body) == false,
            """
            `ClipEditorModal.commitOpenEdits` closes its drafts without \
            routing them through `openDraftDecision` / `commitContent`. \
            That is F24 Defect 1: the top-bar Done silently discards a \
            typed edit. Body was:
            \(body)
            """
        )
    }

    /// Self-test — the scanner must recognise the shape that actually
    /// shipped. Without this, a regex that silently matches nothing
    /// reports a clean caller forever (the `loudPeakThenSilence`
    /// lesson: green for the wrong reason).
    @Test func scanner_flagsThePreFixBody() {
        let shipped = """
                // Done from the top bar while a field is open commits it (never lose
                // work), routed through the same gate via each editor's own onDone —
                // here we simply close drafts; the ClipEditor coordinator commits.
                contentDraft = nil
                annotationDraft = nil
        """
        #expect(Self.discardsWithoutCommitting(body: shipped) == true)
    }

    /// Self-test the other way — the fixed shape must NOT be flagged,
    /// so the guard can't fail permanently and get muted.
    @Test func scanner_acceptsACommittingBody() {
        let fixed = """
                if case .commit(let trimmed)? = Self.openDraftDecision(
                    draft: contentDraft, current: currentContent, field: contentField
                ) {
                    commitContent(trimmed)
                }
                contentDraft = nil
                annotationDraft = nil
        """
        #expect(Self.discardsWithoutCommitting(body: fixed) == false)
    }

    // MARK: - Scanner

    /// A body is a discard-without-commit when it clears a draft but
    /// never consults the commit decision.
    static func discardsWithoutCommitting(body: String) -> Bool {
        let code = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
            .joined(separator: "\n")
        let clearsADraft = code.contains("contentDraft = nil")
            || code.contains("annotationDraft = nil")
        let consultsTheGate = code.contains("openDraftDecision")
            || code.contains("ClipEditorCommitDecision.decide")
        return clearsADraft && !consultsTheGate
    }

    /// The body of `private func commitOpenEdits()`, brace-matched so a
    /// reformat can't defeat it.
    static func commitOpenEditsBody(in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("private func commitOpenEdits()") })
        else { throw Failure.functionNotFound }
        var depth = 0
        var started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.functionNotFound
    }

    static func modalSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MemoryStreamTests
            .deletingLastPathComponent()          // MemoryStream (project dir)
            .appendingPathComponent("MemoryStream/Views/Clip/ClipEditorModal.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            // Throw rather than pass on an empty read — a moved file must
            // break the guard loudly, never silently stop guarding.
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), functionNotFound }
}
