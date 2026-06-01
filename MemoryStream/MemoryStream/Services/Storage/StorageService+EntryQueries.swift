import Foundation
import CoreData

extension StorageService {
    /// `createdAt` of the most recent non-recycled JournalEntry, or
    /// `nil` if no entries exist. Drives the daily-nudge scheduler's
    /// chosen-time rollover (`DailyNudgePolicy.nextFireDate`): if
    /// this timestamp falls inside the chosen-time window ending
    /// now, the scheduler suppresses the next nudge.
    ///
    /// Replaces the prior `hasEntryCreatedToday()` accessor (midnight
    /// rollover Bool) — the policy needs the raw timestamp to apply
    /// the user-chosen rollover anchor.
    func mostRecentEntryAt() -> Date? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first?.createdAt
    }
}
