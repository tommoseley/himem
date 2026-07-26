import Foundation
import CoreData
import CloudKit

final class StorageService {
    /// Production singleton. Under XCTest / Swift Testing this returns
    /// an in-memory container instead of the CloudKit-backed one — any
    /// test code that touches `.shared` (SwiftUI View bodies during
    /// test snapshots, `JournalEntry.latestProcessingTask` fallbacks,
    /// `CrucibleTheme.loadFromCoreData` and other init-time paths) is
    /// safe. Tests that need a fresh isolated store still use
    /// `StorageService(inMemory: true)` — this only guards accidental
    /// touches. See troika review 2026-07-09.
    static let shared: StorageService = {
        if StorageService.isRunningTests {
            return StorageService(inMemory: true)
        }
        return StorageService()
    }()

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
        // Pass `cachedModel` explicitly so the shared container uses the
        // SAME `NSManagedObjectModel` instance as the in-memory test
        // containers. Otherwise `NSPersistentCloudKitContainer(name:)`
        // auto-loads a fresh model from the bundle, and every
        // `NSManagedObject` subclass (JournalEntry, MediaReference, ...)
        // ends up "claimed" by two models — Core Data's `+entity` then
        // fails with "Failed to find a unique match" errors during any
        // test that also loads a fresh in-memory store. See troika
        // review 2026-07-09.
        let cloudKitContainer = NSPersistentCloudKitContainer(name: "MemoryStream", managedObjectModel: Self.cachedModel)
        container = cloudKitContainer

