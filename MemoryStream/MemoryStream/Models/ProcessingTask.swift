import Foundation
import CoreData

/// Per-device runtime state for AI processing. **Lives in the Local
/// store, not the Cloud store** — see `StorageService` configuration
/// split and `docs/architecture/cloudkit-cold-launch-investigation.md`.
/// The reason: a ProcessingTask describes *this device's progress*
/// on organizing an entry; the *result* (OrganizePass, mentions,
/// topics, etc.) syncs via the Cloud store. Syncing the task itself
/// would produce ghost spinners on other devices and stale
/// "processing" states if the device crashed mid-pass.
///
/// Because the task lives in a different store from `JournalEntry`,
/// the previous bidirectional relationship is gone — Core Data
/// can't cross stores. Use `entryId: UUID` as the foreign key;
/// `JournalEntry.latestProcessingTask()` queries by that.
@objc(ProcessingTask)
public class ProcessingTask: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var taskType: String // "entity_extraction"
    @NSManaged public var status: String // "pending", "processing", "completed", "failed"
    @NSManaged public var progressDescription: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var processedAt: Date?
    @NSManaged public var errorMessage: String?
}

// MARK: - Status

extension ProcessingTask {
    enum Status: String {
        case pending = "pending"
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"
    }

    var statusEnum: Status {
        Status(rawValue: status) ?? .pending
    }
}
