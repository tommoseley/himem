import Foundation
import CoreData

@objc(JournalEntry)
public class JournalEntry: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String?
    @NSManaged public var content: String
    @NSManaged public var inputType: String // "siri", "voice_in_app", "typed"
    @NSManaged public var audioFilePath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var isRecycled: Bool
    @NSManaged public var recycledAt: Date?
    @NSManaged public var extractedEntities: NSSet?
    @NSManaged public var mediaReferences: NSSet?
    @NSManaged public var processingTasks: NSSet?
    @NSManaged public var inferenceSummary: InferenceSummary?
    @NSManaged public var topics: NSSet?
    @NSManaged public var projects: NSSet?
}

// MARK: - Input Type

extension JournalEntry {
    enum InputType: String {
        case siri = "siri"
        case voiceInApp = "voice_in_app"
        case typed = "typed"
        case camera = "camera"
        case composed = "composed"

        var displayLabel: String {
            switch self {
            case .siri: return "Captured via Siri"
            case .voiceInApp: return "Voice in app"
            case .typed: return "Typed"
            case .camera: return "Photo / Video"
            case .composed: return "Composed"
            }
        }
    }

    var inputTypeEnum: InputType {
        InputType(rawValue: inputType) ?? .typed
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch inputTypeEnum {
        case .siri, .voiceInApp: return "Hands-free capture"
        case .typed: return "Journal entry"
        case .camera: return "Photo / Video capture"
        case .composed: return "Memory"
        }
    }
}

// MARK: - Relationships

extension JournalEntry {
    var entitiesArray: [ExtractedEntity] {
        let set = extractedEntities as? Set<ExtractedEntity> ?? []
        return set.sorted { $0.createdAt < $1.createdAt }
    }

    var topicsArray: [Topic] {
        let set = topics as? Set<Topic> ?? []
        return set.sorted { $0.name < $1.name }
    }

    var mediaReferencesArray: [MediaReference] {
        let set = mediaReferences as? Set<MediaReference> ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var latestProcessingTask: ProcessingTask? {
        let set = processingTasks as? Set<ProcessingTask> ?? []
        return set.sorted { $0.createdAt > $1.createdAt }.first
    }
}

// MARK: - Fetch Requests

extension JournalEntry {
    static func fetchAllChronological() -> NSFetchRequest<JournalEntry> {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == NO OR isRecycled == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        return request
    }

    static func fetchByTopic(_ topic: Topic) -> NSFetchRequest<JournalEntry> {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "ANY topics == %@", topic)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        return request
    }
}
