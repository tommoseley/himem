import Testing
import Foundation
@testable import HiMem

/// Money tests for the phone-direct voice composer save path's
/// transcription failure surfacing.
///
/// Before 2026-06-01 the save path collapsed every
/// `TranscriptionService.Outcome` into `outcome.textOrEmpty` — a
/// failure (model not yet installed, file unreadable, transcriber
/// threw) silently landed as a clip with an empty transcript and
/// no signal to the user that anything went wrong. The clip looked
/// indistinguishable from a genuine "no speech" result.
///
/// The watch-arrival path solved its version of this with
/// `InboxTranscriptionDispatcher.shouldMarkAttempted` so the inbox
/// sweep retries transient failures. The phone-direct path can't
/// retry — the user is in the foreground, the recording is over —
/// so it surfaces the deferral to the user instead. The contract:
/// `userFacingDeferralMessage` returns `nil` for definitive outcomes
/// (transcribed, including empty for genuine silence) and a copy
/// string for every infrastructure failure.
@Suite
struct VoiceCaptureSavePathOutcomeTests {

    private struct DummyError: Error {}

    /// A definitive answer from the recognizer (success). No deferral
    /// message — the transcript is on the fragment.
    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_forTranscribed_isNil() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "hello world", coverageSeconds: 3, fileDurationSeconds: 3, segmentCount: 1)
        )
        #expect(outcome.userFacingDeferralMessage == nil)
    }

    /// Genuine silence is also a definitive answer. The recognizer
    /// ran end-to-end and found no speech — the empty transcript IS
    /// the truth, not a deferral. No toast.
    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_forTranscribedEmpty_isNil() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "", coverageSeconds: 5, fileDurationSeconds: 5, segmentCount: 0)
        )
        #expect(outcome.userFacingDeferralMessage == nil)
    }

    /// Model still downloading on cold launch — user should know
    /// transcription will retry next time the model is ready.
    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_forModelNotInstalled_describesDeferral() {
        let outcome = TranscriptionService.Outcome.modelNotInstalled
        guard let message = outcome.userFacingDeferralMessage else {
            Issue.record("Expected deferral message for .modelNotInstalled, got nil")
            return
        }
        #expect(message.isEmpty == false)
    }

    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_forTranscriberFailed_describesDeferral() {
        let outcome = TranscriptionService.Outcome.transcriberFailed(DummyError())
        #expect(outcome.userFacingDeferralMessage != nil)
    }

    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_forFileUnreadable_describesDeferral() {
        let outcome = TranscriptionService.Outcome.fileUnreadable(DummyError())
        #expect(outcome.userFacingDeferralMessage != nil)
    }

    /// All three failure variants share the same user-facing message
    /// — the user doesn't need to disambiguate "the model isn't
    /// installed yet" from "the transcriber threw"; they need to
    /// know transcription will be retried. Honest label, not
    /// technical detail.
    @available(iOS 26.0, *)
    @Test func userFacingDeferralMessage_allFailures_useSameMessage() {
        let modelMissing = TranscriptionService.Outcome.modelNotInstalled
        let transcriberFailed = TranscriptionService.Outcome.transcriberFailed(DummyError())
        let fileUnreadable = TranscriptionService.Outcome.fileUnreadable(DummyError())
        #expect(modelMissing.userFacingDeferralMessage == transcriberFailed.userFacingDeferralMessage)
        #expect(transcriberFailed.userFacingDeferralMessage == fileUnreadable.userFacingDeferralMessage)
    }
}
