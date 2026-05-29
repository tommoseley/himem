import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// **Hero-path money tests** for the transcription pipeline.
///
/// The bug these tests guard against (2026-05-29): watch clips
/// arrived in the inbox, the `TranscriptionService` returned an
/// empty result because the SpeechTranscriber model wasn't installed
/// yet (cold-launch race against the background pre-warm task), and
/// `transcribePendingInboxClips` then marked every clip as
/// `transcriptionAttempted = true`. The UI rendered them all as
/// "no speech detected · likely accidental" — silently destroying
/// real user content with no path to recovery.
///
/// Root cause: `TranscriptionService.transcribe` collapsed four
/// distinct outcomes (model-not-installed, file-unreadable,
/// transcriber-error, genuine-empty) into the same empty `Result`.
/// The inbox sweep then treated every empty result as "ran and
/// found nothing," marking the clip permanently as accidental.
///
/// Fix: `transcribe` returns an `Outcome` enum. The inbox sweep
/// only flips `transcriptionAttempted` on `.transcribed` — every
/// infrastructure failure leaves the clip pending so the next
/// sweep retries.
///
/// These tests must fail against the pre-fix code and pass after.
@MainActor
@Suite(.serialized)
struct TranscriptionPipelineOutcomeTests {

    // MARK: - Outcome contract (pure, deterministic)

    /// The lone dispatch surface that decides whether an outcome
    /// should flip the manifest's `transcriptionAttempted` flag.
    /// Locked here so a future "let's also mark X as attempted"
    /// regression can't slip in unnoticed.

    @available(iOS 26.0, *)
    @Test func outcomeDispatch_transcribed_marksAttempted() {
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "hello world", coverageSeconds: 3, fileDurationSeconds: 3, segmentCount: 1)
        )
        #expect(InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) == true)
        #expect(InboxTranscriptionDispatcher.transcriptForMark(from: outcome) == "hello world")
    }

    @available(iOS 26.0, *)
    @Test func outcomeDispatch_transcribedEmpty_marksAttempted_withEmptyText() {
        // Legit "ran, heard genuine silence" — the model executed
        // end-to-end, found no speech. This case SHOULD mark
        // attempted, with empty text, so the UI renders the
        // accidental note honestly.
        let outcome = TranscriptionService.Outcome.transcribed(
            TranscriptionService.Result(text: "", coverageSeconds: 5, fileDurationSeconds: 5, segmentCount: 0)
        )
        #expect(InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) == true)
        #expect(InboxTranscriptionDispatcher.transcriptForMark(from: outcome) == "")
    }

    @available(iOS 26.0, *)
    @Test func outcomeDispatch_modelNotInstalled_leavesPending() {
        // The bug: pre-fix code marked attempted here, silently
        // burning a real clip because the model install was still
        // in flight. Post-fix MUST leave pending.
        let outcome = TranscriptionService.Outcome.modelNotInstalled
        #expect(InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) == false)
    }

    @available(iOS 26.0, *)
    @Test func outcomeDispatch_fileUnreadable_leavesPending() {
        struct DummyError: Error {}
        let outcome = TranscriptionService.Outcome.fileUnreadable(DummyError())
        #expect(InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) == false)
    }

    @available(iOS 26.0, *)
    @Test func outcomeDispatch_transcriberFailed_leavesPending() {
        struct DummyError: Error {}
        let outcome = TranscriptionService.Outcome.transcriberFailed(DummyError())
        #expect(InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) == false)
    }

    // MARK: - Outcome classification (real audio fixtures)

    /// Confirms the speech fixture produces `.transcribed` with
    /// non-empty text — the baseline "everything works" assertion.
    /// Skipped silently when the simulator doesn't have the model
    /// cached; treat the skip as a known-test-env gap, not a pass.
    @available(iOS 26.0, *)
    @Test func transcribe_speechFixture_returnsTranscribedWithText() async throws {
        guard let fixture = speechFixtureURL() else {
            Issue.record("Fixture long-speech-90s.caf missing from test bundle")
            return
        }
        guard await TranscriptionService.shared.modelIsInstalled(for: .current) else {
            print("[Test] skipped — model not installed in this simulator")
            return
        }
        let outcome = await TranscriptionService.shared.transcribe(audioURL: fixture)
        guard case .transcribed(let result) = outcome else {
            Issue.record("Expected .transcribed, got \(outcome)")
            return
        }
        #expect(!result.text.isEmpty, "Speech fixture produced empty text — recognizer regression")
        #expect(result.segmentCount > 0, "Speech fixture produced zero segments")
    }

    /// A missing audio file is `.fileUnreadable`, not `.transcribed`
    /// with empty text — so the inbox sweep retries instead of
    /// silently marking the clip as accidental forever.
    @available(iOS 26.0, *)
    @Test func transcribe_missingFile_returnsFileUnreadable() async throws {
        // We only assert the model-installed path; if the model
        // isn't installed we'd get .modelNotInstalled before the
        // file-open attempt. Skip in that case.
        guard await TranscriptionService.shared.modelIsInstalled(for: .current) else {
            print("[Test] skipped — model not installed in this simulator")
            return
        }
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).caf")
        let outcome = await TranscriptionService.shared.transcribe(audioURL: bogus)
        if case .fileUnreadable = outcome { return }
        Issue.record("Expected .fileUnreadable for missing file, got \(outcome)")
    }

    /// A genuine-silence file goes through the recognizer end-to-end
    /// and produces an empty transcript — that's `.transcribed` with
    /// empty text, NOT a failure case. The user really did record
    /// nothing.
    @available(iOS 26.0, *)
    @Test func transcribe_silenceFixture_returnsTranscribedWithEmptyText() async throws {
        guard await TranscriptionService.shared.modelIsInstalled(for: .current) else {
            print("[Test] skipped — model not installed in this simulator")
            return
        }
        let silenceURL = try makeSilenceFile(seconds: 3)
        defer { try? FileManager.default.removeItem(at: silenceURL) }

        let outcome = await TranscriptionService.shared.transcribe(audioURL: silenceURL)
        guard case .transcribed(let result) = outcome else {
            Issue.record("Silence should be .transcribed (engine ran, found nothing), got \(outcome)")
            return
        }
        #expect(result.text.isEmpty, "Silence fixture produced text — recognizer hallucinating")
    }

    // MARK: - Fixture helpers

    private func speechFixtureURL() -> URL? {
        Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf",
            subdirectory: "Fixtures"
        ) ?? Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf"
        )
    }

    /// Writes a zero-filled PCM file at 16 kHz mono — what the
    /// recognizer would see for a clip recorded into a fully-silent
    /// environment (or one where the mic was muted at the source).
    /// Generated at test time so we don't need to bundle yet
    /// another fixture file.
    private func makeSilenceFile(seconds: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence-\(UUID().uuidString).caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(seconds * 16000)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "TranscriptionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "buffer alloc failed"])
        }
        buffer.frameLength = frameCount
        // Float32 buffers initialize to zero — that's the silence.
        try file.write(from: buffer)
        return url
    }
}

private final class BundleAnchor {}
