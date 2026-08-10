import Testing
import Foundation
@testable import HiMem

/// **F35 · the New lens described one set and rendered another.**
///
/// Found on device 2026-08-02. The header read
/// *"19 new clips · 1 session · Apr 28 2:02 PM – today 5:43 PM"* above a
/// single rendered clip, and the same transcript appeared three times in
/// one viewport.
///
/// **(a) Three numbers, two sets.** `headerTitle` counted `benchClips`
/// (unfiltered) and `headerSubtitle` took its time range from `benchClips`
/// (unfiltered), while its session count came from `sessions` — which
/// `computeSessions` derives from `benchClips.filter { !$0.reviewed }` on
/// the New lens. Each number was true of a different set; together they
/// claimed a three-month session that never existed.
///
/// **The grouper was NOT the fault, and this is the load-bearing part.**
/// `ClipSessionGrouper` applies its 10-minute idle gap correctly; it simply
/// never saw the April clips, because the filter removed them before
/// grouping. "1 session" was the right answer for the set it was given.
/// The reported finding was "the idle-gap grouper isn't splitting" —
/// acting on that would have modified a correct component while the real
/// defect survived. Enumeration before action (CLAUDE.md § Don't Go
/// Looking for Zebras).
///
/// **The word "new" lied independently of the arithmetic.** The header sits
/// directly under the New chip, where New means *unseen*; a count including
/// 18 reviewed clips is an Honest-Label failure, not a rounding error.
/// Ruled 2026-08-02: **the header describes the lens, filtered** — one set,
/// one source.
///
/// **(b) Two views fetched the same row.** `SessionListView` pulls
/// zero-edge **voice** refs into its session cards; `ClipsTabView.loadUnplaced`
/// pulled zero-edge refs of **every** type into the sibling stack below.
/// Neither excluded the other, so an unreviewed zero-edge voice ref rendered
/// in both — and expanding the row repeated the transcript its own collapsed
/// header had already shown. Ruled: exclude voice from `loadUnplaced`, so
/// the session card owns voice; logged against C2 (one owner for "what is on
/// the bench") as the structural answer.
///
/// *Confirmed before shipping (b), because the ruling required it:*
/// `unplacedRefs` has exactly one consumer, `newFilterContent`. The
/// Unconnected lens renders `UnconnectedListView` and All renders
/// `FlatClipsListView`, both from independent sources — so excluding voice
/// here **cannot** hide an unconnected voice clip from the cleanup lens.
/// The fetch is already New-lens-scoped by construction.
@Suite struct ClipsNewLensCoherenceTests {


    // MARK: - (a) The lens set is one set (behavioural)

    /// The pure helper the header and the grouper must both read.
    ///
    /// **Updated at F36 (2026-08-02) — the meaning moved, not the phrasing.**
    /// `forLens` gained a `now`, because a reviewed clip is now admitted
    /// while its session is still open. These assertions still pin what they
    /// always pinned — that a reviewed clip is dropped — so they pass a
    /// `now` past the window, which is the state they were implicitly
    /// written against.
    @Test func lensClips_onNewLens_dropsReviewed() {
        let reviewed = Self.clip(reviewed: true)
        let unseen = Self.clip(reviewed: false)
        let lens = BenchLensClips.forLens(benchClips: [reviewed, unseen], hideReviewed: true,
                                          now: Self.afterTheWindow)
        #expect(lens.count == 1)
        #expect(lens.first?.clipId == unseen.clipId)
    }

