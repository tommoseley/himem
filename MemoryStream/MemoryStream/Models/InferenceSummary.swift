import Foundation
import CoreData

@objc(InferenceSummary)
public class InferenceSummary: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var summaryText: String
    @NSManaged public var feedbackState: String? // "confirmed", "edited", "ignored", nil (pending)
    @NSManaged public var feedbackAt: Date?
    @NSManaged public var userCorrection: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var entry: JournalEntry?
}

// MARK: - Feedback State

extension InferenceSummary {
    enum FeedbackState: String {
        case confirmed = "confirmed"
        case edited = "edited"
        case ignored = "ignored"

        var displayLabel: String {
            switch self {
            case .confirmed: return "Confirmed"
            case .edited: return "Edited"
            case .ignored: return "Ignored"
            }
        }
    }

    var feedbackStateEnum: FeedbackState? {
        guard let feedbackState else { return nil }
        return FeedbackState(rawValue: feedbackState)
    }

    var isPending: Bool {
        feedbackState == nil
    }
}
