import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Money tests for the transcription pipeline at the watch's hard
/// 5-minute recording cap.
///
/// The bug context (2026-05-29): Tom recorded a 5-minute clip on
/// the watch, audio was perfectly audible on playback, but the clip
/// transcribed as empty and ended up auto-excluded. A 6-second clip
/// from the same session had the same outcome. Pattern: failures
/// clustered at the duration extremes (very short, at-cap), successes
/// in the 14–37 s band. Hypothesis: the compress→transcribe pipeline
/// has an edge-case failure at or near the 5-minute boundary —
/// possibly an AAC encoder issue, possibly a SpeechTranscriber buffer
/// exhaustion, possibly format mismatch on the watch's long-form
/// output.
///
/// These tests reproduce the conditions deterministically by looping
/// the existing 90-second fixture to produce a ~6-minute file (just
/// over the cap so any cap-boundary effect surfaces), running it
/// through `AudioCompressor` (the same compression the watch path
/// applies), then transcribing. If the bug is in the pipeline rather
/// than in the watch's specific encode, this test fails before fix
/// and passes after.
///
/// **Skips silently** when the SpeechTranscriber model isn't
/// installed (test simulator gap) — there's no point asserting on
/// transcription when the recognizer can't run.
struct TranscriptionMaxDurationTests {

    private func fixtureURL() -> URL? {
        Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf",
            subdirectory: "Fixtures"
        ) ?? Bundle(for: BundleAnchor.self).url(
            forResource: "long-speech-90s",
            withExtension: "caf"
        )
    }

    /// THE BUG-FIX MONEY TEST. ~6 minutes of speech (90 s fixture x 4)
    /// must round-trip through compress → transcribe and produce
    /// recognizable text, just like the existing 90-second case
    /// already does in `AudioCompressorTests`. If a hard regression
    /// at the 5-minute boundary lives in the pipeline (rather than
    /// in the watch's specific encode), it fails here.
    @available(iOS 26.0, *)
    @Test func sixMinuteSpeech_roundTripsCompressAndTranscribe() async throws {
        guard let fixture = fixtureURL() else {
            Issue.record("Fixture long-speech-90s.caf missing")
            return
        }
        guard await SpeechAssetGate.canExerciseTranscription(
                "a six-minute clip round-trips compress + transcribe"
            ) else { return }

        // Loop the 90 s fixture x 4 → ~360 s of speech audio. Just
        // over the watch's 300 s cap so any boundary effect (encoder
        // wrap, recognizer buffer reset) gets exercised.
        let loopedURL = try makeLoopedFile(source: fixture, copies: 4)
        defer { try? FileManager.default.removeItem(at: loopedURL) }

        // Compress with the same utility the watch-arrival path uses.
        let compressedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("looped-compressed-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: compressedURL) }
        try await AudioCompressor.compress(source: loopedURL, destination: compressedURL)

        // Sanity: compressed file is a valid audio file. If the AAC
        // encoder produced something AVAudioFile can't open, that's
        // the bug — not the recognizer.
        let readback = try AVAudioFile(forReading: compressedURL)
        #expect(readback.length > 0, "Compressed 6-min file decoded to zero frames — encoder broke")
        let compressedDuration = Double(readback.length) / readback.fileFormat.sampleRate
        print("[Test] compressed duration: \(compressedDuration)s")
        #expect(compressedDuration > 300, "Compressed file is shorter than the source — encoder dropped audio")

        // Money assertion: 6 minutes of clear speech → non-empty
        // transcript with substantial coverage. If `SpeechTranscriber`
        // is choking at the duration boundary, this fails with
        // .transcribed(empty) and segments=0.
        let outcome = await TranscriptionService.shared.transcribe(audioURL: compressedURL)
        guard case .transcribed(let result) = outcome else {
            Issue.record("Expected .transcribed for 6-min clip, got \(outcome)")
            return
        }
        print("[Test] transcribe textLen=\(result.text.count) coverage=\(result.coverageSeconds)s segments=\(result.segmentCount)")
        #expect(!result.text.isEmpty, "6-min speech produced empty transcript — bug reproduced")
        #expect(result.segmentCount > 0, "6-min speech produced 0 segments — recognizer rejected the file")
        #expect(result.coverageSeconds > 60, "Coverage \(result.coverageSeconds) s suspiciously low for 6-min file")
    }

    /// Looping helper. Reads the source file's PCM frames and writes
    /// them `copies` times to a fresh `.caf` at temp, returning the
    /// new URL. Format is preserved exactly from the source so the
    /// downstream `AudioCompressor.compress` sees the same shape it
    /// would from a real watch recording.
    private func makeLoopedFile(source: URL, copies: Int) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("looped-\(UUID().uuidString).caf")
        let inFile = try AVAudioFile(forReading: source)
        let outFile = try AVAudioFile(forWriting: dest, settings: inFile.fileFormat.settings)
        let bufferCapacity: AVAudioFrameCount = 4096
        for _ in 0..<copies {
            inFile.framePosition = 0
            while inFile.framePosition < inFile.length {
                guard let buf = AVAudioPCMBuffer(
                    pcmFormat: inFile.processingFormat,
                    frameCapacity: bufferCapacity
                ) else {
                    throw NSError(domain: "TranscriptionMaxDurationTests", code: 1)
                }
                try inFile.read(into: buf)
                if buf.frameLength > 0 {
                    try outFile.write(from: buf)
                } else {
                    break
                }
            }
        }
        return dest
    }
}

private final class BundleAnchor {}
