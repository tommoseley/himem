import Foundation
import CoreData

@objc(ExtractedEntity)
public class ExtractedEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var entityType: String // "project", "person", "issue", "idea", "next_action"
    @NSManaged public var value: String
    @NSManaged public var confidenceScore: Double
    @NSManaged public var textRangeLocation: Int32
    @NSManaged public var textRangeLength: Int32
    @NSManaged public var processingMethod: String // "local", "cloud"
    @NSManaged public var createdAt: Date
    @NSManaged public var entry: JournalEntry?
}

// MARK: - Entity Type

extension ExtractedEntity {
    enum EntityType: String, CaseIterable {
        case project = "project"
        case person = "person"
        case issue = "issue"
        case idea = "idea"
        case nextAction = "next_action"

        var displayLabel: String {
            switch self {
            case .project: return "Project"
            case .person: return "Person"
            case .issue: return "Issue"
            case .idea: return "Idea"
            case .nextAction: return "Next Action"
            }
        }
    }

    var entityTypeEnum: EntityType {
        EntityType(rawValue: entityType) ?? .idea
    }

    var textRange: NSRange? {
        guard textRangeLocation >= 0, textRangeLength > 0 else { return nil }
        return NSRange(location: Int(textRangeLocation), length: Int(textRangeLength))
    }
}
