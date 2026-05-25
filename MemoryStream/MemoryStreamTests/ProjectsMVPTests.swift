import Testing
import Foundation
import CoreData
@testable import HiMem

/// PR 1 of the Projects MVP rebuild. Covers:
///
///   • Project cap policy (Free hard-capped at 1; Plus/Founders
///     uncapped) — extracted so the gate is testable without
///     driving the ProjectListView.
///   • ProjectViewModel CRUD — createProject, deleteProject.
///   • Memory × Project many-to-many — a memory can belong to
///     multiple projects (the m2m schema was already there; this
///     locks behavior in via test).
///   • Derived topic names — `Project.topicNames` returns the
///     unioned topics of the project's member memories. No
///     project-level topic field.
@MainActor
@Suite(.serialized)
struct ProjectsMVPTests {

    // MARK: - Cap policy

    @Test func cap_freeWithZeroProjects_canCreate() {
        #expect(ProjectCapPolicy.canCreate(isPlus: false, currentCount: 0) == true)
    }

    @Test func cap_freeWithOneProject_blocked() {
        #expect(ProjectCapPolicy.canCreate(isPlus: false, currentCount: 1) == false)
    }

    @Test func cap_freeWithMultipleProjects_stillBlocked() {
        // Edge case: user was Plus, created 3 projects, then downgraded.
        // The cap policy itself still returns false; the rest is handled
        // by the cancel-Plus regression (deferred per spec).
        #expect(ProjectCapPolicy.canCreate(isPlus: false, currentCount: 3) == false)
    }

    @Test func cap_plusUser_uncappedAtAnyCount() {
        #expect(ProjectCapPolicy.canCreate(isPlus: true, currentCount: 0) == true)
        #expect(ProjectCapPolicy.canCreate(isPlus: true, currentCount: 1) == true)
        #expect(ProjectCapPolicy.canCreate(isPlus: true, currentCount: 50) == true)
    }

    // MARK: - ProjectViewModel CRUD

    @Test func createProject_persistsAndRetrievable() async throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectViewModel(storage: storage)

        vm.createProject(name: "Building Himem", purpose: "Ship the iOS app")
        // ProjectViewModel observes Core Data via debounced notification;
        // call loadProjects directly to avoid the 250ms debounce.
        vm.loadProjects()

