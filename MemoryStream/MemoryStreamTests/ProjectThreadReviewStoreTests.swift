import Testing
import Foundation
@testable import HiMem

/// Money tests for `ProjectThreadReviewStore` — the per-device "kept" marker
/// behind the project summary's Draft → committed transition (2026-07-23).
/// The store keys keep-state on the summary's `generatedAt` instant, so a
/// re-run (new generated-at) must fall back to Draft automatically.
@Suite(.serialized)
struct ProjectThreadReviewStoreTests {

    private func freshProjectId() -> UUID { UUID() }

    @Test func unkeptByDefault() {
        let p = freshProjectId()
        #expect(ProjectThreadReviewStore.isKept(projectId: p, generatedAt: Date()) == false)
    }

    @Test func markKept_thenIsKept_forSameGeneratedAt() {
        let p = freshProjectId()
        let gen = Date()
        ProjectThreadReviewStore.markKept(projectId: p, generatedAt: gen)
        #expect(ProjectThreadReviewStore.isKept(projectId: p, generatedAt: gen))
    }

    /// The whole point: a fresh "Find the thread again" stamps a new
    /// generated-at, so the prior keep no longer matches → back to Draft.
    @Test func newGeneratedAt_resetsToDraft() {
        let p = freshProjectId()
        let firstGen = Date(timeIntervalSinceReferenceDate: 1_000)
        ProjectThreadReviewStore.markKept(projectId: p, generatedAt: firstGen)
        #expect(ProjectThreadReviewStore.isKept(projectId: p, generatedAt: firstGen))

        let rerunGen = Date(timeIntervalSinceReferenceDate: 2_000)
        #expect(ProjectThreadReviewStore.isKept(projectId: p, generatedAt: rerunGen) == false)
    }

    /// nil generated-at (no summary yet) is never kept, and marking a nil is
    /// a no-op that can't crash.
    @Test func nilGeneratedAt_isNeverKept() {
        let p = freshProjectId()
        ProjectThreadReviewStore.markKept(projectId: p, generatedAt: nil)
        #expect(ProjectThreadReviewStore.isKept(projectId: p, generatedAt: nil) == false)
    }

    /// Keep is scoped per project — keeping one doesn't keep another.
    @Test func keptState_isPerProject() {
        let a = freshProjectId(), b = freshProjectId()
        let gen = Date(timeIntervalSinceReferenceDate: 5_000)
        ProjectThreadReviewStore.markKept(projectId: a, generatedAt: gen)
        #expect(ProjectThreadReviewStore.isKept(projectId: a, generatedAt: gen))
        #expect(ProjectThreadReviewStore.isKept(projectId: b, generatedAt: gen) == false)
    }
}
