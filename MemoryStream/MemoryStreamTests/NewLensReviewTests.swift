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

    @Test func emptyState_suppressedWhenSiblingStackHasContent() {
        // The reported bug: no sessions, but the sibling unplaced stack has
        // rows → the empty state must NOT show.
        #expect(SessionListView.showsEmptyState(sessionsEmpty: true, hasSiblingContent: true) == false,
                "no 'Nothing new' above populated sibling rows")
        // Whole lens empty → the empty state is the only thing shown.
        #expect(SessionListView.showsEmptyState(sessionsEmpty: true, hasSiblingContent: false) == true)
        // Sessions present → never the empty state, regardless of siblings.
        #expect(SessionListView.showsEmptyState(sessionsEmpty: false, hasSiblingContent: false) == false)
        #expect(SessionListView.showsEmptyState(sessionsEmpty: false, hasSiblingContent: true) == false)
    }
}
