import Testing
import Foundation
@testable import HiMem

/// Money tests for the iOS-26 SpeechAnalyzer + SpeechTranscriber path.
///
/// The pre-migration `SFSpeechRecognizer` had a ~60-second utterance-
/// boundary cap. SpeechService used to work around it by re-spawning a
/// new recognition task on every `isFinal` callback (a brittle pattern
/// that occasionally lost the tail-end of a clip). The migration to
/// SpeechAnalyzer eliminates the ceiling entirely. These tests lock in
/// that regression — feed a ~120-second audio file through the engine
/// and assert it transcribes content from beyond the old 60s ceiling.
///
/// **Skipped when the on-device model isn't installed.** Asset download
/// is environment-dependent (locale / network / clean simulator). The
/// test logs and skips so CI doesn't fail on a fresh simulator that
/// hasn't pulled the model yet.
struct TranscriptionServiceLongFormTests {

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

    @Test func transcribe_longClip_coversBeyondSFSpeechRecognizerCeiling() async throws {
        guard let url = fixtureURL() else {
            Issue.record("Test fixture long-speech-90s.caf missing from MemoryStreamTests bundle")
            return
        }

        // Skip if the model isn't installed locally — asset download is
        // environment-dependent and orthogonal to what we're testing.
        guard await TranscriptionService.shared.modelIsInstalled(for: .current) else {
            print("[Test] skipping long-form test — speech model not installed for current locale")
            return
        }

        let result = await TranscriptionService.shared.transcribe(audioURL: url)

        // Money assertions — these would fail on the old SFSpeechRecognizer
        // path because it would have truncated the transcript at the ~60s
        // utterance boundary unless the multi-pass workaround was active.
        #expect(
            result.fileDurationSeconds > 100,
            "Fixture should be >100s — actual: \(result.fileDurationSeconds)s. Regenerate via the test plan in docs."
        )
        #expect(
            result.coverageSeconds > 60,
            "Coverage \(result.coverageSeconds)s did not pass the old 60s ceiling — possible truncation regression"
        )
        #expect(
            !result.text.isEmpty,
            "Empty transcript on a non-empty audio file"
        )
        // The fixture text mentions things from across the duration.
        // "morning glories" is around the 80s mark and is rare enough not
        // to false-positive elsewhere.
        let lower = result.text.lowercased()
        #expect(
            lower.contains("morning") || lower.contains("garden") || lower.contains("garlic"),
            "Transcript missing expected mid/late content. Got: \(result.text.prefix(500))"
        )
    }
}

/// Anchor class so `Bundle(for:)` resolves to the test bundle. Bundle
/// lookup needs a class context; XCTest used to provide one, Swift
/// Testing doesn't, so we make our own.
private final class BundleAnchor {}
