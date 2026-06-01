import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `ProjectAssistViewModel` — the network-call
/// orchestrator behind "Find the thread". Locks:
/// - Debit-on-success only (a network failure does NOT burn an assist)
/// - Persistence: lastThreadSummary + lastThreadGeneratedAt land
///   on the Project for the "Summarized" state to survive launches
/// - dismissSummary clears local state (no refund — the work
///   already happened)
/// - The request payload only sees title / topics / summary / date
///   (spec § "What it sees") — Plan A integration test, with the
///   builder-level test in `ProjectAssistAPITests`.
@MainActor
@Suite(.serialized)
struct ProjectAssistViewModelTests {

    private struct StubError: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    private final class SuccessAPI: ProjectAssistAPI, @unchecked Sendable {
        let summary: String
        private(set) var capturedProjectName: String = ""
        private(set) var capturedProjectGoal: String?
        private(set) var capturedMemories: [ClaudeAPIService.ProjectMemoryInput] = []
        private(set) var capturedTier: String = ""

        init(summary: String) { self.summary = summary }

        func generateProjectThread(
            projectName: String,
            projectGoal: String?,
            memories: [ClaudeAPIService.ProjectMemoryInput],
            tier: String
        ) async throws -> ClaudeAPIService.ProjectAssistResult {
            capturedProjectName = projectName
            capturedProjectGoal = projectGoal
            capturedMemories = memories
            capturedTier = tier
            return ClaudeAPIService.ProjectAssistResult(summary: summary)
        }
    }

    private final class ThrowingAPI: ProjectAssistAPI {
        let error: Error
        init(error: Error) { self.error = error }
        func generateProjectThread(
            projectName: String,
            projectGoal: String?,
            memories: [ClaudeAPIService.ProjectMemoryInput],
            tier: String
        ) async throws -> ClaudeAPIService.ProjectAssistResult {
            throw error
        }
    }

    private func makeProject(
        in ctx: NSManagedObjectContext,
        memoryCount: Int = 2
    ) throws -> Project {
        let topic = Topic(context: ctx)
        topic.id = UUID()
        topic.name = "Garden"
        topic.slug = "garden"
        topic.inferredAt = Date()

        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "Building HiMem"
        project.purpose = "Ship v1"
        project.createdAt = Date()
        project.updatedAt = Date()

        for i in 0..<memoryCount {
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.title = "Memory \(i)"
            entry.content = "content \(i)"
            entry.createdAt = Date(timeIntervalSinceNow: TimeInterval(-i))
            entry.inputType = "typed"
            entry.addToTopics(topic)
            project.addToEntries(entry)
        }
        try ctx.save()
        return project
    }

    // MARK: - Success path

