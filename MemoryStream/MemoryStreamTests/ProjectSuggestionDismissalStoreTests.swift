import Testing
import Foundation
@testable import HiMem

/// Money tests for the local dismissal cache backing the suggested-
/// membership review sheet. Verifies persistence, project scope, and
/// idempotence — same surface the SuggestedMemoriesSheet "Skip"
/// action invokes.
@MainActor
@Suite(.serialized)
struct ProjectSuggestionDismissalStoreTests {

    private func freshStore() -> (ProjectSuggestionDismissalStore, UserDefaults) {
        // Per-test in-memory UserDefaults — the unit-test suite
        // shouldn't read or pollute the host app's real defaults.
        let suiteName = "test.ProjectSuggestionDismissalStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ProjectSuggestionDismissalStore(defaults: defaults)
        return (store, defaults)
    }

    @Test func dismiss_persists_acrossInstances() {
        let suiteName = "test.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let project = UUID()
        let entry = UUID()

        let store1 = ProjectSuggestionDismissalStore(defaults: defaults)
        store1.dismiss(entryId: entry, forProject: project)
        #expect(store1.dismissed(forProject: project) == [entry])

        // Second store on the same defaults reads the same data —
        // this is the "user backgrounds + relaunches the app"
        // scenario.
        let store2 = ProjectSuggestionDismissalStore(defaults: defaults)
        #expect(store2.dismissed(forProject: project) == [entry])
    }

    @Test func dismiss_isProjectScoped() {
        let (store, _) = freshStore()
        let entry = UUID()
        let projectA = UUID()
        let projectB = UUID()

        store.dismiss(entryId: entry, forProject: projectA)

        #expect(store.dismissed(forProject: projectA) == [entry])
        // Dismissing in A doesn't leak into B.
        #expect(store.dismissed(forProject: projectB).isEmpty)
    }

    @Test func dismiss_isIdempotent() {
        let (store, _) = freshStore()
        let project = UUID()
        let entry = UUID()

        store.dismiss(entryId: entry, forProject: project)
        let firstVersion = store.version

        // Re-dismissing the same entry is a no-op. Locking this
        // matters because the affordance row's view-model observes
        // `version` to refresh — a phantom bump would churn the UI.
        store.dismiss(entryId: entry, forProject: project)
        #expect(store.version == firstVersion)
        #expect(store.dismissed(forProject: project) == [entry])
    }

    @Test func restore_removesDismissal() {
        let (store, _) = freshStore()
        let project = UUID()
        let entry = UUID()

        store.dismiss(entryId: entry, forProject: project)
        #expect(store.dismissed(forProject: project) == [entry])

        store.restore(entryId: entry, forProject: project)
        #expect(store.dismissed(forProject: project).isEmpty)
    }

    @Test func restore_noOpForUnknownEntry() {
        let (store, _) = freshStore()
        let project = UUID()
        let firstVersion = store.version
        store.restore(entryId: UUID(), forProject: project)
        #expect(store.version == firstVersion)
    }

    @Test func clearAll_emptiesProjectButLeavesOthers() {
        let (store, _) = freshStore()
        let projectA = UUID()
        let projectB = UUID()
        let entryA = UUID()
        let entryB = UUID()

        store.dismiss(entryId: entryA, forProject: projectA)
        store.dismiss(entryId: entryB, forProject: projectB)

        store.clearAll(forProject: projectA)

        #expect(store.dismissed(forProject: projectA).isEmpty)
        #expect(store.dismissed(forProject: projectB) == [entryB])
    }
}
