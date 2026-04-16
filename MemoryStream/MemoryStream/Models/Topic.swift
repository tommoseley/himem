import Foundation
import CoreData

@objc(Topic)
public class Topic: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var slug: String
    @NSManaged public var inferredAt: Date
    @NSManaged public var entries: NSSet?
}

// MARK: - Relationships

extension Topic {
    var entriesArray: [JournalEntry] {
        let set = entries as? Set<JournalEntry> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }
    }

    var entryCount: Int {
        (entries as? Set<JournalEntry>)?.count ?? 0
    }
}

// MARK: - Fetch Requests

extension Topic {
    static func fetchAll() -> NSFetchRequest<Topic> {
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Topic.name, ascending: true)]
        return request
    }
}