    @Test func run_success_persistsSummaryAndDebitsAssist() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)

        // Grant a starter so the gate allows the run; debit will
        // flip the starter to used.
        // Fresh EntitlementService backed by the same in-memory
        // storage as the project — fully isolated from
        // `EntitlementService.shared` so this test can run in
        // parallel with ProjectsMVPTests' starter-consumption
        // tests without state-leaking.
        let entitlement = EntitlementService(storage: storage)
        entitlement.debugSetStarterProjectAssistUsed(false)

        let api = SuccessAPI(summary: "The thread runs through gardening.")
        let vm = ProjectAssistViewModel(
            storage: storage,
            entitlement: entitlement,
            api: api,
            readTier: { "founders" }
        )

        await vm.run(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        // Persistence: spec § "Summarized" state survives launch.
        #expect(project.lastThreadSummary == "The thread runs through gardening.")
        #expect(project.lastThreadGeneratedAt != nil)

        // Tier captured at call time matches what we injected.
        #expect(api.capturedTier == "founders")
        #expect(api.capturedProjectName == "Building HiMem")
        #expect(api.capturedProjectGoal == "Ship v1")
        #expect(api.capturedMemories.count == 2)

        // Debit: starter was unused → now used.
        #expect(entitlement.starterProjectAssistUsed == true)
    }

    // MARK: - Failure path — the money test

    /// The original bug Tom hit: pre-2026-06-01 the call site
    /// debited THEN called the (stub) endpoint. With a real server
    /// call, an Anthropic timeout or 5xx would burn an assist for
    /// nothing visible. Contract: a thrown error from the API must
    /// leave the assist counter untouched and the persisted
    /// summary nil. ErrorState gets a message so the user knows
    /// something failed.
    @Test func run_failure_doesNotDebitOrPersist() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)

        // Fresh EntitlementService backed by the same in-memory
        // storage as the project — fully isolated from
        // `EntitlementService.shared` so this test can run in
        // parallel with ProjectsMVPTests' starter-consumption
        // tests without state-leaking.
        let entitlement = EntitlementService(storage: storage)
        entitlement.debugSetStarterProjectAssistUsed(false)

        // Capture closure — scoped to this test, no shared state.
        let captured = ErrorCapture()

        let api = ThrowingAPI(error: StubError(detail: "Anthropic timeout"))
        let vm = ProjectAssistViewModel(
            storage: storage,
            entitlement: entitlement,
            api: api,
            readTier: { "founders" },
            reportError: { captured.record($0) }
        )

        await vm.run(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        // No debit.
        #expect(entitlement.starterProjectAssistUsed == false)

        // No persisted summary — the project is in the same state
        // as before the failed run.
        #expect(project.lastThreadSummary == nil)
        #expect(project.lastThreadGeneratedAt == nil)

        // User-facing error surfaced via the injected sink — no
        // dependence on `ErrorState.shared` so this can run in
        // parallel with other suites that read/write it.
        guard let recorded = captured.last else {
            Issue.record("Expected reportError to fire on API failure")
            return
        }
        switch recorded {
        case .processingFailed(let msg):
            #expect(msg.contains("Anthropic timeout"))
        default:
            Issue.record("Expected .processingFailed, got \(recorded)")
        }
    }

    @MainActor
    private final class ErrorCapture {
        private(set) var last: AppError?
        func record(_ error: AppError) { last = error }
    }

    // MARK: - Gate respected

    @Test func run_whenCantConsumeAssist_doesNothing() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)

        // Burn the starter (Free tier) — canConsumeProjectAssist
        // is now false; the VM should bail without calling the API.
        // Fresh entitlement for isolation.
        let entitlement = EntitlementService(storage: storage)
        entitlement.setTier(.free)
        entitlement.debugSetStarterProjectAssistUsed(true)
        #expect(entitlement.canConsumeProjectAssist == false)

        let api = SuccessAPI(summary: "should never be called")
        let vm = ProjectAssistViewModel(
            storage: storage,
            entitlement: entitlement,
            api: api,
            readTier: { "free" }
        )

        await vm.run(projectId: project.id)

        #expect(project.lastThreadSummary == nil)
        #expect(api.capturedProjectName == "", "API should not have been called")
    }

    // MARK: - Dismiss

    @Test func dismissSummary_clearsPersistedFields() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)
        project.lastThreadSummary = "old thread"
        project.lastThreadGeneratedAt = Date()
        try storage.viewContext.save()

        let vm = ProjectAssistViewModel(storage: storage)
        vm.dismissSummary(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        #expect(project.lastThreadSummary == nil)
        #expect(project.lastThreadGeneratedAt == nil)
    }

    // MARK: - Memory input mapping

    @Test func run_passesTopicsTitleSummaryDateOnly() async throws {
        // Integration check on the same spec contract the
        // ProjectAssistAPITests builder test pins from the other
        // side — verify the VM's memory-input build path matches.
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext

        let topic = Topic(context: ctx)
        topic.id = UUID()
        topic.name = "Garden"
        topic.slug = "garden"
        topic.inferredAt = Date()

        let entry = JournalEntry(context: ctx)
        entry.id = UUID()
        entry.title = "Compost notes"
        entry.content = "Loooooong content that absolutely should not be sent to the server, ever."
        entry.createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        entry.inputType = "typed"
        entry.addToTopics(topic)

        let summary = InferenceSummary(context: ctx)
        summary.id = UUID()
        summary.entryId = entry.id
        summary.summaryText = "linked to gardening"
        summary.createdAt = Date()
        summary.entry = entry

        let project = Project(context: ctx)
        project.id = UUID()
        project.name = "p"
        project.purpose = nil
        project.createdAt = Date()
        project.updatedAt = Date()
        project.addToEntries(entry)
        try ctx.save()

        // Fresh EntitlementService backed by the same in-memory
        // storage as the project — fully isolated from
        // `EntitlementService.shared` so this test can run in
        // parallel with ProjectsMVPTests' starter-consumption
        // tests without state-leaking.
        let entitlement = EntitlementService(storage: storage)
        entitlement.debugSetStarterProjectAssistUsed(false)

        let api = SuccessAPI(summary: "ok")
        let vm = ProjectAssistViewModel(
            storage: storage,
            entitlement: entitlement,
            api: api,
            readTier: { "founders" }
        )

        await vm.run(projectId: project.id)

        #expect(api.capturedMemories.count == 1)
        let m = api.capturedMemories[0]
        #expect(m.title == "Compost notes")
        #expect(m.topics == ["Garden"])
        #expect(m.summary == "linked to gardening")
        // The full content is NOT in the request — the only thing
        // that goes is the AI summary.
        #expect(!(m.summary ?? "").contains("Loooooong"))
    }
}
