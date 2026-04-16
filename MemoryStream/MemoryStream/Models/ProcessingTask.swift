import Foundation
import CoreData

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
    @NSManaged public var entry: JournalEntry?
}

// MARK: - Status

extension ProcessingTask {
    enum Status: String {
        case pending = "pending"
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"

        var displayLabel: String {
            switch self {
            case .pending: return "Queued"
            case .processing: return "Parsing now"
            case .completed: return "Processed"
            case .failed: return "Failed"
            }
        }
    }

    var statusEnum: Status {
        Status(rawValue: status) ?? .pending
    }
}
