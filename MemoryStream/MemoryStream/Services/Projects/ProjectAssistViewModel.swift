import Foundation
import CoreData

/// Coordinates the "Find the thread" flow for a single project:
/// fetches the project's memories, builds the API request, calls
/// `/himem/project-assist`, and persists the result so the
/// "Summarized" state survives app launches.
///
/// **Debit-on-success only.** Pre-2026-06-01 the call site debited
/// before invoking (it had to — the invocation was a stub). With a
/// real server call, debiting up-front means a network failure
/// burns an assist. The fix: gate-check via
/// `EntitlementService.canConsumeProjectAssist`, do the call, only
/// then `tryConsumeProjectAssist`. If the post-call debit fails
/// after a successful synthesis — the summary already ran, the
/// user got value — surface to ErrorState (don't roll back) per the
/// same pattern as ProcessingEngine's assist-debit handling.
@MainActor
final class ProjectAssistViewModel: ObservableObject {

    @Published private(set) var isRunning: Bool = false

    private let storage: StorageService
    private let entitlement: EntitlementService
    private let api: ProjectAssistAPI
    private let readTier: @MainActor () -> String
    private let reportError: @MainActor (AppError) -> Void

    /// Protocol for the network call — same `EntryAnalyzer`-style
    /// injection so tests can drive the success / failure branches
    /// without hitting Anthropic.
    ///
    /// `reportError` defaults to the process-wide `ErrorState`
    /// singleton; tests inject a capture closure so cross-suite
    /// state on `ErrorState.shared` doesn't race with other test
    /// suites that also read/write it.
    init(
        storage: StorageService = .shared,
        entitlement: EntitlementService = .shared,
        api: ProjectAssistAPI = ClaudeAPIService.shared,
        readTier: @escaping @MainActor () -> String = { EntitlementService.shared.tier.rawValue },
        reportError: @escaping @MainActor (AppError) -> Void = { ErrorState.shared.report($0) }
    ) {
        self.storage = storage
        self.entitlement = entitlement
        self.api = api
        self.readTier = readTier
        self.reportError = reportError
    }

    /// Runs the synthesis. No-op if already running (the UI
    /// disables Run when `isRunning`, but multi-tap belt-and-
    /// suspenders).
    func run(projectId: UUID) async {
        guard !isRunning else { return }
        guard entitlement.canConsumeProjectAssist else { return }

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

            // Persist BEFORE debiting — if the save itself fails,
            // we don't want a successful debit logged against a
            // result the user can't see.
            project.lastThreadSummary = result.summary
            project.lastThreadGeneratedAt = Date()
            project.updatedAt = Date()
            try ctx.save()

            // Debit. A failure here means the user got their
            // summary but the assist counter didn't tick — surface
            // to the user (so they know something's off) but do
            // not roll back the persisted summary. Mirrors the
            // ProcessingEngine debit-after-success pattern.
            do {
                try entitlement.tryConsumeProjectAssist()
            } catch {
                NSLog("[Himem][Pricing] tryConsumeProjectAssist failed after successful run: \(error.localizedDescription)")
                reportError(.processingFailed("Couldn't record assist usage. Please retry."))
            }
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