        // ALL store-description options must be set before
        // `loadPersistentStores` so the persistent coordinator sees them
        // when it loads the store (Apple, WWDC "Sync a Core Data store
        // with the CloudKit public database"). Setting them after the load
        // contributes to the spurious "different NSManagedObjectModel"
        // warnings that Tom's launch console showed on 2026-05-09.
        //
        // Two-store split (task #19, 2026-06-06):
        // - **Cloud store** holds the user's memories — JournalEntry,
        //   ExtractedEntity, OrganizePass, Topic, Project, MediaReference,
        //   TextSegment, InferenceSummary. Synced via CloudKit.
        // - **Local store** holds per-device runtime state — currently
        //   just ProcessingTask. Not synced. Both stores live on the
        //   same coordinator so contexts can fetch across them; only
        //   relationships can't cross. See ProcessingTask's docstring
        //   for the rationale.
        //
        // TODO (deferred, 2026-06-06): the two-store split produces a
        // recurring non-fatal Core Data fault after each CloudKit import:
        //   "Delete propagation prefetching failed … 'NSCKImportOperation'
        //    appears to be from a different NSManagedObjectModel than
        //    this context's"
        // `NSPersistentCloudKitContainer` injects its own metadata
        // entities (NSCKImportOperation et al.) into the model at
        // runtime; they aren't listed in our explicit "Cloud" / "Local"
        // configurations, so Core Data's internal delete-propagation
        // fetch can't resolve them against either store's context.
        // The fault is caught internally — sync still imports/exports
        // successfully — but it's noise we should silence. Defer until
        // post-launch; revisit if it starts surfacing real sync issues
        // or if Apple ships a cleaner multi-config pattern.
        let cloudDescription = container.persistentStoreDescriptions.first!
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.himem.app"
        )

        // Local store sits next to the Cloud store on disk; same
        // application support folder, different filename. No CloudKit
        // options — this store stays on-device.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let localURL = appSupport.appendingPathComponent("MemoryStream-Local.sqlite")
        let localDescription = NSPersistentStoreDescription(url: localURL)
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true
        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        container.persistentStoreDescriptions = [cloudDescription, localDescription]

        var cloudLoadError: Error?
        var localLoadError: Error?
        LaunchSignposter.interval("storage.loadPersistentStores") {
            container.loadPersistentStores { description, error in
                if let error {
                    if description.configuration == "Cloud" {
                        cloudLoadError = error
                    } else {
                        localLoadError = error
                    }
                }
            }
        }

        // Local store load failure is fatal — we can't run without
        // somewhere to track ProcessingTask state.
        if let localLoadError {
            fatalError("Local Core Data store failed to load: \(localLoadError.localizedDescription)")
        }

        // CloudKit-backed cloud-store load failed (rare — typically a
        // transient setup issue). Strip CloudKit options and try once
        // more so the user gets a working local Cloud store; sync just
        // won't happen this session. Local store already loaded above.
        if cloudLoadError != nil {
            cloudDescription.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [cloudDescription]
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
        // Also skip under XCTest — schema discovery holds a CKDatabase
        // singleton and multiple parallel test hosts collide on it.
        if !Self.isRunningTests {
        // Schema discovery is a CloudKit chatter bomb (multiple round
        // trips, dozens of log lines) and only needs to run once per
        // schema version per device. The flag is debug-only so a
        // production user never gets here even if they install a
        // debug build by accident.
        //
        // **When you change the Cloud schema, bump the version
        // suffix.** That tells already-installed Debug builds to
        // re-run `initializeCloudKitSchema`, which publishes the new
        // schema to the **Development** CloudKit environment so the
        // dashboard's "Schema Changes" view actually shows a diff to
        // deploy to Production. Without the bump, the dashboard sees
        // Development matching Production — no diff — even though the
        // model file has changed.
        //
        // Version log:
        //   V1 — initial.
        //   V2 — assist-quota retirement (8e.2: remove AssistBalance
        //         entity + OrganizePass.nextStepsMarkdown) and the
        //         transient-entity split (#19: ProcessingTask moved
        //         to the Local store, removed from Cloud).
        //   V3 — `MediaReference.mediaDescription` added for the
        //         photo/video description feature (#53). Folds into
        //         the same dashboard deploy as V2 since V2 has not
        //         shipped to Production yet.
        // V5 — Phase 4 clean-cut: v3 model is the ONLY model version
        //       (v1 and v2 deleted from disk). Legacy `entry`/`entryId`/
        //       `mediaReferences` fields gone. Migration code removed
        //       entirely — Tom exported his data and starts fresh.
        //       Bumped so his device republishes v3 to Dev after Dev
        //       is reset via CloudKit Dashboard.
        //   V6 — `Project.recycledAt` added for the F1 project deletion lock
        //         (soft-delete → Recently Deleted). Without this bump the
        //         field never publishes to Development, so the recycledAt
        //         write doesn't round-trip and deleted projects never reach
        //         the bin (device repro 2026-07-17).
        //   V7 — B4 mentions-library schema batch (July 18 2026): new
        //         `Mention` entity (many-to-many → JournalEntry), the
        //         `JournalEntry.mentions` relationship, and
        //         `MediaReference.sourceDevice`. Bumped so all three
        //         publish to Development. The ExtractedEntity→Mention DATA
        //         migration is separate (`MentionMigration`, run via
        //         LaunchScreenView), not a schema concern.
        //   V8 — `MediaReference.recycledAt` added for the P8 last-reference
        //         deletion rule + clip-level Recently Deleted (July 19 2026).
        //         Without this bump the field never publishes to Development,
        //         so a recycled clip's recycledAt doesn't round-trip and the
        //         clip never reaches the bin (same class of bug as V6). THE
        //         DECISION LOGIC (edge-count) needs no schema — only
        //         recycledAt does.
        //
        //   DEPLOY STATUS (2026-07-25): the V2–V8 field batch — including
        //   `Project.recycledAt` (V6), the V7 Mention/sourceDevice fields,
        //   and `MediaReference.recycledAt` (V8) — has been DEPLOYED to the
        //   Production CloudKit environment (dashboard shows no pending diff).
        //   Earlier revisions of this log described these as "still-pending
        //   pre-TestFlight" — that is no longer true. Note the deploy
        //   implication for soft-delete sync: because both `isRecycled` and
        //   the clip-side `recycledAt` are now deployed, a recycle syncs
        //   symmetrically (memory + its sole-edge clips), so "memory recycled
        //   but its clips still live" across devices is NOT a deploy-asymmetry
        //   artifact — see TestFlight #4a provenance.
        let schemaInitKey = "com.himem.cloudkit.schemaInitializedV8"
        if !UserDefaults.standard.bool(forKey: schemaInitKey) {
            // Only mark the version flag set on actual success. If we
            // failed silently (e.g. account daemon temporarily refused
            // the call), we want the next launch to retry — otherwise
            // we burn the version flag, the schema never publishes to
            // Development, and the dashboard sees no diff to deploy.
            LaunchSignposter.interval("storage.initializeCloudKitSchema") {
                do {
                    try cloudKitContainer.initializeCloudKitSchema(options: [])
                    UserDefaults.standard.set(true, forKey: schemaInitKey)
                    NSLog("[HiMem][CloudKit] initializeCloudKitSchema succeeded — V2 schema published to Development")
                } catch {
                    NSLog("[HiMem][CloudKit] initializeCloudKitSchema FAILED: \(error.localizedDescription) — will retry next launch")
                }
            }
        }
        } // end !isRunningTests guard
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

    #if DEBUG
    /// Test-only: an on-disk **SQLite** store using the shared cached model.
    /// The in-memory store (`init(inMemory:)`) evaluates fetch predicates via
    /// Foundation, which masks SQL three-valued-logic behavior — notably a
    /// NULL optional `Bool` under `!= YES`. Tests that must exercise real SQL
    /// predicate semantics (or `NSBatchUpdateRequest`, unsupported in-memory)
    /// use this. Reuses `cachedModel` so no second model claims the entity
    /// classes. Caller deletes `url` (and -wal/-shm) when done.
    static func makeSQLiteTestContainer() -> (container: NSPersistentContainer, url: URL) {
        let container = NSPersistentContainer(name: "MemoryStream", managedObjectModel: cachedModel)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("himem-sqlite-test-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("SQLite test store failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return (container, url)
    }
    #endif

    func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
    // The temporary v1 invariant (`assertNoZeroEdgeMediaReferences`) was
    // retired in Phase 6 alongside the delete-verb split. Removing a
    // clip from its last memory legitimately creates a zero-edge
    // MediaReference (the "returned to Clips tab" state), which the
    // Clips tab default view now reads. See
    // `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`
    // § Temporary v1 invariant.

    /// True inside the XCTest / Swift Testing test host process. Static
    /// so callers outside `StorageService` (e.g. `MemoryStreamApp.init`)
    /// can use it to skip the launch pre-warm — under parallel Swift-Testing
    /// runs the pre-warm makes N test hosts race the persistent-store lock
    /// during any Core Data lightweight migration, and the losers get
    /// killed for preflight timeout.
    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || NSClassFromString("Testing.Test") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        // No `task.entry = entry` — the relationship was removed when
        // ProcessingTask moved to the Local store (Core Data can't cross
        // stores). `entryId` is the link; `JournalEntry.latestProcessingTask()`
        // queries by it.
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

    /// Creates a MediaReference (evidence) attached to `entry` via a
    /// `MemoryClipEdge` (the v1 ontology's associative entity).
    /// `capturedAt` overrides the default `Date()` for `ref.createdAt`.
    func createMediaReference(
        for entry: JournalEntry,
        localIdentifier: String,
        mediaType: MediaReference.MediaType,
        capturedAt: Date? = nil,
        sourceDevice: JournalEntry.SourceDevice? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = localIdentifier
        ref.mediaType = mediaType.rawValue
        ref.isAccessible = true
        ref.sourceDevice = sourceDevice?.rawValue
        let refCreatedAt = capturedAt ?? Date()
        ref.createdAt = refCreatedAt
        try Self.createEdge(from: entry, to: ref, linkedAt: refCreatedAt, in: ctx)
        try save(context: ctx)
        return ref
    }

    /// Creates a `.note` fragment — a MediaReference whose body lives in
    /// the `text` field rather than referencing an external asset. Replaces
    /// the legacy `TextSegment` entity.
    func createNoteFragment(
        for entry: JournalEntry,
        text: String,
        createdAt: Date = Date(),
        sourceDevice: JournalEntry.SourceDevice? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = ""
        ref.mediaType = MediaReference.MediaType.note.rawValue
        ref.isAccessible = true
        ref.sourceDevice = sourceDevice?.rawValue
        ref.createdAt = createdAt
        ref.text = text
        try Self.createEdge(from: entry, to: ref, linkedAt: createdAt, in: ctx)
        try save(context: ctx)
        return ref
    }

    /// Creates a `.voice` fragment with the audio filename as
    /// `osIdentifier` and the speech transcript on the ref. Replaces the
    /// legacy `JournalEntry.audioFilePath` slot for in-app voice
    /// captures.
    func createVoiceFragment(
        for entry: JournalEntry,
        audioFilename: String,
        transcript: String,
        createdAt: Date = Date(),
        sourceDevice: JournalEntry.SourceDevice? = nil,
        context: NSManagedObjectContext? = nil
    ) throws -> MediaReference {
        let ctx = context ?? viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = audioFilename
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.isAccessible = true
        ref.sourceDevice = sourceDevice?.rawValue
        ref.createdAt = createdAt
        // Strip ASR leading-noise punctuation (",.", ",…", "...") so
        // the stored transcript — and everything downstream (joined
        // entry.content, AI prompt, card snippet, full-detail body)
        // — sees clean text. Per Tom's 2026-05-27 screenshots.
        ref.transcript = JournalEntry.cleanedTranscript(transcript)
        try Self.createEdge(from: entry, to: ref, linkedAt: createdAt, in: ctx)
        try save(context: ctx)
        return ref
    }

    /// Creates a single `MemoryClipEdge` connecting `entry` to `ref` in
    /// `ctx`. `orderInMemory` is derived from the memory's current
    /// edge count — for new memories with N clips inserted sequentially,
    /// this yields 0..N-1 in insertion order. Never called directly by
    /// higher layers — flows through `createMediaReference` /
    /// `createVoiceFragment` / `createNoteFragment` so every
    /// MediaReference lands with at least one edge (the temporary
    /// v1 invariant enforced through Phase 6).
    ///
    /// **Idempotent per (memoryId, clipId).** If an edge already exists
    /// for the pair, this is a no-op — the pre-existing edge is
    /// preserved (its `linkedAt` / `orderInMemory` / `annotation` are
    /// not overwritten). The `MemoryClipEdge` docstring names this
    /// invariant; without the guard, a re-invoked Sort commit /
    /// OrganizePass / hostile CloudKit merge could double a memory's
    /// clip list, which surfaced as the "duplicate transcript rows on
    /// Memory Detail" defect (CD 2026-07-09).
    static func createEdge(
        from entry: JournalEntry,
        to ref: MediaReference,
        linkedAt: Date,
        in ctx: NSManagedObjectContext
    ) throws {
        if entry.edgesArray.contains(where: { $0.clipId == ref.id }) {
            return
        }
        let edge = MemoryClipEdge(context: ctx)
        edge.id = UUID()
        edge.clipId = ref.id
        edge.memoryId = entry.id
        edge.clip = ref
        edge.memory = entry
        edge.orderInMemory = Int16(entry.edgesArray.count)
        edge.linkedAt = linkedAt
        edge.annotation = nil
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

    // MARK: - Mention Operations

    /// Idempotent find-or-create for a library-backed `Mention` (B4).
    /// Dedup is on **(normalizedName, type)** — a same-name person and
    /// org stay distinct (ruled 2026-07-17); only a same-name same-type
    /// pair merges. Mirrors `findOrCreateTopic`'s slug idempotency.
    @discardableResult
    func findOrCreateMention(
        name: String,
        type: Mention.MentionType,
        context: NSManagedObjectContext? = nil
    ) throws -> Mention {
        let ctx = context ?? viewContext
        let normalized = Mention.normalize(name)

        let request = NSFetchRequest<Mention>(entityName: "Mention")
        request.predicate = NSPredicate(
            format: "normalizedName == %@ AND type == %@",
            normalized, type.rawValue
        )
        request.fetchLimit = 1

        if let existing = try ctx.fetch(request).first {
            return existing
        }

        let mention = Mention(context: ctx)
        mention.id = UUID()
        mention.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mention.type = type.rawValue
        mention.normalizedName = normalized
        mention.createdAt = Date()
        try save(context: ctx)
        return mention
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

// MARK: - Mention Migration (B4, July 18 2026)

/// Seeds the library-backed `Mention` store from the legacy per-memory
/// `ExtractedEntity` mentions, so the unified associations mentions UI has
/// data on day one. Co-located with `StorageService` (avoids a new
/// project-file entry) and modelled on `FragmentMigration.runIfNeeded`.
///
/// **Mapping** (ruled 2026-07-18): `idea→idea`, `person→person`,
/// `project→org` (the NL extractor lumped places+orgs into `project`; org
/// is the least-wrong bucket, user re-types in one tap), `issue→idea`,
/// `next_action→skipped` (never a mention).
///
/// **ExtractedEntity rows are LEFT in place** — that table is still the
/// NL-extraction substrate; only the mentions *display/management* moves
/// to `Mention`. The migration is idempotent twice over: a run-once
/// UserDefaults flag *and* `findOrCreateMention` + `addToMentions` Set
/// semantics, so a re-run self-heals rather than duplicating.
enum MentionMigration {
    private static let flagKey = "com.himem.migration.extractedEntityToMentionV1"

    static func runIfNeeded(in context: NSManagedObjectContext, storage: StorageService = .shared) {
        if UserDefaults.standard.bool(forKey: flagKey) { return }
        _ = migrate(in: context, storage: storage)
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// Maps a legacy entity type to a mention type, or `nil` when the
    /// entity is not a mention (`next_action`). Internal for the money
    /// tests.
    static func mappedType(for type: ExtractedEntity.EntityType) -> Mention.MentionType? {
        switch type {
        case .idea:       return .idea
        case .person:     return .person
        case .project:    return .org
        case .issue:      return .idea
        case .nextAction: return nil
        }
    }

    /// The migration body, flag-free so tests can drive it directly on an
    /// in-memory context. Returns the number of memory→mention links
    /// created (existing links are not double-counted). Idempotent.
    @discardableResult
    static func migrate(in context: NSManagedObjectContext, storage: StorageService = .shared) -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        guard let entries = try? context.fetch(request) else { return 0 }

        var linked = 0
        for entry in entries {
            let entities = (entry.extractedEntities as? Set<ExtractedEntity>) ?? []
            let alreadyLinked = (entry.mentions as? Set<Mention>) ?? []
            for entity in entities {
                guard let type = mappedType(for: entity.entityTypeEnum) else { continue }
                let name = entity.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                guard let mention = try? storage.findOrCreateMention(name: name, type: type, context: context) else { continue }
                if !alreadyLinked.contains(mention) && !(entry.mentions as? Set<Mention> ?? []).contains(mention) {
                    entry.addToMentions(mention)
                    linked += 1
                }
            }
        }
        try? context.save()
        return linked
    }
}
