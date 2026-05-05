import Foundation
import CoreData

/// One typed-note capture from a Contribute Mode session. Stored as a
/// first-class entity (rather than joined into `JournalEntry.content`) so
/// that the entry detail view can render text/voice/photo captures in
/// chronological order with per-panel edit and delete affordances.
///
/// `entry.content` remains the source of truth for AI analysis and search,
/// regenerated from sorted text segments + voice transcripts whenever any
/// capture changes.
@objc(TextSegment)
public class TextSegment: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var text: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var entry: JournalEntry?
}
