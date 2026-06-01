import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the bridge between `ProjectMembershipSuggester`
/// (pure logic) and `SuggestedMemoriesSheet` (UI). Locks the
/// commit semantics — selected → addToEntries, unselected →
/// persistent dismissal — and the rationale / confidence mapping.
@MainActor
@Suite(.serialized)
struct ProjectSuggestionsViewModelTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "test.ProjectSuggestionsViewModel.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeTopic(named name: String, in ctx: NSManagedObjectContext) -> Topic {
        let t = Topic(context: ctx)
        t.id = UUID()
        t.name = name
        t.slug = TopicSlugHelper.slugify(name)
        t.inferredAt = Date()
        return t
    }

    private func makeEntry(
        title: String?,
        content: String,
        topics: [Topic],
        in ctx: NSManagedObjectContext
    ) -> JournalEntry {
        let entry = JournalEntry(context: ctx)
        entry.id = UUID()
        entry.title = title
        entry.content = content
        entry.createdAt = Date()
        entry.inputType = "typed"
        for t in topics { entry.addToTopics(t) }
        return entry
    }

    @Test func reload_populatesSuggestionsWithRationaleAndConfidence() throws {
        let storage = StorageService(inMemory: true)
        let defaults = freshDefaults()
        let dismissalStore = ProjectSuggestionDismissalStore(defaults: defaults)
        let vm = ProjectSuggestionsViewModel(dismissalStore: dismissalStore, storage: storage)
        let ctx = storage.viewContext

        let garden = makeTopic(named: "Garden", in: ctx)
        let cooking = makeTopic(named: "Cooking", in: ctx)

        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "Building HiMem"
        project.createdAt = Date()
        project.updatedAt = Date()
        let seed = makeEntry(title: "seed", content: "x", topics: [garden, cooking], in: ctx)
        project.addToEntries(seed)

        let twoTopic = makeEntry(title: "Compost run", content: "x", topics: [garden, cooking], in: ctx)
        let oneTopic = makeEntry(title: "Just garden", content: "x", topics: [garden], in: ctx)
        try ctx.save()

        vm.reload(projectId: project.id)

        let byId = Dictionary(uniqueKeysWithValues: vm.suggestions.map { ($0.id, $0) })
        let twoSug = byId[twoTopic.id]
        let oneSug = byId[oneTopic.id]

        #expect(twoSug != nil)
        #expect(oneSug != nil)

        // Rationale: literal topic-match list (Plan B is local;
        // AI rationales are v1.1).
        #expect(twoSug?.rationale.contains("Garden") == true)
        #expect(twoSug?.rationale.contains("Cooking") == true)
        #expect(twoSug?.rationale.hasPrefix("Matches ") == true)

        // Confidence band: 1 = Maybe, ≥2 = Likely.
        #expect(twoSug?.confidence == .likely)
        #expect(oneSug?.confidence == .maybe)
    }

    @Test func reload_titleFallsBackToContentExcerptWhenTitleNil() throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectSuggestionsViewModel(
            dismissalStore: ProjectSuggestionDismissalStore(defaults: freshDefaults()),
            storage: storage
        )
        let ctx = storage.viewContext

        let garden = makeTopic(named: "Garden", in: ctx)
        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "p"
        project.createdAt = Date()
        project.updatedAt = Date()
        let seed = makeEntry(title: "seed", content: "x", topics: [garden], in: ctx)
        project.addToEntries(seed)

        let untitled = makeEntry(
            title: nil,
            content: "I went to the garden today and watered the tomatoes",
            topics: [garden],
            in: ctx
        )
        try ctx.save()

        vm.reload(projectId: project.id)

        let sug = vm.suggestions.first { $0.id == untitled.id }
        #expect(sug != nil)
        // First few words of the content with an ellipsis when
        // truncated — the row needs *something* to anchor it
        // visually even without a memory title.
        #expect(sug?.title.hasPrefix("I went to the") == true)
    }

    @Test func commit_addsSelectedEntriesToProject() throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectSuggestionsViewModel(
            dismissalStore: ProjectSuggestionDismissalStore(defaults: freshDefaults()),
            storage: storage
        )
        let ctx = storage.viewContext
        let garden = makeTopic(named: "Garden", in: ctx)

        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "p"
        project.createdAt = Date()
        project.updatedAt = Date()
        let seed = makeEntry(title: "seed", content: "x", topics: [garden], in: ctx)
        project.addToEntries(seed)

        let candidate = makeEntry(title: "compost", content: "x", topics: [garden], in: ctx)
        try ctx.save()

        vm.reload(projectId: project.id)
        #expect(vm.suggestions.contains { $0.id == candidate.id })

        // User accepts the candidate.
        vm.commit(acceptedIDs: [candidate.id], projectId: project.id)

        let memberIDs = Set(project.entriesArray.map(\.id))
        #expect(memberIDs.contains(candidate.id))
        // Now that it's a member, it shouldn't be suggested again.
        #expect(vm.suggestions.contains { $0.id == candidate.id } == false)
    }

    @Test func commit_dismissesUnselectedShownEntries() throws {
        let storage = StorageService(inMemory: true)
        let defaults = freshDefaults()
        let dismissalStore = ProjectSuggestionDismissalStore(defaults: defaults)
        let vm = ProjectSuggestionsViewModel(dismissalStore: dismissalStore, storage: storage)
        let ctx = storage.viewContext

        let garden = makeTopic(named: "Garden", in: ctx)
        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "p"
        project.createdAt = Date()
        project.updatedAt = Date()
        let seed = makeEntry(title: "seed", content: "x", topics: [garden], in: ctx)
        project.addToEntries(seed)

        let keep = makeEntry(title: "keep", content: "x", topics: [garden], in: ctx)
        let skip = makeEntry(title: "skip", content: "x", topics: [garden], in: ctx)
        try ctx.save()

        vm.reload(projectId: project.id)
        #expect(vm.suggestions.count == 2)

        // User accepts `keep`, leaves `skip` unchecked, taps Add.
        vm.commit(acceptedIDs: [keep.id], projectId: project.id)

        // `skip` is persistently dismissed — reopening the sheet
        // won't re-surface it.
        #expect(dismissalStore.dismissed(forProject: project.id).contains(skip.id))
        // And after reload, both have left the suggestions list:
        // `keep` because it's now a member, `skip` because it's
        // dismissed.
        #expect(vm.suggestions.isEmpty)
    }

    @Test func commit_emptyAcceptedSet_dismissesAllShownEntries() throws {
        // Edge case: user deselects everything then taps a Skip-All
        // path (or some future variant). Even though the existing
        // sheet disables Add at zero, lock the contract that
        // commit() handles empty input cleanly — every shown row
        // gets dismissed, no rows get added.
        let storage = StorageService(inMemory: true)
        let defaults = freshDefaults()
        let dismissalStore = ProjectSuggestionDismissalStore(defaults: defaults)
        let vm = ProjectSuggestionsViewModel(dismissalStore: dismissalStore, storage: storage)
        let ctx = storage.viewContext

        let garden = makeTopic(named: "Garden", in: ctx)
        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "p"
        project.createdAt = Date()
        project.updatedAt = Date()
        let seed = makeEntry(title: "seed", content: "x", topics: [garden], in: ctx)
        project.addToEntries(seed)

        let a = makeEntry(title: "a", content: "x", topics: [garden], in: ctx)
        let b = makeEntry(title: "b", content: "x", topics: [garden], in: ctx)
        try ctx.save()

        vm.reload(projectId: project.id)
        #expect(vm.suggestions.count == 2)

        vm.commit(acceptedIDs: [], projectId: project.id)

        let dismissed = dismissalStore.dismissed(forProject: project.id)
        #expect(dismissed.contains(a.id))
        #expect(dismissed.contains(b.id))
        #expect(project.entriesArray.map(\.id).contains(a.id) == false)
        #expect(project.entriesArray.map(\.id).contains(b.id) == false)
    }
}
