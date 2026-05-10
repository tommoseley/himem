import Foundation
import CoreData

extension StorageService {
    /// True if at least one non-recycled JournalEntry was created since
    /// midnight (local time). Used by the daily-nudge scheduler to decide
    /// whether today still needs a reminder.
    func hasEntryCreatedToday() -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND isRecycled == NO",
            startOfDay as NSDate
        )
        request.fetchLimit = 1
        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }
}
