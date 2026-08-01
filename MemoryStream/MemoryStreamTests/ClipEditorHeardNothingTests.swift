import Testing
import Foundation
@testable import HiMem

/// **F24 Defect 4 — a transcription that succeeded and heard nothing
/// said nothing at all.**
///
/// `retranscribe` set `retryStatus = outcome.userFacingDeferralMessage`
/// on empty text. That property returns **nil for `.transcribed`** by
/// design — a definitive result needs no deferral notice. So the one
/// case where the run succeeded and the recording contained no speech
/// produced: a spinner, a return to idle, no message, no change.
/// Indistinguishable from a dead button, which is how it was reported.
///
/// The trigger population is not hypothetical. Every clip recorded
/// before `4a08423` was captured under `.measurement`, which suppressed
/// input gain — so short, quiet, pre-fix recordings are exactly the
/// ones that transcribe to nothing. Those are the clips already on the
/// second dogfooder's device.
///
/// **The ruled copy: "No words in this recording."** The transcription
/// ran and heard nothing — not a failure, not a deferral, no blame, and
/// no promise of a retry that won't help.
@Suite struct ClipEditorHeardNothingTests {

    // MARK: - Three facts, three strings

    /// The load-bearing constraint: "not yet transcribed" and
    /// "transcribed and there were no words" are DIFFERENT FACTS and
    /// must not share a string. Before the fix both rendered
    /// "(no transcript)".
    @Test func silenceAndNotYetTranscribed_areDifferentStrings() {
        let notYet = ClipEditorModal.emptyContentState(
            isDescriptionField: false, heardNothing: false, attemptedAndEmpty: false
        )
        let silence = ClipEditorModal.emptyContentState(
            isDescriptionField: false, heardNothing: true, attemptedAndEmpty: false
        )
        #expect(notYet == .notYetTranscribed)
        #expect(silence == .transcribedToSilence)
        #expect(notYet.message != silence.message)
    }

    /// Pinned as a literal: here the wording IS the promise (the ruled
    /// honest state). A failure means the promise moved and needs a
    /// ruling — not that phrasing drifted.
    @Test func silenceMessage_isTheRuledCopy() {
        #expect(ClipEditorModal.EmptyContentState.transcribedToSilence.message
                == "No words in this recording.")
    }

    /// It must not read as a failure or a deferral — that was the whole
    /// objection to reusing the deferral string, which would have been
    /// false in both clauses.
    @Test func silenceMessage_claimsNeitherFailureNorRetry() {
        let m = ClipEditorModal.EmptyContentState.transcribedToSilence.message.lowercased()
        #expect(m.contains("fail") == false)
        #expect(m.contains("error") == false)
        #expect(m.contains("try again") == false)
        #expect(m.contains("deferred") == false)
    }

    /// The stored signal reaches the same state as this session's run —
    /// a clip that already transcribed to silence says so on open, not
    /// only after she re-runs it.
    @Test func storedAttemptWithNoText_readsAsSilence() {
        #expect(
            ClipEditorModal.emptyContentState(
                isDescriptionField: false, heardNothing: false, attemptedAndEmpty: true
            ) == .transcribedToSilence
        )
    }

    /// Photo/video keeps its invitation — an empty description is not a
    /// report about audio.
    @Test func descriptionField_isUnaffected() {
        #expect(
            ClipEditorModal.emptyContentState(
                isDescriptionField: true, heardNothing: true, attemptedAndEmpty: true
            ) == .needsDescription
        )
        #expect(ClipEditorModal.EmptyContentState.needsDescription.message == "Add a description")
    }

    // MARK: - "again" must be true

    @Test func label_dropsAgain_whenThereIsNoTranscript() {
        #expect(ClipEditorModal.transcribeActionLabel(hasTranscript: false) == "Transcribe with AI")
        #expect(ClipEditorModal.transcribeActionLabel(hasTranscript: false).contains("again") == false)
    }

    @Test func label_keepsAgain_whenRepeatingARealTranscription() {
        #expect(ClipEditorModal.transcribeActionLabel(hasTranscript: true) == "Transcribe again with AI")
    }

    /// Crucible: a blue AI button names the AI. Both labels do.
    @Test func bothLabels_nameTheAI() {
        #expect(ClipEditorModal.transcribeActionLabel(hasTranscript: true).contains("with AI"))
        #expect(ClipEditorModal.transcribeActionLabel(hasTranscript: false).contains("with AI"))
    }

    // MARK: - Caller guard

    /// The reproduction: `retranscribe` must branch on the OUTCOME, not
    /// just on the emptiness of the text. Reading
    /// `userFacingDeferralMessage` for a `.transcribed` result yields
    /// nil and shows nothing — the defect.
    @Test func retranscribe_distinguishesSilenceFromDeferral() throws {
        let src = try Self.modalSource()
        let body = try Self.functionBody(named: "private func retranscribe()", in: src)
        #expect(
            body.contains("case .transcribed = outcome"),
            """
            `retranscribe` does not distinguish a successful-but-empty \
            transcription from a deferral. `userFacingDeferralMessage` is nil \
            for `.transcribed`, so that case shows nothing at all — F24 \
            Defect 4. Body was:
            \(body)
            """
        )
        #expect(
            body.contains("heardNothing = true"),
            "`retranscribe` never records the heard-nothing state, so the transcript slot cannot report it."
        )
    }

    // MARK: - Source access

    static func functionBody(named needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.functionNotFound(needle)
        }
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
        throw Failure.functionNotFound(needle)
    }

    static func modalSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Clip/ClipEditorModal.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), functionNotFound(String) }
}