    /// On All, nothing is dropped — one helper serves both lenses, so there
    /// is one definition of "what this lens shows" rather than two.
    @Test func lensClips_onAllLens_keepsEverything() {
        let clips = [Self.clip(reviewed: true), Self.clip(reviewed: false)]
        #expect(BenchLensClips.forLens(benchClips: clips, hideReviewed: false,
                                       now: Self.afterTheWindow).count == 2)
    }

    /// **The device case, as data.** 19 bench clips, 18 already reviewed,
    /// spanning three months. The lens shows one — so the header must say
    /// one, and its span must not reach back to April.
    @Test func theDeviceCase_headerDescribesWhatIsRendered() {
        let april = Date(timeIntervalSince1970: 1_777_000_000)
        let today = april.addingTimeInterval(90 * 24 * 3600)
        var clips = (0..<18).map { i in
            Self.clip(reviewed: true, capturedAt: april.addingTimeInterval(Double(i) * 3600))
        }
        clips.append(Self.clip(reviewed: false, capturedAt: today))

        let lens = BenchLensClips.forLens(benchClips: clips, hideReviewed: true, now: today)
        #expect(lens.count == 1, "the lens renders one clip; the header counted \(clips.count)")

        let span = lens.map(\.capturedAt)
        #expect(span.min() == today, "the subtitle span reached back to a clip the lens does not show")
        #expect(span.max() == today)
    }

    /// Bound the other side: a helper that returned nothing would pass the
    /// filtering tests above while emptying the lens entirely.
    @Test func lensClips_keepsEveryUnseenClip() {
        let unseen = (0..<5).map { _ in Self.clip(reviewed: false) }
        #expect(BenchLensClips.forLens(benchClips: unseen, hideReviewed: true,
                                       now: Self.afterTheWindow).count == 5)
    }

    // MARK: - (a) Caller guard — the header must not reach past the lens

    /// The helper being right says nothing about whether the header reads
    /// it. This is the defect: both header properties bound `benchClips`
    /// directly while the session count came from the filtered set.
    @Test func headerReadsTheLensSetNotTheRawBench() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        for property in ["private var headerTitle: String {", "private var headerSubtitle: String {"] {
            let body = try Self.blockBody(startingAtLineContaining: property, in: src)
            let code = Self.codeOnly(body)
            #expect(code.contains("benchClips") == false,
                    """
                    \(property) reads `benchClips` directly, which is unfiltered — so on the \
                    New lens it describes a different set than the one rendered. It must read \
                    the lens set. Body was:
                    \(body)
                    """)
            #expect(code.contains("lensClips"),
                    "\(property) does not read the lens set.")
        }
    }

    // MARK: - (b) Caller guard — one owner per media type on the bench

    /// `loadUnplaced` must not fetch voice: `SessionListView` already owns
    /// zero-edge voice refs via `fetchZeroEdgeVoiceRefs`, and two views
    /// fetching the same row is what put one transcript on screen twice.
    @Test func unplacedStackDoesNotFetchVoice() throws {
        let src = try Self.source("MemoryStream/Views/ClipsTabView.swift")
        let body = try Self.blockBody(startingAtLineContaining: "private func loadUnplaced()", in: src)
        let code = Self.codeOnly(body)
        #expect(code.contains("mediaType != %@"),
                """
                `loadUnplaced` fetches every media type, including voice — which \
                `SessionListView.fetchZeroEdgeVoiceRefs` already renders as session \
                cards. The same clip lands in both stacks. Body was:
                \(body)
                """)
        #expect(code.contains("MediaType.voice.rawValue"),
                "`loadUnplaced` does not name the type it excludes.")
    }

    /// Self-test: the scanner must flag the shipped predicate…
    @Test func scanner_flagsAnUnfilteredUnplacedFetch() {
        let shipped = """
        private func loadUnplaced() {
            req.predicate = NSPredicate(format: "edges.@count == 0 AND recycledAt == nil")
        }
        """
        #expect(Self.codeOnly(shipped).contains("mediaType != %@") == false)
    }

    /// …and accept the fixed one, including when the exclusion is only
    /// described in a comment (which would not filter anything).
    @Test func scanner_ignoresAnExclusionThatIsOnlyProse() {
        let prose = """
        private func loadUnplaced() {
            // voice is excluded — mediaType != %@ — see SessionListView
            req.predicate = NSPredicate(format: "edges.@count == 0 AND recycledAt == nil")
        }
        """
        #expect(Self.codeOnly(prose).contains("mediaType != %@") == false,
                "a comment is not a predicate")
    }


    // MARK: - Fixtures

    /// Far enough past every fixture's `capturedAt` that no session is still
    /// open — the F35 assertions are about filtering, not about F36's window.
    static let afterTheWindow = Date(timeIntervalSince1970: 1_785_000_000)
        .addingTimeInterval(365 * 24 * 3600)

    static func clip(reviewed: Bool, capturedAt: Date = Date(timeIntervalSince1970: 1_785_000_000)) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 10,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "phone",
            audioFilename: "f35-\(UUID().uuidString).m4a",
            transcriptionAttempted: true,
            rollGroupId: nil,
            reviewed: reviewed
        )
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
