import Foundation
import CoreData

final class StorageService {
    static let shared = StorageService()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private init() {
        container = NSPersistentContainer(name: "MemoryStream")
        let description = container.persistentStoreDescriptions.first!
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - Journal Entry Operations

    func createEntry(content: String, inputType: JournalEntry.InputType, title: String? = nil, context: NSManagedObjectContext? = nil) throws -> JournalEntry {
        let ctx = context ?? viewContext
        let entry = JournalEntry(context: ctx)
        entry.id = UUID()
        entry.content = content
        entry.inputType = inputType.rawValue
        entry.title = title
        entry.createdAt = Date()
        try save(context: ctx)
        return entry
    }

    // MARK: - Processing Task Operations

    func createProcessingTask(for entry: JournalEntry, context: NSManagedObjectContext? = nil) throws -> ProcessingTask {
        let ctx = context ?? viewContext
        let task = ProcessingTask(context: ctx)
        task.id = UUID()
        task.entryId = entry.id
        task.taskType = "entity_extraction"
        task.status = ProcessingTask.Status.pending.rawValue
        task.createdAt = Date()
        task.entry = entry
        try save(context: ctx)
        return task
    }

    func updateTaskStatus(_ task: ProcessingTask, status: ProcessingTask.Status, progress: String? = nil, error: String? = nil, context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        task.status = status.rawValue
        task.progressDescription = progress
        if status == .completed || status == .failed {
            task.processedAt = Date()
        }
        if let error {
            task.errorMessage = error
        }
        try save(context: ctx)
    }

    // MARK: - Extracted Entity Operations

    func createEntity(entryId: UUID, type: ExtractedEntity.EntityType, value: String, confidence: Double, rangeLocation: Int = -1, rangeLength: Int = 0, method: String = "cloud", entry: JournalEntry, context: NSManagedObjectContext? = nil) throws -> ExtractedEntity {
        let ctx = context ?? viewContext
        let entity = ExtractedEntity(context: ctx)
        entity.id = UUID()
        entity.entryId = entryId
        entity.entityType = type.rawValue
        entity.value = value
        entity.confidenceScore = confidence
        entity.textRangeLocation = Int32(rangeLocation)
        entity.textRangeLength = Int32(rangeLength)
        entity.processingMethod = method
        entity.createdAt = Date()
        entity.entry = entry
        try save(context: ctx)
        return entity
    }

    // MARK: - Inference Summary Operations

    func createInferenceSummary(entryId: UUID, summaryText: String, entry: JournalEntry, context: NSManagedObjectContext? = nil) throws -> InferenceSummary {
        let ctx = context ?? viewContext
        let summary = InferenceSummary(context: ctx)
        summary.id = UUID()
        summary.entryId = entryId
        summary.summaryText = summaryText
        summary.createdAt = Date()
        summary.entry = entry
        try save(context: ctx)
        return summary
    }

    func updateFeedback(_ summary: InferenceSummary, state: InferenceSummary.FeedbackState, correction: String? = nil, context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        summary.feedbackState = state.rawValue
        summary.feedbackAt = Date()
        summary.userCorrection = correction
        try save(context: ctx)
    }

    // MARK: - Media Reference Operations

    func createMediaReference(for entry: JournalEntry, localIdentifier: String, mediaType: MediaReference.MediaType, context: NSManagedObjectContext? = nil) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.entryId = entry.id
        ref.osIdentifier = localIdentifier
        ref.mediaType = mediaType.rawValue
        ref.isAccessible = true
        ref.createdAt = Date()
        ref.entry = entry
        try save(context: ctx)
        return ref
    }

    func updateThumbnailFilename(_ ref: MediaReference, filename: String, context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        ref.thumbnailCacheFilename = filename
        try save(context: ctx)
    }

    // MARK: - Topic Operations

    func findOrCreateTopic(name: String, paletteKey: String? = nil, context: NSManagedObjectContext? = nil) throws -> Topic {
        let ctx = context ?? viewContext
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")

        let request = NSFetchRequest<Topic>(entityName: "Topic")
        request.predicate = NSPredicate(format: "slug == %@", slug)
        request.fetchLimit = 1

        if let existing = try ctx.fetch(request).first {
            return existing
        }

        let topic = Topic(context: ctx)
        topic.id = UUID()
        topic.name = name
        topic.slug = slug
        topic.inferredAt = Date()
        topic.paletteKey = paletteKey
        try save(context: ctx)
        return topic
    }
}
