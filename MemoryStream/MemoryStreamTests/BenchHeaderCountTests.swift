import Testing
import Foundation
@testable import HiMem

/// **Does the Clips header count everything on screen?**
///
/// `DrawnBench.count`'s own doc says it is *"Every item on screen, in any
/// region. One set — so the count, the span and the session term cannot
/// describe different things, which is the identity seven defects violated."*
///
/// But `count` is `items.count`, and `items` is
/// `loose + clusteredSessions + inFlight` where `loose` is already narrowed by
/// `DrawnBench.from(…, drawsVoicelessSessions: false)` to `.filter(\.hasVoice)`.
/// The **sibling day-grouped stack** — `ClipsTabView.unplacedDayGroupedStack`,
/// fed from `RenderedBench.siblingStackSessions` via `BenchSiblingStackBus` —
/// draws the complement, and nothing in `items` accounts for it.
///
/// The header therefore stated a number smaller than the number of things
/// beneath it, which is precisely the rule Tom locked on 2026-08-10:
///
/// > **A count must describe the thing it sits on.** The list header sits above
/// > a card; the card's glyph sits on that card; the drill-in header sits above
/// > its rows. If any of those three states a number, it must be the number
/// > visible beneath it.
///
/// That made the doc comment a **phantom comment** in the F23 sense —
/// describing a completeness the value did not have — over a live F37-class
/// defect. Measured before the fix: the header said **2** with **4** items
/// drawn (2 as session cards, 2 in the stack), and `count` was **2** against
/// **3** loose items composed.
///
/// **Latent, not invisible.** It requires a voiceless (media-only) session to
/// exist, which the QA seeder does not produce — the fixture gap the 2026-08-19
/// log recorded. One appeared on device for the first time that evening, made
/// by setting a photo aside from a cluster.
///
/// **FIXED 2026-08-19 — and the fix was to the value, not to this test.**
/// `DrawnBench` gained `siblingStack` as a fourth REGION (the distinction
/// `inFlight` already carried), so `items`, `count`, `capturedAts`,
/// `drawnSessionCount` and `sessionTerm` all describe one set again. This was
/// held as `.held` while it was red so the branch never carried a knowingly-
/// failing gate, and released unchanged when the value stopped lying.
///
/// **The fix deliberately did NOT change what the session cards draw.**
/// Folding the stack into `loose` is the deferred layout flip — a *what*, and
/// unruled. The count now describes the current layout honestly instead of
/// quietly assuming a different one.
struct BenchHeaderCountTests {

    private func item(_ kind: BenchClipItem.Kind, at seconds: TimeInterval) -> BenchClipItem {
        BenchClipItem(
            id: UUID(),
            kind: kind,
            capturedAt: Date(timeIntervalSinceReferenceDate: seconds),
            rollGroupId: nil
        )
    }

    /// `proposals:` is passed to `compose` rather than only to
    /// `DrawnBench.from` — `claiming` is what moves a session out of `loose`,
    /// so a fixture that skips it leaves a "clustered" session loose and the
    /// self-tests below correctly refuse it. Same shape as
    /// `RenderedBenchTests.theSessionTermDropsWhenEverySessionIsClustered`.
    private func bench(_ items: [BenchClipItem], proposals: [ClusterProposal] = []) -> RenderedBench {
        RenderedBench.compose(
            allItems: items,
            reviewedIds: [],
            hideReviewed: false,
            now: Date(timeIntervalSinceReferenceDate: 100_000),
            inFlightIds: [],
            reviewedAt: { _ in nil },
            soloIds: [],
            proposals: proposals
        )
    }

    private func cardRegionIsNonEmpty(_ drawn: DrawnBench) -> Bool {
        !(drawn.loose.isEmpty && drawn.clusteredSessions.isEmpty)
    }

