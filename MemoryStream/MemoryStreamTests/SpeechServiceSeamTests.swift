import Testing
import Foundation
@testable import HiMem

/// **§5 · the line through `SpeechService`, drawn before the deletion that
/// follows it** (Tom, 2026-09-18).
///
/// The service runs one engine for two surfaces with opposite needs:
///
/// - **voice search** wants the WORDS — it reads `transcribedText` live and has
///   never read `lastRecordingPath`;
/// - **the voice composer** wants the FILE — `lastRecordingPath` exists for it.
///
/// §5.4 retires the composer. Drawing the line now turns that into an
/// *excision* rather than a refactor-performed-mid-deletion, which is the whole
/// reason this landed first.
///
/// **What makes the seam provable rather than argued** is the reader count:
/// `lastRecordingPath` is read in exactly one file, and it is the file being
/// deleted. These tests pin that, because it is the claim §5.4 rests on — and a
/// claim about "every reader" is exactly the shape that a `head`-bounded grep
/// gets wrong (CLAUDE.md § Measurement Discipline).
@Suite struct SpeechServiceSeamTests {

    enum GateFailure: Error { case noSourceWalked(String), sourceNotFound(String) }

    private static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // MemoryStreamTests/
        .deletingLastPathComponent()      // project dir
        .appendingPathComponent("MemoryStream")

    /// The file side of the seam — the only surface allowed to keep audio.
    private static let composer = "Views/Input/VoiceCaptureScreen.swift"

    // MARK: - The seam

    /// **THE LOAD-BEARING ASSERTION.** If a second file starts reading
    /// `lastRecordingPath`, §5.4 stops being an excision — the file-writing half
    /// would have grown a consumer outside the surface being deleted.
    @Test("lastRecordingPath is read only by the composer")
    func theFileSideHasOneConsumer() throws {
        let readers = try Self.filesMentioning("lastRecordingPath")
            .filter { $0 != "Services/AI/SpeechService.swift" }
        #expect(readers == [Self.composer], """
            `lastRecordingPath` is read outside the composer. The §5 seam assumed \
            exactly one consumer, and §5.4's deletion assumes the file-writing \
            half dies with it. Readers found:
            \(readers.joined(separator: "\n"))
            """)
    }

    /// Voice search takes the words and leaves nothing behind. Before §5 it ran
    /// the same engine and silently wrote a `.caf` per search that nothing ever
    /// read.
    @Test("the search surface never retains audio")
    func searchDoesNotRetainAudio() throws {
        let src = try Self.source("Views/Search/VoiceSearchView.swift")
        #expect(src.contains("startRecording(retainingAudio: false)"),
                "voice search must ask for words only — it reads no file")
        #expect(!src.contains("retainingAudio: true)"),
                "voice search has no reader for the audio it would keep")
    }

    /// **No default, and that is the mechanism.** A caller that says nothing
    /// would inherit file-writing, which is how a words-only surface ends up
    /// leaving audio on disk — the defect §5 found in voice search. The
    /// compiler enforces the choice; this pins that the enforcement stays.
    @Test("startRecording forces every caller to state its intent")
    func theParameterHasNoDefault() throws {
        let src = try Self.source("Services/AI/SpeechService.swift")
        #expect(src.contains("func startRecording(retainingAudio: Bool) {"),
                "a default on `retainingAudio` removes the compiler's forcing function")
        #expect(!src.contains("retainingAudio: Bool = "),
                "`retainingAudio` acquired a default — callers can now inherit file-writing silently")
    }

    // MARK: - Self-tests — the matcher must be able to fail, and survive junk

    @Test("the matcher flags a reader outside the composer")
    func matcherFlagsAnOutsideReader() {
        let sources = [
            "Views/Input/VoiceCaptureScreen.swift": "speechService.lastRecordingPath",
            "Views/Journal/Somewhere.swift": "let p = speechService.lastRecordingPath",
        ]
        let hits = Self.matches("lastRecordingPath", in: sources).filter { $0 != "Services/AI/SpeechService.swift" }
        #expect(hits.count == 2)
        #expect(hits != [Self.composer])
    }

    @Test("the matcher accepts the clean shape")
    func matcherAcceptsTheCleanShape() {
        let sources = [
            "Views/Input/VoiceCaptureScreen.swift": "speechService.lastRecordingPath",
            "Views/Search/VoiceSearchView.swift": "speechService.transcribedText",
        ]
        #expect(Self.matches("lastRecordingPath", in: sources) == [Self.composer])
    }

    /// The shape that produced a false positive on the first run: prose about
    /// the symbol is not a use of it.
    @Test("the matcher ignores the symbol in comments")
    func matcherIgnoresComments() {
        let sources = [
            "Views/Input/VoiceCaptureScreen.swift": "speechService.lastRecordingPath",
            "Views/Search/VoiceSearchView.swift":
                "            // never reads `lastRecordingPath`\n            doSomething()",
        ]
        #expect(Self.matches("lastRecordingPath", in: sources) == [Self.composer])
    }

    @Test("the matcher survives degenerate input")
    func matcherSurvivesDegenerateInput() {
        #expect(Self.matches("lastRecordingPath", in: [:]).isEmpty)
        #expect(Self.matches("lastRecordingPath", in: ["a.swift": ""]).isEmpty)
        #expect(Self.matches("lastRecordingPath", in: ["a.swift": "lastRecordingPat"]).isEmpty)
    }

    // MARK: - Scanner

    /// Membership only — no offsets, so there is no slice to invert
    /// (the 2026-08-25 trap).
    ///
    /// **Comment lines are skipped, and this guard found out why on its own
    /// first run.** It reported `VoiceSearchView` as a reader of
    /// `lastRecordingPath` — because the comment added there, explaining that
    /// the surface has never read it, contains the word. A scanner that matches
    /// its own documentation measures prose rather than code, and would have
    /// made the seam unprovable by describing it. Same idiom as
    /// `theDispatcherHasNoProductionCaller`.
    private static func matches(_ needle: String, in sources: [String: String]) -> [String] {
        sources.compactMap { path, text in
            let isCode = text.split(separator: "\n").contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//") else { return false }
                return t.contains(needle)
            }
            return isCode ? path : nil
        }.sorted()
    }

    /// Walks the whole app target. Throws if it reaches no source — a
    /// completeness claim cannot rest on a walk that inspected nothing, and
    /// "one reader" and "zero files scanned" must not read the same.
    private static func filesMentioning(_ needle: String) throws -> [String] {
        guard let walker = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            throw GateFailure.sourceNotFound(appRoot.path)
        }
        var sources: [String: String] = [:]
        // Consume the URL the enumerator hands us rather than retyping a path.
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = url.path.components(separatedBy: "/MemoryStream/MemoryStream/").last ?? url.path
            sources[rel] = text
        }
        guard !sources.isEmpty else { throw GateFailure.noSourceWalked(appRoot.path) }
        return matches(needle, in: sources)
    }

    private static func source(_ relative: String) throws -> String {
        let url = appRoot.appendingPathComponent(relative)
        guard let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty else {
            throw GateFailure.sourceNotFound(url.path)
        }
        return s
    }
}
