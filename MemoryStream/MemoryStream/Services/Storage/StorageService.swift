import Foundation
import CoreData
import CloudKit

final class StorageService {
    static let shared = StorageService()

    /// Base type so the test path can use a plain `NSPersistentContainer`
    /// (no CloudKit). Production assigns an `NSPersistentCloudKitContainer`
    /// here; everything we call on it (`viewContext`,
    /// `newBackgroundContext`, `persistentStoreCoordinator`,
    /// `persistentStoreDescriptions`) is on the base class. CloudKit-only
    /// APIs like `initializeCloudKitSchema` get a downcast inside the init
    /// that needs them.
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Test-only model cache. Multiple `init(inMemory:)` calls during a
    /// parallel test run each used to load their own copy of the model,
    /// producing "Class X is implemented in two NSManagedObjectModels"
    /// warnings that escalate to test-process crashes. Not used in
    /// production — the singleton lets `NSPersistentCloudKitContainer(name:)`
    /// auto-discover and configure the model itself, which it does in a
    /// way that the explicit-model overload doesn't quite match for the
    /// CloudKit-mirroring entities (`NSCKImportOperation` and friends).
    private static let cachedModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "MemoryStream", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to locate MemoryStream Core Data model in main bundle.")
        }
        return model
    }()

    private init() {
        let cloudKitContainer = NSPersistentCloudKitContainer(name: "MemoryStream")
        container = cloudKitContainer

        // ALL store-description options must be set before
        // `loadPersistentStores` so the persistent coordinator sees them
        // when it loads the store (Apple, WWDC "Sync a Core Data store
        // with the CloudKit public database"). Setting them after the load
        // contributes to the spurious "different NSManagedObjectModel"
        // warnings that Tom's launch console showed on 2026-05-09.
        let description = container.persistentStoreDescriptions.first!
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.himem.app"
        )

        var loadError: Error?
        LaunchSignposter.interval("storage.loadPersistentStores") {
            container.loadPersistentStores { _, error in
                if let error { loadError = error }
            }
        }

        // CloudKit-backed load failed (rare — typically a transient setup
        // issue). Strip CloudKit options and try once more so the user
        // gets a working local store; sync just won't happen this session.
        if loadError != nil {
            description.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [description]
            LaunchSignposter.interval("storage.loadPersistentStores.fallback") {
                container.loadPersistentStores { _, error in
                    if let error {
                        fatalError("Core Data failed to load even without CloudKit: \(error.localizedDescription)")
                    }
                }
            }
        }

        // viewContext configuration runs AFTER `loadPersistentStores` per
        // Apple's WWDC pattern — ensures the store coordinator has the
        // store attached before we set merge / query-generation behavior.
        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Lets us filter changes by origin in `NSManagedObjectContextObjectsDidChange`
        // observers — distinguishes user edits from CloudKit imports.
        viewContext.transactionAuthor = "viewContext"
        // Drops faults that point at deleted CloudKit records instead of
        // throwing on access — important when sync deletes a record we
        // had cached.
        viewContext.shouldDeleteInaccessibleFaults = true
        // Pins reads to the current generation so a CloudKit import in
        // flight can't change rows out from under an in-progress query.
        try? viewContext.setQueryGenerationFrom(.current)

        #if DEBUG
        // Schema discovery is a CloudKit chatter bomb (multiple round
        // trips, dozens of log lines) and only needs to run once per
        // schema version per device. The flag is debug-only so a
        // production user never gets here even if they install a
        // debug build by accident.
        let schemaInitKey = "com.himem.cloudkit.schemaInitializedV1"
        if !UserDefaults.standard.bool(forKey: schemaInitKey) {
            LaunchSignposter.interval("storage.initializeCloudKitSchema") {
                try? cloudKitContainer.initializeCloudKitSchema(options: [])
            }
            UserDefaults.standard.set(true, forKey: schemaInitKey)
        }
        #endif

        // Listen for remote changes from other devices. With
        // `automaticallyMergesChangesFromParent` true, the viewContext
        // already absorbs CloudKit imports — the prior `refreshAllObjects`
        // here was redundant and (per the 2026-04-29 sync-asymmetry doc)
        // didn't help the iPad case anyway.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            // Hook left in place for future targeted reload work; the
            // auto-merge above is sufficient for the common path.
        }
    }

    /// Test-only initializer: in-memory Core Data store with no disk
    /// persistence and no CloudKit. Tests don't exercise CloudKit, so plain
    /// `NSPersistentContainer` is the right type — no mirroring entities,
    /// faster init, no possibility of CloudKit-related model warnings.
    init(inMemory: Bool) {
        precondition(inMemory, "Use .shared for on-disk storage")
        container = NSPersistentContainer(name: "MemoryStream", managedObjectModel: Self.cachedModel)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
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

    /// Creates a `.note` fragment — a MediaReference whose body lives in
    /// the `text` field rather than referencing an external asset. Replaces
    /// the legacy `TextSegment` entity.
    func createNoteFragment(for entry: JournalEntry, text: String, createdAt: Date = Date(), context: NSManagedObjectContext? = nil) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.entryId = entry.id
        ref.osIdentifier = ""
        ref.mediaType = MediaReference.MediaType.note.rawValue
        ref.isAccessible = true
        ref.createdAt = createdAt
        ref.text = text
        ref.entry = entry
        try save(context: ctx)
        return ref
    }

    /// Creates a `.voice` fragment with the audio filename as
    /// `osIdentifier` and the speech transcript on the ref. Replaces the
    /// legacy `JournalEntry.audioFilePath` slot for in-app voice
    /// captures.
    func createVoiceFragment(for entry: JournalEntry, audioFilename: String, transcript: String, createdAt: Date = Date(), context: NSManagedObjectContext? = nil) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.entryId = entry.id
        ref.osIdentifier = audioFilename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.isAccessible = true
        ref.createdAt = createdAt
        // Strip ASR leading-noise punctuation (",.", ",…", "...") so
        // the stored transcript — and everything downstream (joined
        // entry.content, AI prompt, card snippet, full-detail body)
        // — sees clean text. Per Tom's 2026-05-27 screenshots.
        ref.transcript = JournalEntry.cleanedTranscript(transcript)
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

    /// Merges Topic entities that share a slug into a single canonical
    /// topic. CloudKit can't enforce uniqueness, so two devices that
    /// independently create the same topic before they sync end up with
    /// duplicate `Topic` rows (e.g. "Garden" 5 entries + "Garden" 10
    /// entries in the user's settings list). This sweeps them up.
    ///
    /// Strategy:
    ///   - Group all topics by slug.
    ///   - For groups of size > 1, pick the canonical topic (most entries,
    ///     ties broken by earliest `inferredAt` so the original "wins").
    ///   - Move each duplicate's entries onto the canonical, then delete
    ///     the duplicate.
    ///
    /// Safe to call frequently — fast path returns immediately when no
    /// duplicates exist. Triggered from JournalViewModel on launch and on
    /// app foregrounding.
    func mergeDuplicateTopics(context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        let topics = try ctx.fetch(request)
        let bySlug = Dictionary(grouping: topics) { $0.slug }

        var didMerge = false
        for (_, group) in bySlug where group.count > 1 {
            let sorted = group.sorted { lhs, rhs in
                let lhsCount = (lhs.entries as? Set<JournalEntry>)?.count ?? 0
                let rhsCount = (rhs.entries as? Set<JournalEntry>)?.count ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                let lhsDate = lhs.inferredAt ?? .distantPast
                let rhsDate = rhs.inferredAt ?? .distantPast
                return lhsDate < rhsDate
            }
            guard let canonical = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                if let entries = duplicate.entries as? Set<JournalEntry> {
                    for entry in entries {
                        entry.removeFromTopics(duplicate)
                        entry.addToTopics(canonical)
                    }
                }
                ctx.delete(duplicate)
                didMerge = true
            }
        }
        if didMerge {
            try save(context: ctx)
        }
    }

    /// Collapses ExtractedEntity duplicates within each entry. Two entities
    /// are duplicates when they share the same `(entryId, entityType, normalized value)`
    /// — same key the ProcessingEngine uses when deciding whether to skip an
    /// insert. The keeper is the oldest by `createdAt`; the rest are deleted.
    /// Same trigger surface as `mergeDuplicateTopics`: launch, foreground,
    /// remote change.
    func mergeDuplicateEntities(context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        let all = try ctx.fetch(request)
        let grouped = Dictionary(grouping: all) { entity -> String in
            let key = ProcessingEngine.entityKey(type: entity.entityType, value: entity.value)
            return "\(entity.entryId.uuidString)|\(key)"
        }
        var didMerge = false
        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            for duplicate in sorted.dropFirst() {
                ctx.delete(duplicate)
                didMerge = true
            }
        }
        if didMerge {
            try save(context: ctx)
        }
    }
}
