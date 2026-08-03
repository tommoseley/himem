import Testing
import Foundation
@testable import HiMem

/// **F36 · a clip left New while it could still join a session.**
///
/// Observed on device 2026-08-02: opening a clip moved it to Unconnected
/// immediately, and a header reading "1 new clip" opened a session
/// containing two — one New, one already reclassified. The lens and the
/// session disagreed because `reviewed` flips on open while session
/// membership is time-based.
///
/// **Ruled:** on Done a clip stays New while it would still group into an
/// existing session. `reviewed` still records "opened by you"; the New lens
/// admits `!reviewed || stillInPlay`, so the lens and the grouper share one
/// notion of "still in play".
///
/// **Session-relative, not clip-relative (ruled after a worked example).**
/// With a clip-relative window, clip A at T and clip B at T+9 are one
/// session but split across New and Unconnected at T+11 — reproducing the
/// exact symptom. Only a session-relative window makes the lens and the
/// grouper agree, because a session extends as clips join it.
///
/// **One threshold, not two.** `ClipSessionGrouper.sessionTimeWindowSeconds`
/// is already the single definition; the lens reads it rather than
/// restating it. Consequence, stated at the constant: retuning the grouper
/// now also retunes how long clips linger in New.
@Suite struct ClipsStillInPlayTests {


    // MARK: - The window (behavioural)

