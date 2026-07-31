import Testing
import AVFoundation
import Foundation
@testable import HiMem

/// Capture-gain P0 (2026-07-15) + F18 (2026-07-31) — the session-mode invariant,
/// for **every** capture surface.
///
/// Capture MUST use a gain-applying mode. `.measurement` minimizes system input
/// processing including input GAIN, which left the watch mic at ~-40 dBFS —
/// silent, untranscribable clips (the loud-clip dogfood had `in_peak` pinned
/// ~0.01). `.default` applies gain and resolves the input to mono. Real input
/// energy needs mic hardware to measure — the `[Amp]` transcode log is that
/// device-side check. These are the deterministic guards.
///
/// **Why there are now two tests, not one.** The 2026-07-15 fix gave the watch
/// an owner (`recordMode`) and this suite. The phone kept a hardcoded
/// `.measurement` literal in `SpeechService`, justified by a comment claiming
/// *"the phone tolerates `.measurement` because its mic is hotter."* It does
/// not: on iPad the waveform never moves and voice capture is dead, and on
/// iPhone every recording was quieter than it should be. A constant-value test
/// alone could never have caught that, because the phone was not reading the
/// constant. So the second test asserts the **literal is absent from production
/// source** — the invariant is "one owner", not merely "the owner is correct".
@Suite
struct CaptureAudioSessionConfigTests {

    @Test func recordMode_appliesInputGain_notMeasurement() {
        #expect(CaptureAudioSessionConfig.recordMode != .measurement,
                "capture must not use .measurement — it suppresses input gain (silent clips, capture-gain P0)")
        #expect(CaptureAudioSessionConfig.recordMode == .default,
                "capture records in .default (applies input gain, resolves to mono)")
    }

    /// THE F18 GUARD. No production file may hardcode the session mode — every
    /// capture path reads `CaptureAudioSessionConfig.recordMode`. Without this,
    /// a second surface can quietly reintroduce `.measurement` and the
    /// constant-value test above will still pass, which is exactly how this
    /// survived from 2026-07-15 to 2026-07-31.
    @Test func noProductionSiteHardcodesTheSessionMode() throws {
        let offenders = try Self.sourcesHardcodingMode()
        #expect(
            offenders.isEmpty,
            """
            Capture session mode is hardcoded instead of reading \
            `CaptureAudioSessionConfig.recordMode`:
            \(offenders.map { "  • \($0)" }.joined(separator: "\n"))

            Read the shared constant. A per-surface literal is how the watch fix \
            failed to reach the phone for two weeks.
            """
        )
    }

    /// Guards the guard — a scanner that matches nothing would report a clean
    /// codebase forever, and one that matches everything is just noise.
    @Test func scannerFlagsCaptureLiteralsAndIgnoresTheRest() {
        // The real offender's shape: a wrapped capture call.
        #expect(Self.isHardcoding("""
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers]
        )
        """), "a multi-line capture call is the shape that was missed")

        #expect(Self.isHardcoding("setCategory(.playAndRecord, mode: .voiceChat)"))

        #expect(!Self.isHardcoding("setCategory(.record, mode: CaptureAudioSessionConfig.recordMode, options: [])"),
                "reading the owner is the correct form")
        #expect(!Self.isHardcoding("try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)"),
                "playback sets its own mode — input gain is not a playback concern")
        #expect(!Self.isHardcoding("/// `.measurement` suppresses input gain — see the type doc"),
                "prose naming the mode is not a call site")
    }

    // MARK: - Scanner

    /// True when a **capture** `setCategory` call passes a literal `mode:`
    /// instead of reading the shared constant.
    ///
    /// Two scoping rules, both learned by getting this wrong first (2026-07-31):
    ///   * **Capture only.** `.playback` sessions legitimately set their own
    ///     mode — input gain is not a playback concern. A first version flagged
    ///     three playback sites and would have forced them to read a capture
    ///     constant that means nothing to them.
    ///   * **Whole call, not one line.** The real offender spanned five lines,
    ///     so a line-scoped match missed the only site that mattered while
    ///     reporting three that didn't. Scan the call.
    static func isHardcoding(_ call: String) -> Bool {
        let body = call.replacingOccurrences(of: "\n", with: " ")
        guard body.contains("setCategory") else { return false }
        // Capture categories only.
        guard body.contains(".record") || body.contains(".playAndRecord") else { return false }
        return body.range(of: #"mode:\s*\."#, options: .regularExpression) != nil
    }

    static func sourcesHardcodingMode() throws -> [String] {
        var out: [String] = []
        let root = try Self.sourceRoot()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return out }
        for case let url as URL in walker where url.pathExtension == "swift" {
            // The tests themselves legitimately contain literal examples.
            guard !url.path.contains("Tests") else { continue }
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = src.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), line.contains("setCategory") else { continue }
                // A call may wrap; take enough lines to close it.
                let call = lines[i..<min(i + 6, lines.count)].joined(separator: " ")
                if isHardcoding(call) { out.append("\(url.lastPathComponent):\(i + 1)") }
            }
        }
        return out
    }

    /// The project directory — parent of `MemoryStreamTests`, so the scan covers
    /// the phone app, `Shared/`, and the watch targets alike. `#filePath` is the
    /// only anchor available: the test bundle carries no sources.
    static func sourceRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // …/MemoryStreamTests
            .deletingLastPathComponent()   // …/MemoryStream (project dir)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw Failure.rootNotFound(root.path)
        }
        return root
    }

    enum Failure: Error { case rootNotFound(String) }
}
