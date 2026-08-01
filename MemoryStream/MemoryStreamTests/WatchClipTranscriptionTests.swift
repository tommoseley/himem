import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Contract test: confirms that `TranscriptionService` can ingest the
/// audio file format produced by `WatchRecordingService`'s recording
/// pipeline. Originally written as a reproducer for the production
/// "watch clip arrives with No speech detected" bug — the hypothesis
/// being that watchOS-hardware's `inputNode.outputFormat(forBus:0)`
/// settings produce a CAF variant that SpeechAnalyzer silently rejects.
///
/// The test **passes** — a float32 non-interleaved mono 48 kHz CAF
/// (the watch's typical recording shape) transcribes cleanly through
/// the existing pipeline. That rules out raw format as the bug surface
/// and means the production issue lives upstream: either the watch
/// isn't capturing actual audio, the WatchConnectivity transfer is
/// corrupting the file, a locale mismatch is short-circuiting the
/// model-installed check, or there's a race in lazy transcription.
///
/// Keep this test as a regression guard so anyone who touches the
/// recording or transcription pipeline notices if the contract breaks.
struct WatchClipTranscriptionTests {

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

    @Test func watchStyleCaf_transcribesNonEmpty() async throws {
        guard let fixture = fixtureURL() else {
            Issue.record("Test fixture long-speech-90s.caf missing from MemoryStreamTests bundle")
            return
        }
        guard await SpeechAssetGate.canExerciseTranscription(
                "watch-format .caf transcribes to non-empty text"
            ) else { return }

        let source = try AVAudioFile(forReading: fixture)
        let sourceFormat = source.processingFormat  // typically Float32 non-interleaved at file rate

        // Build the format the watch's `inputNode.outputFormat(forBus:0)`
        // typically produces on real watchOS hardware: float32 mono
        // non-interleaved at 48 kHz. The .settings dict derived from this
        // is what `WatchRecordingService` hands to AVAudioFile(forWriting:).
        let watchSampleRate = 48_000.0
        let watchStyleFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: watchSampleRate,
            channels: 1,
            interleaved: false
        )!

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-format-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            // AVAudioFile init signature here mirrors WatchRecordingService:
            // settings-only, letting the framework derive commonFormat and
            // interleaving from the dict. If the dict is incomplete, this
            // is where divergence from the expected on-disk format would
            // creep in.
            let dest = try AVAudioFile(forWriting: tmp, settings: watchStyleFormat.settings)

            // Resample source → 48k mono float32 non-interleaved if needed.
            let needsConversion = (sourceFormat.sampleRate != watchSampleRate)
                || (sourceFormat.channelCount != 1)
                || (sourceFormat.commonFormat != .pcmFormatFloat32)

            if needsConversion {
                guard let converter = AVAudioConverter(from: sourceFormat, to: dest.processingFormat) else {
                    Issue.record("converter init failed")
                    return
                }
                let chunkFrames: AVAudioFrameCount = 4096
                let totalSourceFrames = AVAudioFrameCount(source.length)
                var consumedSourceFrames: AVAudioFrameCount = 0
                while consumedSourceFrames < totalSourceFrames {
                    let toRead = min(chunkFrames, totalSourceFrames - consumedSourceFrames)
                    guard let inBuf = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: toRead) else {
                        Issue.record("in-buffer alloc failed")
                        return
                    }
                    try source.read(into: inBuf, frameCount: toRead)
                    if inBuf.frameLength == 0 { break }
                    consumedSourceFrames += inBuf.frameLength

                    let outCapacity = AVAudioFrameCount(Double(inBuf.frameLength) * watchSampleRate / sourceFormat.sampleRate) + 1024
                    guard let outBuf = AVAudioPCMBuffer(pcmFormat: dest.processingFormat, frameCapacity: outCapacity) else {
                        Issue.record("out-buffer alloc failed")
                        return
                    }
                    var inputProvided = false
                    let inputBlock: AVAudioConverterInputBlock = { _, status in
                        if inputProvided {
                            status.pointee = .noDataNow
                            return nil
                        }
                        inputProvided = true
                        status.pointee = .haveData
                        return inBuf
                    }
                    var error: NSError?
                    let result = converter.convert(to: outBuf, error: &error, withInputFrom: inputBlock)
                    if result == .error {
                        Issue.record("convert failed: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    if outBuf.frameLength > 0 {
                        try dest.write(from: outBuf)
                    }
                }
            } else {
                // Source already in target format — pass buffers straight through.
                let chunkFrames: AVAudioFrameCount = 4096
                let totalFrames = AVAudioFrameCount(source.length)
                var copied: AVAudioFrameCount = 0
                while copied < totalFrames {
                    let toRead = min(chunkFrames, totalFrames - copied)
                    guard let buf = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: toRead) else {
                        Issue.record("buffer alloc failed")
                        return
                    }
                    try source.read(into: buf, frameCount: toRead)
                    if buf.frameLength == 0 { break }
                    try dest.write(from: buf)
                    copied += buf.frameLength
                }
            }
            // `dest` goes out of scope here, finalizing the header.
        }

        // Sanity: confirm file is readable + non-zero before transcribing.
        let readback = try AVAudioFile(forReading: tmp)
        #expect(readback.length > 0, "Watch-style re-encode produced empty file")
        print("[Test] watch-style file format: \(readback.fileFormat)")
        print("[Test] watch-style processing format: \(readback.processingFormat)")
        print("[Test] watch-style length: \(readback.length) frames @ \(readback.fileFormat.sampleRate) Hz")

        let outcome = await TranscriptionService.shared.transcribe(audioURL: tmp)
        guard case .transcribed(let result) = outcome else {
            Issue.record("Watch-style CAF produced \(outcome); expected .transcribed")
            return
        }

        print("[Test] transcribe result: textLen=\(result.text.count) coverage=\(result.coverageSeconds)s segments=\(result.segmentCount) fileDuration=\(result.fileDurationSeconds)s")

        // Money assertion — the bug surface. If empty, the watch-style
        // .caf path defeats SpeechAnalyzer; ship the fix.
        #expect(
            !result.text.isEmpty,
            "TranscriptionService returned empty text on watch-style CAF. coverage=\(result.coverageSeconds)s, segments=\(result.segmentCount). This is the production bug."
        )
        #expect(
            result.segmentCount > 0,
            "SpeechAnalyzer produced 0 result segments — likely silently rejected the file format"
        )
    }
}

/// Bundle anchor — same pattern as TranscriptionServiceLongFormTests.
private final class BundleAnchor {}
