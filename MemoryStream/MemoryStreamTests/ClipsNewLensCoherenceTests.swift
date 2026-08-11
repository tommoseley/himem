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

    /// The one definition of "what this lens shows".
    ///
    /// **Updated at F36 (2026-08-02) — the meaning moved, not the phrasing.**
    /// A reviewed clip is now admitted while its session is still open, so
    /// these pass a `now` past the window, which is the state they were
    /// implicitly written against.
    ///
    /// **Re-pointed 2026-08-10:** `BenchLensClips` is deleted and the lens
    /// lives in `RenderedBench.compose`. Under F37 it admits whole SESSIONS
    /// rather than surviving CLIPS — so these fixtures space their items past
    /// the idle gap, which keeps each item its own session and makes the
    /// item-level assertion these were written to make still the right one.
    @Test func lensClips_onNewLens_dropsReviewed() {
        let reviewed = Self.item(Self.longAgo)
        let unseen = Self.item(Self.longAgo.addingTimeInterval(3 * 3600))
        let bench = RenderedBench.compose(
            allItems: [reviewed, unseen], reviewedIds: [reviewed.id],
            hideReviewed: true, now: Self.afterTheWindow
        )
        #expect(bench.count == 1)
        #expect(bench.items.first?.id == unseen.id)
    }

    /// On All, nothing is dropped — one definition serves both lenses, so
    /// there is one answer to "what does this lens show" rather than two.
    @Test func lensClips_onAllLens_keepsEverything() {
        let a = Self.item(Self.longAgo)
        let b = Self.item(Self.longAgo.addingTimeInterval(3 * 3600))
        let bench = RenderedBench.compose(
            allItems: [a, b], reviewedIds: [a.id],
            hideReviewed: false, now: Self.afterTheWindow
        )
        #expect(bench.count == 2)
    }

    /// **The device case, as data.** 19 bench items, 18 already reviewed,
    /// spanning three months, each its own sitting. The lens shows one — so
    /// the header must say one, and its span must not reach back to April.
    ///
    /// This is the assertion the whole rebuild is for, and it is now checkable
    /// in the form the header actually reads: `count` and `capturedAts` come
    /// off one `items` array, so the "19 new clips · 1 session · Apr 28 –
    /// today" shape is no longer expressible.
    @Test func theDeviceCase_headerDescribesWhatIsRendered() {
        let april = Date(timeIntervalSince1970: 1_777_000_000)
        let today = april.addingTimeInterval(90 * 24 * 3600)
        let seen = (0..<18).map { i in Self.item(april.addingTimeInterval(Double(i) * 3600)) }
        let fresh = Self.item(today)

        let bench = RenderedBench.compose(
            allItems: seen + [fresh], reviewedIds: Set(seen.map(\.id)),
            hideReviewed: true, now: today
        )
        #expect(bench.count == 1, "the lens renders one clip; the header counted \(seen.count + 1)")

        let span = bench.items.map(\.capturedAt)
        #expect(span.min() == today, "the subtitle span reached back to a clip the lens does not show")
        #expect(span.max() == today)
    }

    /// Bound the other side: a lens that returned nothing would pass the
    /// filtering tests above while emptying New entirely.
    @Test func lensClips_keepsEveryUnseenClip() {
        let unseen = (0..<5).map { i in Self.item(Self.longAgo.addingTimeInterval(Double(i) * 3 * 3600)) }
        let bench = RenderedBench.compose(
            allItems: unseen, reviewedIds: [], hideReviewed: true, now: Self.afterTheWindow
        )
        #expect(bench.count == 5)
    }

    // MARK: - (a) Caller guard — the header must not reach past the lens

    /// The helper being right says nothing about whether the header reads
    /// it. This is the defect: both header properties bound `benchClips`
    /// directly while the session count came from the filtered set.
    ///
    /// **SUPERSEDED by `BenchCountAndProposalCopyTests
    /// .theHeaderAssemblesNoCountOfItsOwn`** (C2 step 2b-ii-c2), which is
    /// strictly stronger and was written as a verified red against this very
    /// header.
    ///
    /// This asserted the header reads `lensClips`. That was the right demand
    /// while the header assembled its own count — it named the *one correct*
    /// source among several. The successor forbids **every** raw source
    /// (`lensClips` included) and requires the number to come from the single
    /// drawn value, so the two are now contradictory by construction and the
    /// stronger one wins.
    ///
    /// Kept as the negative half rather than deleted: "must not read the raw
    /// bench" is still true, still this file's subject, and is the clause that
    /// actually failed on device — *"19 new clips · 1 session · Apr 28 –
    /// today"*, three numbers over two sets. The positive half moved.
    @Test func headerReadsNeitherTheRawBenchNorAnySetOfItsOwn() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        for property in ["private var headerTitle: String {", "private var headerSubtitle: String {"] {
            let body = try Self.blockBody(startingAtLineContaining: property, in: src)
            let code = Self.codeOnly(body)
            #expect(code.contains("benchClips") == false,
                    """
                    \(property) reads `benchClips` directly, which is unfiltered — so on the \
                    New lens it describes a different set than the one rendered. Body was:
                    \(body)
                    """)
            #expect(code.contains("drawn"),
                    """
                    \(property) does not read the drawn bench. Every number the header says \
                    must be a property of the ONE value the surface draws, or the count, the \
                    span and the session term can describe different sets again.
                    """)
        }
    }

    // MARK: - (c) Caller guard — review must stick regardless of backing

    /// **A session containing a materialized voice clip can never leave New.**
    ///
    /// Found 2026-08-10 while reporting C2 step 2b-ii-c2. Review state lives in
    /// two stores to match the two backings — `InboxClip.reviewed` on the
    /// device-local manifest row, and the ref-keyed `BenchClipReviewStore` for
    /// a materialized clip — and `BenchInventory` resolves both on the READ
    /// side. The WRITE side has no owner: each site open-codes the routing.
    ///
    /// `ClipEditorModal.onAppear` gets it right and says why (*"mark BOTH
    /// stores … so 'seen' sticks regardless of backing"*).
    /// `SessionListView.markSessionReviewed` does not: it calls
    /// `inbox.markReviewed(clipIds:)`, which walks `clips` and **silently
    /// no-ops on an id it has no row for**, and reaches
    /// `BenchClipReviewStore` only for media refs.
    ///
    /// So opening a session marks its manifest-backed clips and leaves its
    /// ref-backed ones unseen. On a mature bench that is most of them —
    /// `materializeAll` drains every transcribed row into a ref.
    ///
    /// **Under F37 this became a stuck session rather than a stale flag.**
    /// Admission is per-session now: a session is admitted whole while
    /// *anything* in it is unreviewed. A ref-backed clip that can never be
    /// marked keeps re-admitting its session forever — the user reads it,
    /// leaves, and finds it still sitting in New.
    ///
    /// It is the manifest-vs-ref asymmetry of premise 2, one layer up in the
    /// review path. `BenchReviewBackfillMigration`'s doc still asserts *"the
    /// open paths are correct — every one presents `ClipEditorModal`"*; the
    /// July 19 *"open the container → its contents are seen"* ruling added a
    /// second open path that bypasses the editor, and that comment did not
    /// follow it.
    ///
    /// Mechanical because the call site is `private` on a `View` and therefore
    /// unreachable — the form CLAUDE.md sanctions for exactly this case.
    /// `blockBody` throws on a missing anchor, so a rename fails loudly rather
    /// than letting this pass by matching nothing.
    @Test func openingASessionMarksVoiceReviewedInBothStores() throws {
        let src = try Self.source("MemoryStream/Views/Inbox/SessionListView.swift")
        let body = try Self.blockBody(
            startingAtLineContaining: "private func markSessionReviewed(", in: src
        )
        let code = Self.codeOnly(body)
        #expect(code.contains("BenchClipReviewWriter.markReviewed"),
                """
                `markSessionReviewed` routes review state by hand instead of through the \
                one owner. `InboxManifest.markReviewed` no-ops on an id it has no row for, \
                so a materialized (ref-backed) voice clip is never marked seen — and under \
                F37 its session re-admits to New forever. Body was:
                \(body)
                """)
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

    /// The fixtures' capture time — a year before `afterTheWindow`, so every
    /// session in this file is long closed and these assertions stay about
    /// filtering rather than about F36's window.
    static let longAgo = Date(timeIntervalSince1970: 1_785_000_000)

    /// Items rather than `InboxClip`s since `BenchLensClips` was deleted:
    /// `RenderedBench.compose` is media-agnostic and takes the value type.
    /// Callers space these past the idle gap when they want one item per
    /// session, because F37 admits whole sessions.
    static func item(_ at: Date) -> BenchClipItem {
        BenchClipItem(id: UUID(), kind: .voice, capturedAt: at, rollGroupId: nil)
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
