import Foundation
import CoreData
import SwiftUI

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
    }

    var entityTypeEnum: EntityType {
        EntityType(rawValue: entityType) ?? .idea
    }

    var textRange: NSRange? {
        guard textRangeLocation >= 0, textRangeLength > 0 else { return nil }
        return NSRange(location: Int(textRangeLocation), length: Int(textRangeLength))
    }
}

extension ExtractedEntity.EntityType {
    /// Type-indicator dot color for the mentions chip. Subtle — meant
    /// to be a glance signal, not a category label. Person/project/
    /// issue/idea map to four warm/cool tints that read at chip
    /// scale. Lives here so any surface (EntryExpandedView's mentions
    /// row, the eventual review sheet) reads from the same source of
    /// truth.
    ///
    /// Moved out of the assist-quota-era `AISuggestionsCard` so the
    /// styling survives that file's deletion in 8d.
    var mentionTint: Color {
        switch self {
        case .person:     return Crucible.Color.accent
        case .project:    return Crucible.Color.success
        case .issue:      return Crucible.Color.warning
        case .idea:       return Crucible.Color.info
        case .nextAction: return Crucible.Color.accent // unreached — filtered out upstream
        }
    }
}
