import Testing
import Foundation
@testable import HiMem

/// Money tests for the two New-lens defects (device pass 2026-07-27):
///
/// 1. The New lens listed months-old, already-handled clips. Root cause: the
///    pre-existing bench library predates review tracking, so every historical
///    ref decodes `reviewed == false` and floods New when it returns from a
///    memory as a loose ref. `BenchReviewBackfillMigration` marks the existing
///    refs reviewed so they leave New.
/// 2. The empty state ("Nothing new") rendered directly above populated rows,
///    because its gate ignored the sibling unplaced-ref stack.
///    `SessionListView.showsEmptyState` makes the state mutually exclusive with
///    all lens content.
///
/// `.serialized` — both stores are process-global UserDefaults.
@Suite(.serialized)
struct NewLensReviewTests {

    private let reviewedKey = "com.himem.bench.reviewedRefIds"
    private let doneKey = "com.himem.bench.reviewBackfill.v1.done"

    private func reset() {
        UserDefaults.standard.removeObject(forKey: reviewedKey)
        UserDefaults.standard.removeObject(forKey: doneKey)
    }

    // MARK: - Bug 1 · review-state backfill migration

    @Test func backfill_marksExistingRefsReviewedAndSetsFlag() {
        reset()
        let a = UUID(), b = UUID(), c = UUID()
        #expect(!BenchClipReviewStore.isReviewed(a), "precondition: unreviewed (the flood)")
        #expect(!BenchReviewBackfillMigration.hasRun)

        BenchReviewBackfillMigration.apply(refIds: [a, b, c])

        #expect(BenchClipReviewStore.isReviewed(a))
        #expect(BenchClipReviewStore.isReviewed(b))
        #expect(BenchClipReviewStore.isReviewed(c))
        #expect(BenchReviewBackfillMigration.hasRun, "flag set so it runs exactly once")
        reset()
    }

    /// The New lens excludes reviewed refs (`!isReviewed`). A historical ref
    /// that flooded New before the fix must fall off it after the backfill —
    /// this is the exact user-visible symptom, pinned.
    @Test func newLens_excludesBackfilledRef() {
        reset()
        let historical = UUID()
        // Pre-fix: unreviewed → visible on New.
        #expect(!BenchClipReviewStore.isReviewed(historical),
                "before backfill the months-old ref reads unseen → floods New")

        BenchReviewBackfillMigration.apply(refIds: [historical])

        // The New filter is `!BenchClipReviewStore.isReviewed(id)`.
        let visibleOnNew = !BenchClipReviewStore.isReviewed(historical)
        #expect(!visibleOnNew, "after backfill the ref leaves the New lens")
        reset()
    }

    @Test func batchMarkReviewed_isIdempotent() {
        reset()
        let a = UUID(), b = UUID()
        BenchClipReviewStore.markReviewed([a, b])
        BenchClipReviewStore.markReviewed([a, b])   // no-op second time
        BenchClipReviewStore.markReviewed([])       // empty no-op
        #expect(BenchClipReviewStore.isReviewed(a) && BenchClipReviewStore.isReviewed(b))
        reset()
    }

    // MARK: - Bug 2 · empty state / content mutual exclusivity

    /// **Updated at the `main` → `f8` merge, 2026-08-02 — the meaning moved,
    /// not the phrasing.** A third condition arrived from the other branch:
    /// F22's `mayAssertEmpty`, which forbids claiming empty while the first
    /// CloudKit import is still running. That is the legitimate reason to
    /// edit a guard — the rule genuinely gained a clause — as opposed to
    /// updating an assertion to make a red go away.
    ///
    /// The original two assertions are preserved verbatim in meaning; they
    /// simply now pass `mayAssertEmpty: true` (import finished), which is
    /// the state they were implicitly written against.
    @Test func emptyState_suppressedWhenSiblingStackHasContent() {
        // The reported bug: no sessions, but the sibling unplaced stack has
        // rows → the empty state must NOT show.
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: true, hasSiblingContent: true, mayAssertEmpty: true) == false,
                "no 'Nothing new' above populated sibling rows")
        // Whole lens empty, import finished → the empty state is the only
        // thing shown.
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: true, hasSiblingContent: false, mayAssertEmpty: true) == true)
        // Sessions present → never the empty state, regardless of siblings.
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: false, hasSiblingContent: false, mayAssertEmpty: true) == false)
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: false, hasSiblingContent: true, mayAssertEmpty: true) == false)
    }

    /// **F22's half of the same sentence.** An empty local store during the
    /// first import is "we haven't finished looking," not "she has none" —
    /// and on the surface whose subject is content she feared losing,
    /// certainty is the harm. This is the condition the merge added; without
    /// it the resolution would have silently dropped a shipped fix.
    @Test func emptyState_suppressedWhileTheFirstImportIsStillRunning() {
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: true, hasSiblingContent: false, mayAssertEmpty: false) == false,
                "'Nothing new' must not be asserted while the first import is still looking")
    }

    /// Bound the other side too: the predicate must not become "always
    /// false", which would pass both suppression tests above while silently
    /// retiring the empty state entirely.
    @Test func emptyState_isStillReachable() {
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: true, hasSiblingContent: false, mayAssertEmpty: true) == true,
                "the empty state is unreachable — a suppression rule has swallowed it")
    }

    /// All three conditions are load-bearing: flipping any single one away
    /// from the showing state suppresses it. A predicate that ignored one
    /// would pass a narrower test set.
    @Test func everyConditionIsLoadBearing() {
        let showing = (sessionsEmpty: true, hasSiblingContent: false, mayAssertEmpty: true)
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: !showing.sessionsEmpty,
            hasSiblingContent: showing.hasSiblingContent,
            mayAssertEmpty: showing.mayAssertEmpty) == false)
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: showing.sessionsEmpty,
            hasSiblingContent: !showing.hasSiblingContent,
            mayAssertEmpty: showing.mayAssertEmpty) == false)
        #expect(SessionListView.showsEmptyState(
            sessionsEmpty: showing.sessionsEmpty,
            hasSiblingContent: showing.hasSiblingContent,
            mayAssertEmpty: !showing.mayAssertEmpty) == false)
    }
}
