import Foundation
import CoreData

/// Read-only queries over recycled entries. Extracted from
/// `EntryLifecycleService` (CRAP audit Batch 3) so that file stays
/// focused on lifecycle verbs (create, edit, append, delete, recycle,
/// restore, feedback) instead of carrying its own query surface.
///
/// All methods are pure functions of the persistent store contents
/// — no side effects, no mutation, no processing engine. Safe to
/// instantiate per-call or hold long-lived; identity doesn't matter.
@MainActor
final class EntryQueryService {

    private let storage: StorageService

    init(storage: StorageService) {
        self.storage = storage
    }

    /// Fetches every recycled entry, sorted by `recycledAt`
    /// descending (most-recently-binned first), mapped to display
    /// models so the caller doesn't reach into Core Data.
    func loadRecycledEntries() -> [EntryDisplayModel] {
        do {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "isRecycled == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.recycledAt, ascending: false)]
            return try storage.viewContext.fetch(request).map { EntryMapper.mapToDisplayModel($0) }
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
            return []
        }
    }

    /// Counts recycled entries whose topics include the given name.
    /// Case-sensitive exact match (locked by characterization test).
    func recycledCountForTopic(_ topicName: String) -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == YES AND ANY topics.name == %@", topicName)
        return (try? storage.viewContext.count(for: request)) ?? 0
    }

    /// Counts every recycled entry without materializing the rows.
    /// Cheap; use this in derived state instead of
    /// `loadRecycledEntries().count`.
    func recycledCount() -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == YES")
        return (try? storage.viewContext.count(for: request)) ?? 0
    }
}