    /// **THE MONEY TEST.** The header's number must equal what the two regions
    /// draw between them.
    ///
    /// Fixture: one voice sitting with a photo folded into it (drawn as a
    /// session card), and — far enough away in time to group alone — a photo
    /// and a note with no voice (drawn by the sibling stack). Four items on
    /// screen across two regions.
    @Test
    func theHeaderCountsEveryItemBothRegionsDraw() {
        let voice = item(.voice, at: 0)
        let absorbed = item(.image, at: 60)
        let lonelyPhoto = item(.image, at: 50_000)
        let lonelyNote = item(.note, at: 50_060)

        let composed = bench([voice, absorbed, lonelyPhoto, lonelyNote])
        let drawn = DrawnBench.from(composed, proposals: [])
        let stackItems = composed.siblingStackSessions.flatMap(\.items)

        // Self-tests: without these the assertion could pass by the fixture
        // producing no stack at all, which is the "guard that reports success
        // by failing to look" shape.
        #expect(!stackItems.isEmpty, "self-test: the fixture must give the sibling stack something to draw")
        #expect(cardRegionIsNonEmpty(drawn), "self-test: the fixture must give the session-card region something to draw")

        // **Summed from the REGIONS as the view draws them**, not from
        // `drawn.items` — which is the value under test and would make this
        // assertion compare a number to itself. The card block draws
        // `loose` + `clusteredSessions`; the stack draws what
        // `siblingStackSessions` publishes through `BenchSiblingStackBus`.
        // Reading the stack from `composed` rather than from `drawn` also
        // makes this fail if the two ever diverge.
        let cardRegion = drawn.loose.flatMap(\.items).count
            + drawn.clusteredSessions.flatMap(\.items).count
        let onScreen = cardRegion + stackItems.count + drawn.inFlight.count

        #expect(
            drawn.count == onScreen,
            """
            The header says \(drawn.count) but \(onScreen) items are drawn — \
            \(cardRegion) as session cards and \(stackItems.count) in the sibling stack.

            A count must describe the thing it sits on (Tom, 2026-08-10). \
            `DrawnBench.count` excludes `siblingStackSessions`, while its own doc \
            claims "every item on screen, in any region".
            """
        )
    }

    /// The same statement from the other side, so a failure names *which* half
    /// is wrong: every item the composition produced is drawn somewhere, and
    /// the header should equal that whole.
    @Test
    func theHeaderEqualsEveryLooseItemTheBenchComposed() {
        let composed = bench([
            item(.voice, at: 0),
            item(.image, at: 60),
            item(.image, at: 50_000),
        ])
        let drawn = DrawnBench.from(composed, proposals: [])
        let looseItems = composed.loose.flatMap(\.items)

        #expect(looseItems.count == 3, "self-test: all three items should be loose in this fixture")
        #expect(
            drawn.count == looseItems.count,
            "The header (\(drawn.count)) does not describe the bench it heads (\(looseItems.count) loose items)"
        )
    }

    /// **The session term must survive an unclustered region.**
    ///
    /// The rule (2026-08-09) is *"nil when every session is clustered"* — a
    /// header saying "1 session" over a cluster card asserts the grouping the
    /// card only proposes. A session drawn in the sibling stack is **not**
    /// clustered, so the word must stay.
    ///
    /// **Added because a mutation found it unguarded (M16, 2026-08-19).**
    /// Reverting `sessionTerm` to test `loose` alone left the whole suite
    /// green, so the stack's participation in the nil test was carried by
    /// nothing. That is the exact shape CLAUDE.md § Guard the Caller names:
    /// the value was right and no test asked.
    @Test
    func aVoicelessSittingBesideAClusterKeepsTheSessionTerm() {
        let a = item(.voice, at: 0)
        let b = item(.voice, at: 60)
        let lonelyPhoto = item(.image, at: 50_000)

        let proposal = ClusterProposal(
            clipIds: [a.id, b.id],
            ruleTag: .wordMatch,
            whyText: "why",
            proposedName: "cluster",
            previewLines: []
        )
        let composed = bench([a, b, lonelyPhoto], proposals: [proposal])
        let drawn = DrawnBench.from(composed, proposals: [proposal])

        // Self-tests: the fixture must actually reach the case, or the
        // assertion below passes by describing a different bench.
        #expect(drawn.loose.isEmpty, "self-test: every voice sitting must be claimed by the proposal")
        #expect(!drawn.siblingStack.isEmpty, "self-test: the fixture must leave a voiceless sitting in the stack")

        #expect(
            drawn.sessionTerm != nil,
            "The session term went nil over a screen carrying an unclustered region — it is only nil when EVERY session is clustered"
        )
        #expect(
            drawn.sessionTerm == drawn.drawnSessionCount,
            "When the term is carried it counts every drawn session, in any region"
        )
    }

    /// **The control, and it must stay green either way.** With no voiceless
    /// session there is no second region, so the header is already correct.
    /// This is what makes the defect *latent* rather than always-wrong, and it
    /// is why no existing test caught it: every fixture on this surface gives
    /// its media a voice clip to sit with.
    @Test
    func withNoVoicelessSessionTheHeaderIsAlreadyCorrect() {
        let composed = bench([item(.voice, at: 0), item(.image, at: 60)])
        let drawn = DrawnBench.from(composed, proposals: [])
        let stackItems = composed.siblingStackSessions.flatMap(\.items)

        #expect(stackItems.isEmpty, "self-test: this fixture must produce no sibling stack")
        #expect(
            drawn.count == drawn.items.count,
            "with one region there is nothing for the count to omit"
        )
    }
}
