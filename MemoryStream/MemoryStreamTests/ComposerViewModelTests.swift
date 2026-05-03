import Testing
import Foundation
@testable import MemoryStream

@MainActor
@Suite(.serialized)
struct ComposerViewModelTests {

    private func makeComposer() -> (ComposerViewModel, SpeechService) {
        let composer = ComposerViewModel()
        let speech = SpeechService()
        composer.speechService = speech
        return (composer, speech)
    }

    /// Idempotency: calling stopRecordingAndStageIfActive when nothing is
    /// recording is a no-op. Important because the Commit button calls it
    /// unconditionally, and we don't want it to clobber other state when
    /// the user wasn't mid-record.
    @Test func stopRecordingAndStageIfActive_isNoOp_whenNotRecording() {
        let (composer, _) = makeComposer()
        composer.pendingTranscripts = ["pre-existing transcript"]

        composer.stopRecordingAndStageIfActive()

        // Pre-existing data untouched, no new staging happened.
        #expect(composer.pendingTranscripts == ["pre-existing transcript"])
        #expect(composer.mediaCaptures.isEmpty)
    }

    /// Money test for the "No text provided" bug. While the user is
    /// recording, the Commit button should be able to fire and capture
    /// the live transcript. stopRecordingAndStageIfActive snapshots
    /// transcribedText BEFORE calling speechService.stopRecording (which
    /// can clobber it via the recognition callback) and appends it to
    /// pendingTranscripts.
    @Test func stopRecordingAndStageIfActive_capturesLiveTranscript() {
        let (composer, speech) = makeComposer()
        // Simulate active recording with a live transcript on screen.
        speech.transcribedText = "hello world this is a memory"
        speech.isRecording = true

        composer.stopRecordingAndStageIfActive()

        #expect(composer.pendingTranscripts == ["hello world this is a memory"])
        // Recording state cleared.
        #expect(speech.isRecording == false)
        #expect(speech.transcribedText == "")
    }

    /// Empty transcript shouldn't appear in pendingTranscripts (would render
    /// as a blank entry on commit).
    @Test func stopRecordingAndStageIfActive_skipsEmptyTranscript() {
        let (composer, speech) = makeComposer()
        speech.transcribedText = "   "
        speech.isRecording = true

        composer.stopRecordingAndStageIfActive()

        #expect(composer.pendingTranscripts.isEmpty)
    }

    /// Dedupe: if .onChange already staged the transcript before the Commit
    /// button fired, the explicit stage shouldn't double-add it.
    @Test func stopRecordingAndStageIfActive_dedupesExistingTranscript() {
        let (composer, speech) = makeComposer()
        speech.transcribedText = "the quick brown fox"
        speech.isRecording = true
        composer.pendingTranscripts = ["the quick brown fox"] // already there from .onChange

        composer.stopRecordingAndStageIfActive()

        #expect(composer.pendingTranscripts == ["the quick brown fox"])
    }
}
