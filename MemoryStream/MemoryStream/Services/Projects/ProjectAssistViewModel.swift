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

/// Per-device "kept" marker for a project's thread summary — the project
/// analogue of the memory reorganize draft's "Keep this version" commit,
/// and of `BenchClipReviewStore` for clip review-state.
///
/// **Keyed on the summary's `lastThreadGeneratedAt` instant**, so a fresh
/// "Find the thread again" (which stamps a new generated-at) automatically
/// falls back to Draft — no explicit un-keep needed. Persisted per-device in
/// UserDefaults: like `reviewed` on clips, this is a review-state noise signal,
/// not load-bearing content, so per-device is honest for v1 and needs **no
/// CloudKit schema change / deploy** (the summary text + generated-at already
/// sync; only the glance-state is local). Cross-device kept-sync rides the same
/// post-v1 UX-metadata migration as the clip `reviewed` flag.
enum ProjectThreadReviewStore {
    private static let key = "com.himem.project.threadSummaryKeptAt"

    /// Kept iff a kept-instant is recorded for this project that matches the
    /// summary's current generated-at.
    static func isKept(projectId: UUID, generatedAt: Date?) -> Bool {
        guard let generatedAt, let stored = map()[projectId.uuidString] else { return false }
        return abs(stored - generatedAt.timeIntervalSinceReferenceDate) < 0.5
    }

    static func markKept(projectId: UUID, generatedAt: Date?) {
        guard let generatedAt else { return }
        var m = map()
        m[projectId.uuidString] = generatedAt.timeIntervalSinceReferenceDate
        UserDefaults.standard.set(m, forKey: key)
    }

    private static func map() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }
}
