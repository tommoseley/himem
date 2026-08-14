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


    // MARK: - The window (behavioural), over `RenderedBench.compose`
    //
    // **Re-pointed 2026-08-10 when `BenchLensClips` was deleted.** F36's
    // predicate now lives in `RenderedBench.compose`, and under F37 it decides
    // which SESSIONS are admitted rather than which CLIPS survive. The
    // invariants below are unchanged — they were always about outcomes, not
    // about which function produced them.
    //
    // Three cases that used to live here are NOT reproduced, because
    // `RenderedBenchTests` already asserts them behaviourally and duplicating
    // them would inflate the count without adding coverage:
    //   aSessionIsNotSplitAcrossLenses      -> aSessionIsNotSplitAcrossLensesEvenAcrossKinds
    //   openedClipStaysNewWhileItsSessionIsOpen -> aReviewedItemStaysWhileItsSessionCouldStillGrow
    //   onceTheWindowPassesTheReviewedClipLeaves -> onceTheWindowPassesTheReviewedItemLeaves
    // Checked by reading each, not assumed from the names.

    /// An unseen clip is admitted regardless of age — `!reviewed` is the
    /// first half of the predicate and the window must not override it.
    @Test func unseenClipsAreAdmittedAtAnyAge() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let old = Self.item(t)
        let bench = RenderedBench.compose(
            allItems: [old], reviewedIds: [], hideReviewed: true,
            now: t.addingTimeInterval(365 * 24 * 3600)
        )
        #expect(bench.count == 1)
    }

    /// **The bulk trigger, covered by the same predicate.**
    /// `markSessionReviewed` marks every clip in an opened session — including
    /// ones never individually looked at. Because the rule is at the lens
    /// rather than at a trigger, that path is covered by construction: every
    /// review writer lands in the one `reviewedIds` set `compose` reads.
    ///
    /// Under F37 this is stronger than it was. The session is admitted or
    /// refused whole, so a bulk mark can no longer leave a sitting straddling
    /// two lenses even in principle.
    @Test func bulkSessionMarkDoesNotEjectAnOpenSession() {
        let t = Date(timeIntervalSince1970: 1_785_000_000)
        let members = (0..<5).map { i in Self.item(t.addingTimeInterval(Double(i) * 60)) }
        let bench = RenderedBench.compose(
            allItems: members, reviewedIds: Set(members.map(\.id)), hideReviewed: true,
            now: t.addingTimeInterval(6 * 60)
        )
        #expect(bench.count == 5, "the bulk mark ejected clips whose session is still open")
    }

    /// All shows everything — the window is a New-lens concept only.
    @Test func theAllLensIsUnaffectedByTheWindow() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let seen = Self.item(t)
        let unseen = Self.item(t)
        let bench = RenderedBench.compose(
            allItems: [seen, unseen], reviewedIds: [seen.id], hideReviewed: false,
            now: t.addingTimeInterval(999_999)
        )
        #expect(bench.count == 2)
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

    static func item(_ at: Date) -> BenchClipItem {
        BenchClipItem(id: UUID(), kind: .voice, capturedAt: at, rollGroupId: nil)
    }

    // MARK: - Caller guards

    /// The lens must read the grouper's threshold, never its own copy —
    /// two numbers is how the lens and the grouper drift apart again.
    ///
    /// Re-anchored on `RenderedBench.compose` when `BenchLensClips` was
    /// deleted. The consequence recorded at the constant is unchanged:
    /// retuning the grouper also retunes how long a session lingers in New.
    @Test func lensReadsTheGroupersThresholdNotItsOwn() throws {
        let src = try Self.source("MemoryStream/Services/Storage/RenderedBench.swift")
        // Anchored on the lens block itself, NOT on `static func compose(`.
        // `blockBody` counts BRACES, and `compose`'s signature now carries a
        // closure default (`reviewedAt: (UUID) -> Date? = { _ in nil }`) whose
        // braces open and close on one line — so anchoring on the signature
        // returned that single line as the "body". It failed loudly here, but
        // the same trap can pass VACUOUSLY when the needle happens to sit on
        // the terminating line. Same hazard the `callArguments` helper was
        // written for and which died with the 2b-ii revert.
        let body = try Self.blockBody(startingAtLineContaining: "if hideReviewed {", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("ClipSessionGrouper.sessionTimeWindowSeconds"),
                """
                `RenderedBench.compose` does not read \
                `ClipSessionGrouper.sessionTimeWindowSeconds`, so the lens and the grouper \
                have separate notions of "still in play". Body was:
                \(body)
                """)
        // A literal duration in the lens is the duplication this forbids.
        #expect(code.contains("10 * 60") == false,
                "`RenderedBench.compose` restates the idle-gap threshold instead of reading it.")
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
        static func compose(
            static let window: TimeInterval = 10 * 60
        }
        """
        #expect(Self.codeOnly(offending).contains("10 * 60"))
        #expect(Self.codeOnly(offending).contains("sessionTimeWindowSeconds") == false)
    }

    @Test func scanner_acceptsALensThatReadsTheGrouper() {
        let fixed = """
        static func compose(
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
