import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the suggested-project-membership feature
/// (`docs/design/Projects · MVP spec.md` § Suggested memories).
///
/// Contract:
/// - A memory is a candidate iff (a) it's not already in the
///   project, (b) it's not in the dismissed set, and (c) its
///   accepted-topic set intersects the project's topic
///   fingerprint by ≥ 1 topic.
/// - Pre-acceptance topics (OrganizePass suggestions that the user
///   hasn't tapped Accept on) DO NOT count. The entry must have a
///   real Core Data `Topic` relationship.
/// - Ranked: overlap count desc, then `createdAt` desc.
/// - Match is slug-equivalent ("Photo" matches "Photos" matches
///   "photo") so casing / pluralization drift across two AI
///   organize passes doesn't break the join.
@MainActor
@Suite(.serialized)
struct ProjectMembershipSuggesterTests {

    // MARK: - Helpers

    /// Creates a Project + N entries + topic mesh. Returns the
    /// project and a name → entry lookup for assertions.
    private func makeFixture(
        storage: StorageService,
        projectName: String = "Building HiMem",
        projectTopics: [String] = [],
        otherEntries: [(name: String, topics: [String])] = []
    ) throws -> (project: Project, byName: [String: JournalEntry]) {
        let ctx = storage.viewContext

        // Build topics once and intern by name so callers share
        // the same Topic instance across the project + entries.
        var topicsByName: [String: Topic] = [:]
        func topic(_ name: String) -> Topic {
            if let t = topicsByName[name] { return t }
            let t = Topic(context: ctx)
            t.id = UUID()
            t.name = name
            t.slug = TopicSlugHelper.slugify(name)
            t.inferredAt = Date()
            topicsByName[name] = t
            return t
        }

        // Project with N seed memories carrying the topics that
        // define the project's fingerprint.
        let project = Project(context: ctx)
        project.id = UUID()
        project.name = projectName
        project.createdAt = Date()
        project.updatedAt = Date()

        for (i, topicName) in projectTopics.enumerated() {
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.content = "seed \(i)"
            entry.createdAt = Date(timeIntervalSinceNow: TimeInterval(-100 - i))
            entry.inputType = "typed"
            entry.addToTopics(topic(topicName))
            project.addToEntries(entry)
        }

        // Other entries — candidates or not, per their topic mix.
        var byName: [String: JournalEntry] = [:]
        for (i, spec) in otherEntries.enumerated() {
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.content = spec.name
            entry.createdAt = Date(timeIntervalSinceNow: TimeInterval(-i))
            entry.inputType = "typed"
            for tn in spec.topics {
                entry.addToTopics(topic(tn))
            }
            byName[spec.name] = entry
        }

        try ctx.save()
        return (project, byName)
    }

    // MARK: - Core cases

    @Test func noProjectTopics_returnsEmpty() throws {
        let storage = StorageService(inMemory: true)
        let (project, _) = try makeFixture(
            storage: storage,
            projectTopics: [],
            otherEntries: [("a", ["Garden"]), ("b", ["Work"])]
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        // No project fingerprint → no candidates.
        #expect(candidates.isEmpty)
    }

    @Test func entryWithMatchingTopic_isCandidate() throws {
        let storage = StorageService(inMemory: true)
        let (project, byName) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden"],
            otherEntries: [("compost", ["Garden"]), ("work", ["Office"])]
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        let compostId = byName["compost"]!.id
        let workId = byName["work"]!.id
        #expect(candidates.contains { $0.entryId == compostId })
        #expect(!candidates.contains { $0.entryId == workId })
    }

    @Test func entryAlreadyInProject_isExcluded() throws {
        let storage = StorageService(inMemory: true)
        // The seed memory carrying "Garden" IS the project's member.
        // It shouldn't be re-offered as a candidate.
        let (project, _) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden"],
            otherEntries: []
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        #expect(candidates.isEmpty)
    }

    /// Pre-acceptance topics (from `OrganizePass.suggestedTopics`)
    /// MUST NOT count — the entry only enters suggestions when its
    /// `topics` relationship is populated by an Accept. This is the
    /// exact scenario from 2026-06-01: the meta-memory had
    /// suggested topics "Content" + "Technology" but no accepted
    /// topics yet, and didn't appear in Building HiMem's suggestion
    /// list.
    @Test func entryWithoutAcceptedTopics_isExcluded() throws {
        let storage = StorageService(inMemory: true)
        let (project, _) = try makeFixture(
            storage: storage,
            projectTopics: ["Content"],
            otherEntries: [("orphan", [])]  // no topics attached
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        #expect(candidates.isEmpty)
    }

    @Test func dismissedEntry_isExcluded() throws {
        let storage = StorageService(inMemory: true)
        let (project, byName) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden"],
            otherEntries: [("dismissed", ["Garden"]), ("kept", ["Garden"])]
        )

        let dismissedId = byName["dismissed"]!.id
        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: [dismissedId]
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.entryId == byName["kept"]!.id)
    }

    @Test func rankedByOverlapDescThenDateDesc() throws {
        let storage = StorageService(inMemory: true)
        // Project fingerprint: Garden + Photography + Cooking
        // Fixture order = creation order, and our fixture loop
        // assigns createdAt = -i seconds, so i=0 is newest. Put
        // "three-topic-new" first so the label matches the date.
        let (project, byName) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden", "Photography", "Cooking"],
            otherEntries: [
                ("three-topic-new",   ["Garden", "Photography", "Cooking"]), // 3 overlap, newer
                ("three-topic-old",   ["Garden", "Photography", "Cooking"]), // 3 overlap, older
                ("two-topic",         ["Garden", "Photography"]),            // 2 overlap
                ("one-topic",         ["Garden"]),                            // 1 overlap
                ("no-topic-match",    ["Office"])                             // 0
            ]
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        #expect(candidates.count == 4)
        // Ranked: 3 + newest, 3 + oldest, 2, 1
        #expect(candidates[0].entryId == byName["three-topic-new"]!.id)
        #expect(candidates[1].entryId == byName["three-topic-old"]!.id)
        #expect(candidates[2].entryId == byName["two-topic"]!.id)
        #expect(candidates[3].entryId == byName["one-topic"]!.id)
    }

    /// Match by slug — casing drift between two AI organize passes
    /// ("Garden" vs "garden") joins via slug. Locks the contract
    /// that ProcessingEngine.assignTopics relies on (slug-keyed
    /// fetches for topic intern), and that the suggester must
    /// mirror.
    @Test func matchIsCaseInsensitiveByPositionOfSlug() throws {
        let storage = StorageService(inMemory: true)
        let (project, byName) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden"],
            otherEntries: [("lowercase-garden", ["garden"])]
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.entryId == byName["lowercase-garden"]!.id)
    }

    @Test func matchedTopicsCarriesProjectFacingNames() throws {
        let storage = StorageService(inMemory: true)
        let (project, _) = try makeFixture(
            storage: storage,
            projectTopics: ["Garden", "Cooking"],
            otherEntries: [("mixed", ["Garden", "Cooking", "Sports"])]
        )

        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: storage.viewContext,
            dismissed: []
        )

        let names = Set(candidates.first?.matchedTopics ?? [])
        // Only the overlap — "Sports" is on the entry but not on
        // the project, so it doesn't appear in the reason row.
        #expect(names == ["Garden", "Cooking"])
    }
}
