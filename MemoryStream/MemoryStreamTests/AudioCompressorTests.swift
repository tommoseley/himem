import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// Contract tests for `AudioCompressor`.
///
/// Money assertions:
/// 1. AAC output is dramatically smaller than the PCM source (~10–50×
///    reduction on speech). The whole reason this utility exists.
/// 2. `TranscriptionService` still transcribes the compressed file.
///    AAC must round-trip cleanly through `AVAudioFile` /
///    `SpeechAnalyzer` — if not, the size win is moot.
struct AudioCompressorTests {

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

    @Test func compress_shrinksDramatically_andStillTranscribes() async throws {
        guard let source = fixtureURL() else {
            Issue.record("Fixture long-speech-90s.caf missing")
            return
        }

        let sourceSize = try fileSize(source)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: dest) }

        try await AudioCompressor.compress(source: source, destination: dest)

        let compressedSize = try fileSize(dest)
        let ratio = Double(sourceSize) / Double(compressedSize)

        print("[Test] source=\(sourceSize) bytes, compressed=\(compressedSize) bytes, ratio=\(String(format: "%.1fx", ratio))")

        // Money assertion #1 — size win. 10× is conservative; we expect
        // ~30–50× for speech but a lower floor leaves headroom for the
        // encoder's framing overhead on short clips.
        #expect(
            ratio >= 10.0,
            "AAC compression ratio \(String(format: "%.1fx", ratio)) is below the 10× floor — codec settings may be wrong"
        )

        // Sanity — the result is a valid audio file.
        let readback = try AVAudioFile(forReading: dest)
        #expect(readback.length > 0, "Compressed file decoded to zero frames")
        print("[Test] compressed file format: \(readback.fileFormat)")
        print("[Test] compressed processing format: \(readback.processingFormat)")

        // Money assertion #2 — round-trips through the transcription
        // pipeline. Skip when the model isn't installed (env-dependent).
        guard await TranscriptionService.shared.modelIsInstalled(for: .current) else {
            print("[Test] skipping transcription leg — model not installed")
            return
        }
        let outcome = await TranscriptionService.shared.transcribe(audioURL: dest)
        guard case .transcribed(let result) = outcome else {
            Issue.record("AAC file produced \(outcome) — expected .transcribed; round-trip broken")
            return
        }
        print("[Test] transcribe textLen=\(result.text.count) coverage=\(result.coverageSeconds)s segments=\(result.segmentCount)")
        #expect(!result.text.isEmpty, "AAC file produced empty transcript — round-trip broken")
        #expect(result.segmentCount > 0, "AAC file produced 0 segments — SpeechAnalyzer rejected the format")
    }

    @Test func compressInPlace_replacesAtSameURL() async throws {
        guard let fixture = fixtureURL() else {
            Issue.record("Fixture missing")
            return
        }
        // Copy fixture to a temp file so we can compress without touching the bundle.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("scratch-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.copyItem(at: fixture, to: scratch)

        let sizeBefore = try fileSize(scratch)
        try await AudioCompressor.compressInPlace(at: scratch)
        let sizeAfter = try fileSize(scratch)

        #expect(sizeAfter < sizeBefore / 5, "In-place compression didn't shrink the file enough")
        #expect(FileManager.default.fileExists(atPath: scratch.path), "Source URL gone after compressInPlace")

        // Decodes cleanly.
        let readback = try AVAudioFile(forReading: scratch)
        #expect(readback.length > 0)
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? Int64) ?? Int64((attrs[.size] as? Int) ?? 0)
    }
}

private final class BundleAnchor {}
