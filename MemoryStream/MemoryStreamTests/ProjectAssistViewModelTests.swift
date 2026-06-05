import Testing
import Foundation
import CoreData
@testable import HiMem

/// Tests for `ProjectAssistViewModel` — the network-call orchestrator
/// behind "Find the thread". Locks:
/// - Plus-gated: a non-Plus run is a no-op (no API call, no persistence)
/// - Persistence: lastThreadSummary + lastThreadGeneratedAt land on the
///   Project for the "Summarized" state to survive launches
/// - dismissSummary clears local state
/// - Failure path: a thrown error leaves the project's persisted state
///   untouched and surfaces a user-facing error
/// - Payload shape: title / topics / summary / date only
///   (Projects · MVP spec § "What it sees")
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
        private(set) var callCount: Int = 0

        init(summary: String) { self.summary = summary }

        func generateProjectThread(
            projectName: String,
            projectGoal: String?,
            memories: [ClaudeAPIService.ProjectMemoryInput],
            tier: String
        ) async throws -> ClaudeAPIService.ProjectAssistResult {
            callCount += 1
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

    @MainActor
    private final class ErrorCapture {
        private(set) var last: AppError?
        func record(_ error: AppError) { last = error }
    }

    // MARK: - Plus-gate

    @Test func run_freeUser_doesNothing() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)
        let api = SuccessAPI(summary: "should never be called")
        let vm = ProjectAssistViewModel(
            storage: storage,
            isPlus: { false },
            api: api,
            readTier: { "free" }
        )

        await vm.run(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        #expect(api.callCount == 0)
        #expect(project.lastThreadSummary == nil)
        #expect(project.lastThreadGeneratedAt == nil)
    }

    // MARK: - Success path

    @Test func run_plusUser_success_persistsSummary() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)
        let api = SuccessAPI(summary: "The thread runs through gardening.")
        let vm = ProjectAssistViewModel(
            storage: storage,
            isPlus: { true },
            api: api,
            readTier: { "plus" }
        )

        await vm.run(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        #expect(project.lastThreadSummary == "The thread runs through gardening.")
        #expect(project.lastThreadGeneratedAt != nil)
        #expect(api.capturedTier == "plus")
        #expect(api.capturedProjectName == "Building HiMem")
        #expect(api.capturedProjectGoal == "Ship v1")
        #expect(api.capturedMemories.count == 2)
    }

    // MARK: - Failure path

    @Test func run_failure_doesNotPersist() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)
        let captured = ErrorCapture()
        let api = ThrowingAPI(error: StubError(detail: "Anthropic timeout"))
        let vm = ProjectAssistViewModel(
            storage: storage,
            isPlus: { true },
            api: api,
            readTier: { "plus" },
            reportError: { captured.record($0) }
        )

        await vm.run(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        #expect(project.lastThreadSummary == nil)
        #expect(project.lastThreadGeneratedAt == nil)

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

    // MARK: - dismissSummary

    @Test func dismissSummary_clearsPersistedFields() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext)
        project.lastThreadSummary = "stale"
        project.lastThreadGeneratedAt = Date()
        try storage.viewContext.save()

        let vm = ProjectAssistViewModel(
            storage: storage,
            isPlus: { true },
            api: SuccessAPI(summary: "x")
        )
        vm.dismissSummary(projectId: project.id)
        storage.viewContext.refreshAllObjects()

        #expect(project.lastThreadSummary == nil)
        #expect(project.lastThreadGeneratedAt == nil)
    }

    // MARK: - Payload shape

    @Test func run_passesTopicsTitleSummaryDateOnly() async throws {
        let storage = StorageService(inMemory: true)
        let project = try makeProject(in: storage.viewContext, memoryCount: 1)
        let api = SuccessAPI(summary: "result")
        let vm = ProjectAssistViewModel(
            storage: storage,
            isPlus: { true },
            api: api,
            readTier: { "plus" }
        )

        await vm.run(projectId: project.id)

        #expect(api.capturedMemories.count == 1)
        let memInput = api.capturedMemories[0]
        #expect(memInput.title == "Memory 0")
        #expect(memInput.topics == ["Garden"])
        // Date encoded as ISO-8601, summary nil (no AI summary on the
        // fixture entries).
        #expect(memInput.summary == nil)
        #expect(memInput.createdAt.contains("T"))
    }
}
