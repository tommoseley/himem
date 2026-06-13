import Testing
import Foundation
@testable import HiMem

/// Money tests for `AudioPlayerSheet.decideRetryAction(outcome:)` — the
/// pure function the Retry transcription button funnels through.
///
/// Before 2026-06-07 the retry path collapsed every
/// `TranscriptionService.Outcome` into `outcome.textOrEmpty` and
/// assigned it directly to the draft transcript binding. A failure
/// (model not installed, file unreadable, transcriber threw)
/// silently wiped the user's edited transcript to empty — and if
/// they tapped Done out of habit, `commitIfChanged()` persisted the
/// blank because `trimmed != original`. The bug actively destroyed
/// content. The Troika UX reviewer caught it; the code comment at
/// `AudioPlayerSheet.retryTranscription` even named it as known.
///
/// The contract going forward:
/// - `.transcribed` with non-empty text → overwrite the draft.
/// - `.transcribed` with empty text (genuine silence) → keep the
///   draft and surface a "no speech in the retry" message; the
///   user's typed words are probably better than the recognizer's
///   silence verdict.
/// - All failure variants → keep the draft and surface a
///   "couldn't retranscribe" message.
@Suite
struct AudioPlayerSheetRetryDecisionTests {

    private struct DummyError: Error {}

    /// Happy path: transcriber returns non-empty text → overwrite.
    @available(iOS 26.0, *)
    @Test func transcribedWithText_overwritesDraft() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "hello there", coverageSeconds: 2, fileDurationSeconds: 2, segmentCount: 1)
        )
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .overwriteDraft(let newText) = action else {
            Issue.record("Expected .overwriteDraft, got \(action)")
            return
        }
        #expect(newText == "hello there")
    }

    /// Money test for the regression. Failure → DO NOT overwrite.
    @available(iOS 26.0, *)
    @Test func modelNotInstalled_keepsDraft() {
        let outcome = TranscriptionService.Outcome.modelNotInstalled
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .keepDraft(let reason) = action else {
            Issue.record("Expected .keepDraft, got \(action) — failure silently overwrote the draft")
            return
        }
        #expect(reason.isEmpty == false)
    }

    @available(iOS 26.0, *)
    @Test func transcriberFailed_keepsDraft() {
        let outcome = TranscriptionService.Outcome.transcriberFailed(DummyError())
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .keepDraft = action else {
            Issue.record("Expected .keepDraft, got \(action)")
            return
        }
    }

    @available(iOS 26.0, *)
    @Test func fileUnreadable_keepsDraft() {
        let outcome = TranscriptionService.Outcome.fileUnreadable(DummyError())
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .keepDraft = action else {
            Issue.record("Expected .keepDraft, got \(action)")
            return
        }
    }

    /// Genuine silence is a definitive answer from the recognizer
    /// (segments=0, coverage>0 in the diagnostic tag). The user
    /// chose to retry — but if they had typed text already, blanking
    /// it now would be the same regression we're fixing. Keep the
    /// draft; let the user decide whether to clear it themselves.
    @available(iOS 26.0, *)
    @Test func transcribedEmpty_keepsDraft() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "", coverageSeconds: 5, fileDurationSeconds: 5, segmentCount: 0)
        )
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .keepDraft(let reason) = action else {
            Issue.record("Expected .keepDraft for empty success, got \(action)")
            return
        }
        // Empty-success and failure surface different reasons so the
        // status UI can be tuned per-case, but neither overwrites.
        #expect(reason.isEmpty == false)
    }

    /// Whitespace-only success is treated as empty. A transcriber
    /// that returns "  \n  " shouldn't clear a real user transcript
    /// either.
    @available(iOS 26.0, *)
    @Test func transcribedWhitespaceOnly_keepsDraft() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "   \n  ", coverageSeconds: 3, fileDurationSeconds: 3, segmentCount: 2)
        )
        let action = AudioPlayerSheet.decideRetryAction(outcome: outcome)
        guard case .keepDraft = action else {
            Issue.record("Expected .keepDraft for whitespace-only success, got \(action)")
            return
        }
    }
}
