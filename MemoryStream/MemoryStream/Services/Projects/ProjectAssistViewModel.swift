import Foundation
import CoreData

/// Coordinates the "Find the thread" flow for a single project:
/// fetches the project's memories, builds the API request, calls
/// `/himem/project-assist`, and persists the result so the
/// "Summarized" state survives app launches.
///
/// After the assist-quota retirement (PR 8e): Find the thread is a
/// **Plus-only** capability. Free users see the affordance disabled
/// in the surface that calls this; the gate here is defense in depth.
@MainActor
final class ProjectAssistViewModel: ObservableObject {

    @Published private(set) var isRunning: Bool = false

    private let storage: StorageService
    private let isPlus: @MainActor () -> Bool
    private let api: ProjectAssistAPI
    private let readTier: @MainActor () -> String
    private let reportError: @MainActor (AppError) -> Void

    /// Protocol for the network call — same `EntryAnalyzer`-style
    /// injection so tests can drive the success / failure branches
    /// without hitting Anthropic.
    init(
        storage: StorageService = .shared,
        isPlus: @escaping @MainActor () -> Bool = { Entitlement.shared.isPlus },
        api: ProjectAssistAPI = ClaudeAPIService.shared,
        readTier: @escaping @MainActor () -> String = { Entitlement.shared.tierLabel },
        reportError: @escaping @MainActor (AppError) -> Void = { ErrorState.shared.report($0) }
    ) {
        self.storage = storage
        self.isPlus = isPlus
        self.api = api
        self.readTier = readTier
        self.reportError = reportError
    }

    /// Runs the synthesis. No-op if already running (the UI
    /// disables Run when `isRunning`, but multi-tap belt-and-
    /// suspenders).
    func run(projectId: UUID) async {
        guard !isRunning else { return }
        guard isPlus() else { return }

        isRunning = true
        defer { isRunning = false }

        let ctx = storage.viewContext
        guard let project = fetchProject(id: projectId, in: ctx) else {
            reportError(.processingFailed("Couldn't find this project to summarize."))
            return
        }

        let memories = buildMemoryInputs(for: project)
        guard !memories.isEmpty else {
            // The gate (`ProjectAssistGate.isEnabled`) should
            // prevent this — defense in depth.
            reportError(.processingFailed("Add a memory before running Find the thread."))
            return
        }

        let tier = readTier()

        do {
            let result = try await api.generateProjectThread(
                projectName: project.name,
                projectGoal: project.purpose,
                memories: memories,
                tier: tier
            )

            project.lastThreadSummary = result.summary
            project.lastThreadGeneratedAt = Date()
            project.updatedAt = Date()
            try ctx.save()
        } catch {
            reportError(.processingFailed("Find the thread failed: \(error.localizedDescription)"))
        }
    }

    /// Clears the persisted summary so the project goes back to
    /// the pre-run state. The user can Run again (debit-able).
    func dismissSummary(projectId: UUID) {
        let ctx = storage.viewContext
        guard let project = fetchProject(id: projectId, in: ctx) else { return }
        project.lastThreadSummary = nil
        project.lastThreadGeneratedAt = nil
        project.updatedAt = Date()
        try? ctx.save()
    }

    // MARK: - Helpers

    private func fetchProject(id: UUID, in ctx: NSManagedObjectContext) -> Project? {
        let req = NSFetchRequest<Project>(entityName: "Project")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }

    private func buildMemoryInputs(for project: Project) -> [ClaudeAPIService.ProjectMemoryInput] {
        let iso = ISO8601DateFormatter()
        return project.entriesArray.map { entry in
            // Title fallback — short content excerpt when the user
            // never wrote a title. Matches the suggestions sheet's
            // fallback so the model sees something consistent.
            let title: String? = {
                if let t = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    return t
                }
                return Self.excerpt(from: entry.content)
            }()

            // Existing AI summary — per spec § "What it sees".
            // Pulled from the entry's InferenceSummary relationship
            // (set by the memory-organize pass). Nil when the
            // entry was never organized or the summary failed.
            let summary: String? = {
                guard let text = entry.inferenceSummary?.summaryText else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()

            let topics = entry.topicsArray.map(\.name)

            return ClaudeAPIService.ProjectMemoryInput(
                title: title,
                topics: topics,
                summary: summary,
                createdAt: iso.string(from: entry.createdAt)
            )
        }
    }

    private static func excerpt(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).prefix(8)
        let head = words.joined(separator: " ")
        return head + (trimmed.count > head.count ? "…" : "")
    }
}

/// Protocol seam over `ClaudeAPIService.generateProjectThread`.
/// Lets `ProjectAssistViewModelTests` inject success / failure
/// without driving the network.
protocol ProjectAssistAPI {
    func generateProjectThread(
        projectName: String,
        projectGoal: String?,
        memories: [ClaudeAPIService.ProjectMemoryInput],
        tier: String
    ) async throws -> ClaudeAPIService.ProjectAssistResult
}

extension ClaudeAPIService: ProjectAssistAPI {}
