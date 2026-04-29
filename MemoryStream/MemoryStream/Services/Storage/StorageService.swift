import Foundation
import CoreData
import CloudKit

final class StorageService {
    static let shared = StorageService()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private init() {
        container = NSPersistentCloudKitContainer(name: "MemoryStream")
        let description = container.persistentStoreDescriptions.first!
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Try with CloudKit
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.himem.app"
        )

        var loadError: Error?
        container.loadPersistentStores { storeDescription, error in
            if let error {
                loadError = error
            } else {
                print("✅ Core Data store loaded successfully")
                print("✅ Store URL: \(storeDescription.url?.absoluteString ?? "unknown")")
                print("✅ CloudKit container: \(storeDescription.cloudKitContainerOptions?.containerIdentifier ?? "none")")
            }
        }

        // If CloudKit failed, retry without it — local-only fallback
        if let error = loadError {
            let nsError = error as NSError
            print("⚠️ CloudKit store failed: \(nsError)")
            print("⚠️ Domain: \(nsError.domain), Code: \(nsError.code)")
            print("⚠️ Description: \(nsError.localizedDescription)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("⚠️ Underlying: \(underlying)")
                if let ck = underlying.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("⚠️ CloudKit error: \(ck)")
                }
            }
            print("⚠️ Full userInfo: \(nsError.userInfo)")
            print("⚠️ Retrying without CloudKit (local-only).")
            description.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [description]
            container.loadPersistentStores { _, error in
                if let error {
                    fatalError("Core Data failed to load even without CloudKit: \(error.localizedDescription)")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Initialize CloudKit schema on first run — required for sync to work
        #if DEBUG
        do {
            try container.initializeCloudKitSchema(options: [])
            print("✅ CloudKit schema initialized")
        } catch {
            print("⚠️ CloudKit schema init failed: \(error)")
        }
        #endif

        // Listen for remote changes from other devices
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            print("🔄 [SYNC] NSPersistentStoreRemoteChange received")
            self?.viewContext.perform {
                self?.viewContext.refreshAllObjects()
            }
        }

        // CloudKit container event diagnostics
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let typeNames = ["setup", "import", "export"]
            let typeName = event.type.rawValue < typeNames.count ? typeNames[event.type.rawValue] : "\(event.type.rawValue)"
            print("☁️ [CK] type=\(typeName) succeeded=\(event.succeeded) error=\(event.error?.localizedDescription ?? "nil")")
        }

        // Ensure CloudKit database subscription exists for push notifications
        ensureCloudKitSubscription()
    }

    /// Manually create the CKDatabaseSubscription if the container's setup phase
    /// didn't run (e.g. due to BGTaskScheduler failures on iPad).
    private func ensureCloudKitSubscription() {
        let ckContainer = CKContainer(identifier: "iCloud.com.himem.app")
        let db = ckContainer.privateCloudDatabase
        let subscriptionID = "com.apple.coredata.cloudkit.private.subscription"

        // Check if subscription already exists
        db.fetch(withSubscriptionID: subscriptionID) { subscription, error in
            if subscription != nil {
                print("☁️ [CK] Subscription already exists")
                return
            }

            // Create it
            let newSub = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let notifInfo = CKSubscription.NotificationInfo()
            notifInfo.shouldSendContentAvailable = true
            newSub.notificationInfo = notifInfo

            db.save(newSub) { saved, error in
                if let saved {
                    print("☁️ [CK] Created subscription: \(saved.subscriptionID)")
                } else if let error {
                    print("☁️ [CK] Failed to create subscription: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Test-only initializer: in-memory Core Data store with no disk persistence.
    init(inMemory: Bool) {
        precondition(inMemory, "Use .shared for on-disk storage")
        container = NSPersistentCloudKitContainer(name: "MemoryStream")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        // No CloudKit options for in-memory test store
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("In-memory Core Data failed to load: \(error.localizedDescription)")
            }
        }
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

    func createEntry(content: String, inputType: JournalEntry.InputType, sourceDevice: JournalEntry.SourceDevice = .phone, title: String? = nil, context: NSManagedObjectContext? = nil) throws -> JournalEntry {
        let ctx = context ?? viewContext
        let entry = JournalEntry(context: ctx)
        entry.id = UUID()
        entry.content = content
        entry.inputType = inputType.rawValue
        entry.sourceDevice = sourceDevice.rawValue
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

    // MARK: - Project Operations

    func createProject(name: String, purpose: String? = nil, context: NSManagedObjectContext? = nil) throws -> Project {
        let ctx = context ?? viewContext
        let project = Project(context: ctx)
        project.id = UUID()
        project.name = name
        project.purpose = purpose
        project.createdAt = Date()
        project.updatedAt = Date()
        try save(context: ctx)
        return project
    }

    // MARK: - Topic Operations

    func findOrCreateTopic(name: String, paletteKey: String? = nil, context: NSManagedObjectContext? = nil) throws -> Topic {
        let ctx = context ?? viewContext
        let slug = TopicSlugHelper.slugify(name)

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
