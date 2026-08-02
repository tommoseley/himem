import Testing
import Foundation
@testable import HiMem

/// **Device pass 2026-08-01 · three defects on the Clip Editor surface.**
///
/// 1. **F21/B4 was unshipped** — the blue sparkle consequence line was
///    still rendering. Deleted, replaced with nothing.
/// 2. **Two Done buttons live at once** — the top-bar Done and the
///    inline Cancel/Done pair. Ruled: keep both, and prove they cannot
///    disagree. That proof is `bothDonePathsReachTheSameDecision`.
/// 3. **"Original recording · 0:14" rendered twice** — the modal's own
///    Zone-1 header and again in the editor's evidence row.
@Suite struct ClipEditorSurfaceTests {

    // MARK: - 2 · the two Done buttons cannot disagree

    /// **The equivalence proof.** The inline Done runs
    /// `ClipEditorCommitDecision.decide(initial:draft:field:)`; the
    /// top-bar Done runs `ClipEditorModal.openDraftDecision(draft:current:
    /// field:)`. Two entry points, and they must be the same function of
    /// the same inputs — including on the wipe guard, where a divergence
    /// would let one button blank a transcript the other refuses to.
    ///
    /// Exhaustive over the cases that carry meaning: unchanged,
    /// whitespace-only, real edit, emptied, and both-empty × both fields.
    @Test func bothDonePathsReachTheSameDecision() {
        let pairs: [(initial: String, draft: String)] = [
            ("same words",  "same words"),      // unchanged
            ("same words",  "  same words  "),  // whitespace only
            ("old words",   "new words"),       // real edit
            ("real words",  ""),                // emptied → wipe guard
            ("real words",  "   "),             // whitespace-emptied
            ("",            "first words"),     // empty → text
            ("",            ""),                // both empty
            ("",            "   ")              // empty → whitespace
        ]
        for field in [ClipEditorField.transcript, .description] {
            for pair in pairs {
                let inline = ClipEditorCommitDecision.decide(
                    initial: pair.initial, draft: pair.draft, field: field
                )
                let topBar = ClipEditorModal.openDraftDecision(
                    draft: pair.draft, current: pair.initial, field: field
                )
                #expect(topBar == inline,
                        """
                        The two Done buttons disagree on \
                        field=\(field) initial="\(pair.initial)" draft="\(pair.draft)": \
                        inline=\(inline) topBar=\(String(describing: topBar))
                        """)
            }
        }
    }

    /// A no-draft state has no decision to make — the top-bar Done must
    /// return nil rather than fabricate a commit from an empty field.
    @Test func topBarDone_withNoOpenDraft_decidesNothing() {
        #expect(ClipEditorModal.openDraftDecision(
            draft: nil, current: "anything", field: .transcript) == nil)
    }

    /// The two paths must also read the SAME INPUTS. Equivalent logic on
    /// different values would still diverge — the inline editor's
    /// `initialValue` and `commitOpenEdits`' `current` are both
    /// `currentContent`, and that is what makes the equivalence above
    /// hold at runtime rather than only in this test.
    @Test func bothDonePathsReadTheSameSource() throws {
        let src = try Self.modalSource()
        #expect(src.contains("initialValue: currentContent"),
                "The inline editor no longer seeds from `currentContent` — the two Done paths could now disagree on their inputs.")
        let body = try Self.functionBody(named: "private func commitOpenEdits()", in: src)
        #expect(body.contains("current: currentContent"),
                "The top-bar Done no longer reads `currentContent`.\n\(body)")
    }

    // MARK: - 1 · F21/B4 · the sparkle status line is gone

    /// Pinned as a literal because **the copy IS the subject** — this is
    /// a retired line, like "Let Go". A failure means it came back, not
    /// that phrasing drifted.
    @Test func theSparkleConsequenceLineIsGone() throws {
        let src = try Self.modalSource()
        #expect(src.contains("your edit shows in every memory that uses it") == false,
                "F21/B4: the blue sparkle consequence line is back.")
    }

    /// The stronger form: no sparkle-decorated label may sit inside the
    /// editing branch at all. AI-blue + sparkle is reserved for
    /// *invoking* AI (Buttons & Actions); dressing status as an action
    /// is what F21 retired.
    @Test func noSparkleLabelDecoratesTheEditingBranch() throws {
        let src = try Self.modalSource()
        let block = try Self.functionBody(named: "private var contentBlock:", in: src)
        let code = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
            .joined(separator: "\n")
        #expect(code.contains("systemImage: \"sparkles\"") == false,
                "A sparkle label is decorating the clip's edit block again.\n\(block)")
    }

    // MARK: - 3 · the duration renders once

    /// The modal draws "Original recording · 0:14" in its own Zone-1
    /// header, so it must NOT also pass `evidence` into the editor —
    /// that produced a second identical line under the transcript.
    /// Suppressed at this call site rather than removed from
    /// `ClipEditor`, whose other callers have no such header.
    @Test func theModalDoesNotDuplicateTheRecordingLine() throws {
        let src = try Self.modalSource()
        #expect(src.contains("Text(\"Original recording\\(durationSuffix)\")"),
                "The Zone-1 header no longer renders the recording line — re-check which of the two survived.")
        let block = try Self.functionBody(named: "private var contentBlock:", in: src)
        #expect(block.contains("evidence: nil"),
                "The modal passes evidence into the editor again — the duration renders twice.\n\(block)")
    }

    /// …and the capability stays available to the call sites that need
    /// it, so this fix cannot have been done by gutting the component.
    @Test func theEditorStillSupportsAnEvidenceRow() throws {
        let src = try Self.source("MemoryStream/Views/Clip/ClipEditor.swift")
        #expect(src.contains("private func evidenceRow"),
                "evidenceRow was deleted — CompactTranscriptViews / ChronologicalCaptureStream lose their only duration render.")
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.notFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.notFound(needle)
    }

    static func modalSource() throws -> String {
        try source("MemoryStream/Views/Clip/ClipEditorModal.swift")
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), notFound(String) }
}