        #expect(vm.projects.count == 1)
        #expect(vm.projects.first?.name == "Building Himem")
        #expect(vm.projects.first?.purpose == "Ship the iOS app")
    }

    @Test func createProject_emptyPurpose_storesNil() {
        let storage = StorageService(inMemory: true)
        let vm = ProjectViewModel(storage: storage)

        vm.createProject(name: "Garden plans", purpose: nil)
        vm.loadProjects()

        #expect(vm.projects.first?.purpose == nil)
    }

    @Test func deleteProject_removesFromStore() throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectViewModel(storage: storage)
        vm.createProject(name: "Throwaway", purpose: nil)
        vm.loadProjects()
        let id = try #require(vm.projects.first?.id)

        vm.deleteProject(id: id)
        vm.loadProjects()

        #expect(vm.projects.isEmpty)
    }

    // MARK: - Memory × Project many-to-many

    @Test func memoryCanBelongToMultipleProjects() throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectViewModel(storage: storage)
        // Two projects.
        vm.createProject(name: "Building Himem", purpose: nil)
        vm.createProject(name: "AI essay — second draft", purpose: nil)
        vm.loadProjects()
        let projectA = try #require(vm.projects.first { $0.name == "Building Himem" }?.id)
        let projectB = try #require(vm.projects.first { $0.name == "AI essay — second draft" }?.id)
        // One memory.
        let entry = try storage.createEntry(content: "Watch-first capture is the key", inputType: .typed)
        try storage.viewContext.save()

        vm.addMemory(entryId: entry.id, toProjectId: projectA)
        vm.addMemory(entryId: entry.id, toProjectId: projectB)
        vm.loadProjects()

        let projectsContainingMemory = (entry.projects as? Set<Project>)?.map(\.name).sorted() ?? []
        #expect(projectsContainingMemory == ["AI essay — second draft", "Building Himem"])
    }

    @Test func removeMemory_fromOneProject_keepsItInOthers() throws {
        let storage = StorageService(inMemory: true)
        let vm = ProjectViewModel(storage: storage)
        vm.createProject(name: "A", purpose: nil)
        vm.createProject(name: "B", purpose: nil)
        vm.loadProjects()
        let projectA = try #require(vm.projects.first { $0.name == "A" }?.id)
        let projectB = try #require(vm.projects.first { $0.name == "B" }?.id)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        try storage.viewContext.save()
        vm.addMemory(entryId: entry.id, toProjectId: projectA)
        vm.addMemory(entryId: entry.id, toProjectId: projectB)

        vm.removeMemory(entryId: entry.id, fromProjectId: projectA)

        let remaining = (entry.projects as? Set<Project>)?.map(\.name) ?? []
        #expect(remaining == ["B"])
    }

    // MARK: - Derived topics

    @Test func projectTopicNames_unionedFromMemberMemories() throws {
        let storage = StorageService(inMemory: true)
        let entry1 = try storage.createEntry(content: "x", inputType: .typed)
        let entry2 = try storage.createEntry(content: "y", inputType: .typed)
        let cooking = try storage.findOrCreateTopic(name: "Cooking")
        let garden = try storage.findOrCreateTopic(name: "Garden")
        let howWeWork = try storage.findOrCreateTopic(name: "How We Work")
        entry1.addToTopics(cooking)
        entry1.addToTopics(howWeWork)
        entry2.addToTopics(garden)
        entry2.addToTopics(howWeWork)
        let project = try storage.createProject(name: "Mixed", purpose: nil)
        project.addToEntries(entry1)
        project.addToEntries(entry2)
        try storage.viewContext.save()

        let derived = project.topicNames

        #expect(derived == ["Cooking", "Garden", "How We Work"])
    }

    @Test func projectTopicNames_emptyWhenNoMemories() throws {
        let storage = StorageService(inMemory: true)
        let project = try storage.createProject(name: "Empty", purpose: nil)
        try storage.viewContext.save()

        #expect(project.topicNames.isEmpty)
    }

    // MARK: - Project Assist gate (PR 2)

    @Test func assistGate_zeroMemories_alwaysDisabled() {
        #expect(ProjectAssistGate.isEnabled(memoryCount: 0) == false)
    }

    @Test func assistGate_aboveAllPossibleThresholds_enabled() {
        // 7+ memories satisfies both gated-on (≥1) and gated-off
        // (≥3) thresholds, so this assertion is stable regardless of
        // the flag's compile-time value.
        #expect(ProjectAssistGate.isEnabled(memoryCount: 7) == true)
        #expect(ProjectAssistGate.isEnabled(memoryCount: 50) == true)
    }

    /// The flag itself is the contract: when `allowSingleMemoryThreshold`
    /// is false (production-safe default), the conservative ≥3 threshold
    /// applies. When true (post-validation), ≥1 applies. The two
    /// behaviors are tied to the flag — verify the linkage so flipping
    /// the flag is a one-line change with predictable test coverage.
    @Test func assistGate_thresholdTracksFlag() {
        let expectedThreshold = ProjectAssistGate.allowSingleMemoryThreshold ? 1 : 3
        #expect(ProjectAssistGate.minimumMemories == expectedThreshold)
        #expect(ProjectAssistGate.isEnabled(memoryCount: expectedThreshold) == true)
        #expect(ProjectAssistGate.isEnabled(memoryCount: expectedThreshold - 1) == false)
    }

    // MARK: - Project Assist entitlement bucket (PR 3)
    //
    // EntitlementService is a `@MainActor` singleton — these tests
    // exercise it carefully, snapshot/restore the relevant fields so
    // adjacent tests aren't affected.

    @Test func projectAssist_freeUser_firstTapConsumesStarter() throws {
        let svc = EntitlementService.shared
        let originalUsed = svc.starterProjectAssistUsed
        defer { svc.debugSetStarterProjectAssistUsed(originalUsed) }
        svc.debugSetStarterProjectAssistUsed(false)

        #expect(svc.canConsumeProjectAssist == true)
        try svc.tryConsumeProjectAssist()
        #expect(svc.starterProjectAssistUsed == true)
        #expect(svc.canConsumeProjectAssist == false)
    }

    @Test func projectAssist_freeUser_secondTapThrows() throws {
        let svc = EntitlementService.shared
        let originalUsed = svc.starterProjectAssistUsed
        defer { svc.debugSetStarterProjectAssistUsed(originalUsed) }
        svc.debugSetStarterProjectAssistUsed(true)

        #expect(svc.canConsumeProjectAssist == false)
        #expect(throws: EntitlementService.ConsumeError.self) {
            try svc.tryConsumeProjectAssist()
        }
    }

    // MARK: - Suggestion prefilter (PR 4)

    private func candidate(
        topics: [String] = [],
        entities: [String] = [],
        content: String = "",
        daysAgo: Double = 0
    ) -> SuggestionPrefilter.CandidateInput {
        let createdAt = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        return SuggestionPrefilter.CandidateInput(
            id: UUID(),
            topicNames: topics,
            entityValues: entities,
            content: content,
            createdAt: createdAt
        )
    }

    @Test func prefilter_excludesMemoriesAlreadyInProject() {
        let alreadyIn = UUID()
        let candidates = [
            SuggestionPrefilter.CandidateInput(
                id: alreadyIn, topicNames: ["Cooking"],
                entityValues: [], content: "",
                createdAt: Date()
            ),
            candidate(topics: ["Cooking"])
        ]
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: ["Cooking"], entityValues: [],
            memberMemoryIDs: [alreadyIn], centerDate: Date()
        )

        let ranked = SuggestionPrefilter.rank(candidates: candidates, context: ctx)

        #expect(ranked.count == 1)
        #expect(ranked.first?.id != alreadyIn)
    }

    @Test func prefilter_topicOverlap_beatsDateProximity() {
        let withTopic = candidate(topics: ["Cooking"], daysAgo: 30)
        let withDate  = candidate(topics: [],          daysAgo: 0)
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: ["Cooking"], entityValues: [],
            memberMemoryIDs: [], centerDate: Date()
        )

        let ranked = SuggestionPrefilter.rank(candidates: [withDate, withTopic], context: ctx)

        // Topic overlap (2.0) > date proximity (max 1.0)
        #expect(ranked.first?.id == withTopic.id)
    }

    @Test func prefilter_entityOverlap_addsToScore() {
        let bobOnly = candidate(entities: ["Bob"])
        let nothing = candidate()
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: [], entityValues: ["Bob"],
            memberMemoryIDs: [], centerDate: nil
        )

        let ranked = SuggestionPrefilter.rank(candidates: [nothing, bobOnly], context: ctx)

        #expect(ranked.count == 1)
        #expect(ranked.first?.id == bobOnly.id)
    }

    @Test func prefilter_zeroScoreCandidates_excluded() {
        // Candidate shares nothing with the project AND date is
        // outside the 60-day window → score 0 → not surfaced.
        let nothing = candidate(daysAgo: 365)
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: ["Cooking"], entityValues: ["Bob"],
            memberMemoryIDs: [], centerDate: Date()
        )

        let ranked = SuggestionPrefilter.rank(candidates: [nothing], context: ctx)

        #expect(ranked.isEmpty)
    }

    @Test func prefilter_respectsLimit() {
        let candidates = (0..<50).map { _ in candidate(topics: ["Cooking"]) }
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: ["Cooking"], entityValues: [],
            memberMemoryIDs: [], centerDate: nil
        )

        let ranked = SuggestionPrefilter.rank(candidates: candidates, context: ctx, limit: 25)

        #expect(ranked.count == 25)
    }

    @Test func prefilter_caseInsensitiveTopicMatch() {
        let lower = candidate(topics: ["cooking"])
        let title = candidate(topics: ["Cooking"])
        let ctx = SuggestionPrefilter.ProjectContext(
            topicNames: ["COOKING"], entityValues: [],
            memberMemoryIDs: [], centerDate: nil
        )

        let ranked = SuggestionPrefilter.rank(candidates: [lower, title], context: ctx)

        #expect(ranked.count == 2)
    }

    @Test func projectAssist_plusUser_doesntTouchStarter() throws {
        let svc = EntitlementService.shared
        let originalUsed = svc.starterProjectAssistUsed
        let originalTier = svc.tier
        let originalMonthly = svc.monthlyUsed
        defer {
            svc.debugSetStarterProjectAssistUsed(originalUsed)
            svc.setTier(originalTier)
            svc.debugSetMonthlyUsed(originalMonthly)
        }
        svc.setTier(.plusMonthly)
        svc.debugSetStarterProjectAssistUsed(false)
        svc.debugSetMonthlyUsed(0)

        try svc.tryConsumeProjectAssist()

        // Plus paths consume from the monthly bucket; the starter
        // flag stays untouched.
        #expect(svc.starterProjectAssistUsed == false)
        #expect(svc.monthlyUsed == 1)
    }
}