    /// **The worked example that decided session-relative over
    /// clip-relative.** A at T, B at T+9 are ONE session. At T+11 a
    /// clip-relative window ages A out while B survives — the reported
    /// symptom, a session split across two lenses. Session-relative keeps
    /// them together, because the session's window runs from ITS latest
    /// clip.
    @Test func aSessionIsNotSplitAcrossLenses() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let a = Self.clip(reviewed: true, capturedAt: t)
        let b = Self.clip(reviewed: true, capturedAt: t.addingTimeInterval(9 * 60))
        let lens = BenchLensClips.forLens(
            benchClips: [a, b], hideReviewed: true,
            now: t.addingTimeInterval(11 * 60)
        )
        #expect(lens.count == 2, "the session was split — A aged out while B did not")
    }

    /// Opening a clip no longer ejects it: reviewed, but its session is
    /// still open, so New keeps it.
    @Test func openedClipStaysNewWhileItsSessionIsOpen() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let opened = Self.clip(reviewed: true, capturedAt: t)
        let lens = BenchLensClips.forLens(
            benchClips: [opened], hideReviewed: true,
            now: t.addingTimeInterval(60)
        )
        #expect(lens.count == 1)
    }

    /// **The ceiling.** Once the window has passed a reviewed clip DOES
    /// leave — a predicate that never reclassified would pass every test
    /// above while retiring the New lens entirely.
    @Test func onceTheWindowPassesTheReviewedClipLeaves() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let opened = Self.clip(reviewed: true, capturedAt: t)
        let lens = BenchLensClips.forLens(
            benchClips: [opened], hideReviewed: true,
            now: t.addingTimeInterval(ClipSessionGrouper.sessionTimeWindowSeconds + 1)
        )
        #expect(lens.isEmpty)
    }

    /// An unseen clip is admitted regardless of age — `!reviewed` is the
    /// first half of the predicate and the window must not override it.
    @Test func unseenClipsAreAdmittedAtAnyAge() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let old = Self.clip(reviewed: false, capturedAt: t)
        let lens = BenchLensClips.forLens(
            benchClips: [old], hideReviewed: true,
            now: t.addingTimeInterval(365 * 24 * 3600)
        )
        #expect(lens.count == 1)
    }

    /// **The bulk trigger, covered by the same predicate.** `markSessionReviewed`
    /// marks every clip in an opened session — including ones never
    /// individually looked at. Because the fix is at the lens rather than at
    /// a trigger, that path is covered by construction: all four writers land
    /// in `benchClips[].reviewed`, which this reads leniently.
    @Test func bulkSessionMarkDoesNotEjectAnOpenSession() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let members = (0..<5).map { i in
            Self.clip(reviewed: true, capturedAt: t.addingTimeInterval(Double(i) * 60))
        }
        let lens = BenchLensClips.forLens(
            benchClips: members, hideReviewed: true,
            now: t.addingTimeInterval(6 * 60)
        )
        #expect(lens.count == 5, "the bulk mark ejected clips whose session is still open")
    }

    /// All shows everything — the window is a New-lens concept only.
    @Test func theAllLensIsUnaffectedByTheWindow() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let clips = [Self.clip(reviewed: true, capturedAt: t), Self.clip(reviewed: false, capturedAt: t)]
        let lens = BenchLensClips.forLens(
            benchClips: clips, hideReviewed: false,
            now: t.addingTimeInterval(999_999)
        )
        #expect(lens.count == 2)
    }

    // MARK: - Copy (the wording IS the promise)

    @Test func theUnconnectedExplanationIsTheRuledLine() {
        #expect(ClipsLensCopy.unconnectedExplanation
                == "Not part of any memory yet. They stay here until you add them to one.")
        // The reassurance clause is what stops a silent category change
        // reading as a loss — its absence is the defect, not a style change.
        #expect(ClipsLensCopy.unconnectedExplanation.contains("stay here"))
        // "connected" is our architecture word (F7g) and must not surface.
        #expect(ClipsLensCopy.unconnectedExplanation.lowercased().contains("connect") == false)
    }

    // MARK: - Fixtures

    static func clip(reviewed: Bool, capturedAt: Date) -> InboxClip {
        InboxClip(
            clipId: UUID(), capturedAt: capturedAt, duration: 10, transcript: "",
            latitude: nil, longitude: nil, source: "phone",
            audioFilename: "f36-\(UUID().uuidString).m4a",
            transcriptionAttempted: true, rollGroupId: nil, reviewed: reviewed
        )
    }

    // MARK: - Caller guards

    /// The lens must read the grouper's threshold, never its own copy —
    /// two numbers is how the lens and the grouper drift apart again.
    @Test func lensReadsTheGroupersThresholdNotItsOwn() throws {
        let src = try Self.source("MemoryStream/Services/Storage/ClipSessionGrouper.swift")
        let body = try Self.blockBody(startingAtLineContaining: "enum BenchLensClips", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("sessionTimeWindowSeconds"),
                """
                `BenchLensClips` does not read `ClipSessionGrouper.sessionTimeWindowSeconds`, \
                so the lens and the grouper have separate notions of "still in play". Body was:
                \(body)
                """)
        // A literal duration in the lens is the duplication this forbids.
        #expect(code.contains("10 * 60") == false,
                "`BenchLensClips` restates the idle-gap threshold instead of reading it.")
    }

    /// The Unconnected lens must explain the state, not just label the
    /// filter — a silent category change with no explanation is the
    /// vocabulary-failure class.
    @Test func unconnectedLensExplainsTheState() throws {
        let src = try Self.source("MemoryStream/Views/ClipsTabView.swift")
        let code = Self.codeOnly(src)
        #expect(code.contains("ClipsLensCopy.unconnectedExplanation"),
                "The Unconnected lens does not render the ruled explanation.")
        #expect(code.contains("\"Clips not connected to any memory.\"") == false,
                """
                The retired filter-label copy is still present. It read as a filter label \
                rather than an explanation, which is why the state was not legible.
                """)
    }

    // MARK: - Scanner self-tests

    @Test func scanner_flagsALensWithItsOwnThreshold() {
        let offending = """
        enum BenchLensClips {
            static let window: TimeInterval = 10 * 60
        }
        """
        #expect(Self.codeOnly(offending).contains("10 * 60"))
        #expect(Self.codeOnly(offending).contains("sessionTimeWindowSeconds") == false)
    }

    @Test func scanner_acceptsALensThatReadsTheGrouper() {
        let fixed = """
        enum BenchLensClips {
            let w = ClipSessionGrouper.sessionTimeWindowSeconds
        }
        """
        #expect(Self.codeOnly(fixed).contains("sessionTimeWindowSeconds"))
        #expect(Self.codeOnly(fixed).contains("10 * 60") == false)
    }

    // MARK: - Source access

    static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<marker.lowerBound])
            }
            .joined(separator: "\n")
    }

    static func blockBody(startingAtLineContaining needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.blockNotFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.blockNotFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), blockNotFound(String) }
}
