import Foundation
import CoreData

@objc(Project)
public class Project: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    /// UI calls this "goal" — renaming to `goal` would require a
    /// CloudKit schema deploy across Development → Production (see
    /// CLAUDE.md "CloudKit Schema Changes" rule). The divergence
    /// is intentional and well-contained.
    @NSManaged public var purpose: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    /// Last Project Assist synthesis ("Find the thread" output).
    /// Persisted so the "Summarized" state survives app launches —
    /// re-opening a project re-renders the same summary without
    /// re-charging an assist. Cleared by the user via Dismiss; the
    /// assist is NOT refunded (the call already happened).
    @NSManaged public var lastThreadSummary: String?
    /// One-line short summary **derived by compressing `lastThreadSummary`**
    /// (Apple Intelligence, on-device) — never a re-reading of the memories,
    /// so it can add nothing the long summary doesn't already state. Produced
    /// in the same Find-the-thread pass and gated against the long text by
    /// `TruthReconciler`. Drives the project-list card line (falls back to the
    /// goal when there's no thread yet). CloudKit-synced — rides the next
    /// schema deploy (with `coverSource` et al.); see CLAUDE.md "CloudKit
    /// Schema Changes."
    @NSManaged public var projectSummaryShort: String?
    @NSManaged public var lastThreadGeneratedAt: Date?
    /// Soft-delete timestamp (F1 deletion lock, 2026-07-17). Non-nil = in
    /// Recently Deleted; restored by clearing it, purged after 30 days. The
    /// project's membership edges nullify on soft-delete too, so member
    /// memories survive regardless. CloudKit-synced — schema staged on Dev,
    /// Production deploy held for the batched pre-TestFlight ceremony.
    @NSManaged public var recycledAt: Date?
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
