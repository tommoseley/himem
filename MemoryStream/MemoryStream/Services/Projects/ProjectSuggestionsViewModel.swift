import Foundation
import CoreData
import Combine

/// Coordinates the suggested-project-membership feature for a
/// single project: runs the local suggester, maps results into
/// `SuggestedMemoriesSheet.Suggestion`, and resolves the sheet's
/// commit (Add N) by adding selected entries to the project and
/// persisting the unselected as dismissed.
///
/// Commit semantics on Add N:
/// - Selected entries → `project.addToEntries(_:)`, Core Data save.
/// - Unselected entries (rows the user saw but did not check) →
///   `ProjectSuggestionDismissalStore.dismiss(...)` so they don't
///   resurface tomorrow.
/// - Cancel (user closes without committing) is handled by the
///   sheet itself — `onCommit` isn't called, nothing changes.
///
/// That maps the existing sheet's ring-selection UX onto persistent
/// dismissal without adding a separate Skip control. "I reviewed
/// these 5, added 3, skipped 2" is the user's mental model.
@MainActor
final class ProjectSuggestionsViewModel: ObservableObject {

    @Published private(set) var suggestions: [SuggestedMemoriesSheet.Suggestion] = []

    private let dismissalStore: ProjectSuggestionDismissalStore
    private let storage: StorageService
    private var dismissalCancellable: AnyCancellable?

    init(
        dismissalStore: ProjectSuggestionDismissalStore = .shared,
        storage: StorageService = .shared
    ) {
        self.dismissalStore = dismissalStore
        self.storage = storage
    }

    /// Recomputes suggestions for `projectId` from the current
    /// Core Data state. Safe to call from any UI lifecycle hook
    /// (`.onAppear`, after sheet dismiss, after add-memory commit).
    func reload(projectId: UUID) {
        let ctx = storage.viewContext
        guard let project = fetchProject(id: projectId, in: ctx) else {
            suggestions = []
            return
        }
        let dismissed = dismissalStore.dismissed(forProject: projectId)
        let candidates = ProjectMembershipSuggester.candidates(
            for: project,
            in: ctx,
            dismissed: dismissed
        )
        suggestions = candidates.compactMap { suggestion(from: $0, in: ctx) }
    }

    /// Commits the user's selection from `SuggestedMemoriesSheet`.
    /// Selected = add to project; unselected (anything we showed
    /// that isn't in `acceptedIDs`) = persistent dismissal.
    func commit(acceptedIDs: Set<UUID>, projectId: UUID) {
        let shownIDs = Set(suggestions.map(\.id))
        let toAdd = acceptedIDs.intersection(shownIDs)
        let toDismiss = shownIDs.subtracting(acceptedIDs)

        let ctx = storage.viewContext
        guard let project = fetchProject(id: projectId, in: ctx) else { return }

        for entryId in toAdd {
            guard let entry = fetchEntry(id: entryId, in: ctx) else { continue }
            project.addToEntries(entry)
        }

        if !toAdd.isEmpty {
            do {
                try ctx.save()
            } catch {
                NSLog("[Himem][Projects] commit suggestions save failed: \(error.localizedDescription)")
            }
        }

        for entryId in toDismiss {
            dismissalStore.dismiss(entryId: entryId, forProject: projectId)
        }

        reload(projectId: projectId)
    }

    // MARK: - Mapping

    private func suggestion(
        from sm: SuggestedMembership,
        in ctx: NSManagedObjectContext
    ) -> SuggestedMemoriesSheet.Suggestion? {
        guard let entry = fetchEntry(id: sm.entryId, in: ctx) else { return nil }

        let displayTitle: String
        if let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            displayTitle = title
        } else {
            let preview = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = preview.split(separator: " ", omittingEmptySubsequences: true).prefix(8)
            displayTitle = words.joined(separator: " ") + (preview.count > words.joined(separator: " ").count ? "…" : "")
        }

        // Reason row: literal topic-match list. Plan B is local —
        // no AI rationale. When the AI re-rank lands in v1.1, this
        // text gets replaced with the model's one-sentence reason
        // ("Mentions Studio and project synthesis — the same
        // thread you're pulling on here.").
        let rationale = "Matches " + sm.matchedTopics.joined(separator: " · ")

        // Confidence band: 1 topic match = Maybe, ≥2 = Likely.
        // Cheap heuristic that mostly aligns with what the AI
        // re-rank would say; refinable when the AI lands.
        let confidence: SuggestedMemoriesSheet.Suggestion.Confidence =
            sm.matchedTopics.count >= 2 ? .likely : .maybe

        return SuggestedMemoriesSheet.Suggestion(
            id: sm.entryId,
            title: displayTitle,
            createdAt: entry.createdAt,
            rationale: rationale,
            confidence: confidence
        )
    }

    // MARK: - Core Data helpers

    private func fetchProject(id: UUID, in ctx: NSManagedObjectContext) -> Project? {
        let req = NSFetchRequest<Project>(entityName: "Project")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }

    private func fetchEntry(id: UUID, in ctx: NSManagedObjectContext) -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }
}
