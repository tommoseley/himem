import Foundation
import CoreData

@objc(Project)
public class Project: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var purpose: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var entries: NSSet?
}

// MARK: - Relationships

extension Project {
    var entriesArray: [JournalEntry] {
        let set = entries as? Set<JournalEntry> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }
    }

    var entryCount: Int {
        (entries as? Set<JournalEntry>)?.count ?? 0
    }

    /// Distinct topic names across all entries in this project
    var topicNames: [String] {
        let set = entries as? Set<JournalEntry> ?? []
        var names = Set<String>()
        for entry in set {
            for topic in entry.topicsArray {
                names.insert(topic.name)
            }
        }
        return names.sorted()
    }

    @objc(addEntriesObject:)
    @NSManaged func addToEntries(_ value: JournalEntry)

    @objc(removeEntriesObject:)
    @NSManaged func removeFromEntries(_ value: JournalEntry)
}

// MARK: - Fetch Requests

extension Project {
    static func fetchAll() -> NSFetchRequest<Project> {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Project.updatedAt, ascending: false)]
        return request
    }
}
