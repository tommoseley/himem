import Foundation
import CoreData

/// Abstraction over the cloud entry analyzer so ProcessingEngine can be
/// driven by a stub in tests (and to keep the fallback-on-failure path
/// exercised without real network access).
///
/// `tier` and `action` plumb through to the server's COGS log (see
/// `docs/api/himem-cost-logging.md`). Tier is the
/// `EntitlementService.Tier` rawValue captured at the moment of the
/// call; action is one of a small locked vocabulary
/// (`memory_organize`, `project_assist`, …). Tests pass any string
/// they like; the protocol only requires the parameters exist so
/// production call sites can't accidentally drop them.
protocol EntryAnalyzer {
    /// `existingMentions` carries the case-folded-deduped entity values
    /// already attached to this entry. Empty on first-organize. Server
    /// is instructed (via `docs/design/mentions-server-prompt.md`) to
    /// reuse these strings verbatim where they still apply rather than
    /// paraphrasing — kills the "Reusable Sausage Process" /
    /// "Sausage making process" / "Develop Reusable Sausage Process"
    /// paraphrase accumulation observed 2026-05-18.
    func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult
}

extension ClaudeAPIService: EntryAnalyzer {}

final class ProcessingEngine {
    static let shared = ProcessingEngine()

    /// Routes between the on-device and cloud organize paths. Defaults
    /// to true after the assist-quota retirement (PR 8e): Free runs on
    /// Apple Foundation Models, Plus also runs on-device today and gets
    /// the frontier polish in Job 4. Setting the flag false forces the
    /// cloud path for debugging.
    ///   `defaults write com.himem.app himem.organize.useOnDevice -bool NO`
    static let useOnDeviceFlagKey = "himem.organize.useOnDevice"

    static var defaultUseOnDevice: Bool {
        // UserDefaults returns false for an unset bool, so a missing
        // value means "use default" → true.
        let store = UserDefaults.standard
        if store.object(forKey: useOnDeviceFlagKey) == nil { return true }
        return store.bool(forKey: useOnDeviceFlagKey)
    }

    private let storage: StorageService
    private let analyzer: EntryAnalyzer
    private let onDeviceOrganizer: Organizer
    private let localExtractor: EntityExtractor
    private let connectivity: ConnectivityMonitor
    private let useOnDevice: Bool
    /// Injectable tier-read closure. Returns the COGS-log label
    /// (`docs/api/himem-cost-logging.md`) captured at call time so
    /// the report attributes spend to the tier in force. Tests inject
    /// a fixed string for determinism.
    private let readTier: @MainActor () -> String

    init(
        storage: StorageService = .shared,
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        onDeviceOrganizer: Organizer = OnDeviceOrganizer(),
        localExtractor: EntityExtractor = LocalEntityExtractor.shared,
        connectivity: ConnectivityMonitor = .shared,
        useOnDevice: Bool = ProcessingEngine.defaultUseOnDevice,
        readTier: @escaping @MainActor () -> String = { Entitlement.shared.tierLabel }
    ) {
        self.storage = storage
        self.analyzer = analyzer
        self.onDeviceOrganizer = onDeviceOrganizer
        self.localExtractor = localExtractor
        self.connectivity = connectivity
        self.useOnDevice = useOnDevice
        self.readTier = readTier
    }

    // MARK: - Process Entry

    func processEntry(_ entry: JournalEntry) async {
        let objectID = entry.objectID
        let content = entry.content
        let context = storage.backgroundContext()

        // Mark as processing — using the background context's copy.
        // Lazily mints a ProcessingTask when one is missing: free-tier
        // saves don't create a task (would leave the entry stuck on
        // "Queued"), so the manual Organize tap arrives here with no
        // task to advance. Mint it on the spot rather than silently
        // bailing on `guard let task`.
        await context.perform {
            do {
                let bgEntry = try context.existingObject(with: objectID) as! JournalEntry
                if bgEntry.latestProcessingTask() == nil {
                    _ = try self.storage.createProcessingTask(for: bgEntry, context: context)
                }
                guard let task = bgEntry.latestProcessingTask() else { return }
                task.status = ProcessingTask.Status.processing.rawValue
                task.progressDescription = "Raw note saved. The app is extracting entities and content intent."
                try context.save()
            } catch {
                Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
            }
        }

        // Default-on after the assist-quota retirement: Foundation
        // Models runs on-device when available; failure falls through
        // to the cloud path. The flag exists for debug/forced-cloud
        // testing only — see `defaultUseOnDevice`.
        if useOnDevice,
           OnDeviceOrganizer.availabilityError() == nil {
            let succeeded = await processWithOnDevice(objectID: objectID, content: content, context: context)
            if succeeded { return }
        }

        if connectivity.isConnected {
            await processWithCloud(objectID: objectID, content: content, context: context)
        } else {
            await processLocally(objectID: objectID, content: content, context: context)
        }
    }

    // MARK: - On-device Processing (PR 8a, debug-gated)

    /// Runs the entry through `OnDeviceOrganizer` and, on success,
    /// commits the result via the same storage helpers as the cloud
    /// path. Returns true if the AI call + Core Data save committed
    /// cleanly. Returns false on any failure so the caller can fall
    /// through to the existing connectivity-based routing.
    ///
    /// Skips the assist debit — on-device organize is unmetered.
    private func processWithOnDevice(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async -> Bool {
        let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)
        do {
            let result = try await onDeviceOrganizer.organize(
                content: content,
                existingTopics: existingTopics,
                existingMentions: existingMentions
            )
            return await applyAnalysisResult(result, to: objectID, in: context)
        } catch {
            NSLog("[HiMem][Organize] on-device pass failed, falling through: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Cloud Processing

    private func processWithCloud(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async {
        do {
            let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)

            // Capture the tier at the moment of the call — if the user
            // upgrades / downgrades mid-pass, the COGS log attributes
            // spend to the tier that authorized the assist, not the
            // tier they end up at.
            let tier = await MainActor.run { self.readTier() }
            let result = try await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions,
                tier: tier,
                action: "memory_organize"
            )

            _ = await applyAnalysisResult(result, to: objectID, in: context)
        } catch {
            // Cloud unreachable or timed out (weak connection, server error,
            // auth failure). Don't mark .failed and leave the user stuck —
            // fall back to local entity extraction so the entry still gets
            // useful tags. The reconnect watcher will re-process it via
            // cloud once connectivity is good.
            await processLocally(objectID: objectID, content: content, context: context)
        }
    }

    // MARK: - Local Processing

    private func processLocally(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async {
        let localResult = localExtractor.extractEntities(from: content)

        await context.perform {
            do {
                let entryInContext = try context.existingObject(with: objectID) as! JournalEntry

                for localEntity in localResult.entities {
                    let entity = ExtractedEntity(context: context)
                    entity.id = UUID()
                    entity.entryId = entryInContext.id
                    entity.entityType = localEntity.type.rawValue
                    entity.value = localEntity.value
                    entity.confidenceScore = localEntity.confidence
                    entity.processingMethod = "local"
                    entity.createdAt = Date()
                    entity.entry = entryInContext

                    if let nsRange = content.range(of: localEntity.value).map({ NSRange($0, in: content) }) {
                        entity.textRangeLocation = Int32(nsRange.location)
                        entity.textRangeLength = Int32(nsRange.length)
                    }
                }

                // Mark completed
                if let task = entryInContext.latestProcessingTask() {
                    task.status = ProcessingTask.Status.completed.rawValue
                    task.progressDescription = "Processed locally. Connect to the internet for richer analysis."
                    task.processedAt = Date()
                }

                try context.save()
            } catch {
                self.markFailed(objectID: objectID, error: error, context: context)
            }
        }
    }

    // MARK: - Reorganize (PR 8g)

    /// Runs a reorganize pass — **title and summary only**. Topics,
    /// mentions, album sync, and the inference graph are deliberately
    /// not touched per `AI Organize · spec.md` §8.0 (June 6 2026):
    /// reorganize rethinks the *interpretation* fields; the *fact*
    /// fields (topics, mentions) are user-managed and stable.
    ///
    /// Routing matches `processEntry` — on-device first when available,
    /// cloud fallback otherwise. Any topics or mentions the analyzer
    /// returns are discarded silently. The resulting `OrganizePass`
    /// enters the standard draft lifecycle (`dismissedAt = nil` →
    /// `isReviewed = false` → chip flips to *"Draft organized"*); the
    /// ReorganizeReviewSheet handles per-field accept-or-keep.
    ///
    /// A failed pass leaves prior state intact — no partial write, no
    /// pass record — per the spec's "failed passes change nothing."
    func processReorganize(_ entry: JournalEntry) async {
        let objectID = entry.objectID
        let content = entry.content
        let context = storage.backgroundContext()
        let (existingTopics, existingMentions) = await readExistingOrganizeContext(objectID: objectID, context: context)

        // On-device first when available.
        var result: ClaudeAPIService.AnalysisResult?
        if useOnDevice, OnDeviceOrganizer.availabilityError() == nil {
            result = try? await onDeviceOrganizer.organize(
                content: content,
                existingTopics: existingTopics,
                existingMentions: existingMentions
            )
        }

        // Cloud fallback. Skipped if on-device already produced a
        // result, or if we're offline.
        if result == nil, connectivity.isConnected {
            let tier = await MainActor.run { self.readTier() }
            result = try? await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions,
                tier: tier,
                action: "memory_organize"
            )
        }

        guard let result else { return }

        await context.perform { [self] in
            do {
                let entry = try context.existingObject(with: objectID) as! JournalEntry
                storeReorganizePass(title: result.title, summaryText: result.summary, for: entry, in: context)
                try context.save()
            } catch {
                // Swallow — spec §8: failed passes change nothing.
                NSLog("[HiMem][Organize] reorganize storeReorganizePass failed: \(error.localizedDescription)")
            }
        }
    }

    /// Writes a new `OrganizePass` for a reorganize call. Mirrors
    /// `storeOrganizePass` but skips topics, related entries, and
    /// next-steps — only title and summary are recorded.
    private func storeReorganizePass(title: String?, summaryText: String, for entry: JournalEntry, in context: NSManagedObjectContext) {
        let pass = OrganizePass(context: context)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.summaryText = summaryText
        pass.suggestedTitle = title
        pass.suggestedTopicsJSON = nil
        pass.relatedEntryIDsJSON = nil
        pass.dismissedAt = nil
        pass.entry = entry
        entry.lastOrganizedAt = pass.createdAt
    }

    // MARK: - Queue Processing

    /// Finds entries that were processed via the local fallback (extracted
    /// entities all marked `processingMethod = "local"`) and re-runs them
    /// through the cloud analyzer. Wired to fire on connectivity-restored
    /// transitions so memories captured offline get upgraded once the user
    /// is back online.
    func reprocessLocallyHandledEntries() async {
        // Auto-reprocess only runs for Plus users — Free uses
        // on-device organize, which already ran inline and doesn't
        // need a cloud upgrade on reconnect.
        let entitled: Bool = await MainActor.run { Entitlement.shared.isPlus }
        guard entitled else { return }

        let viewContext = storage.viewContext
        let entryIDs: [NSManagedObjectID] = await viewContext.perform {
            let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
            request.predicate = NSPredicate(format: "processingMethod == %@", "local")
            let entities = (try? viewContext.fetch(request)) ?? []
            let ids = Set(entities.compactMap { $0.entry?.objectID })
            return Array(ids)
        }

        guard !entryIDs.isEmpty else { return }

        for entryID in entryIDs {
            let entry: JournalEntry? = await viewContext.perform {
                guard let entry = try? viewContext.existingObject(with: entryID) as? JournalEntry else { return nil }
                let entities = entry.extractedEntities as? Set<ExtractedEntity> ?? []
                for entity in entities { viewContext.delete(entity) }
                if let summary = entry.inferenceSummary { viewContext.delete(summary) }
                if let task = entry.latestProcessingTask() {
                    task.status = ProcessingTask.Status.pending.rawValue
                    task.processedAt = nil
                    task.errorMessage = nil
                    task.progressDescription = nil
                }
                try? viewContext.save()
                return entry
            }
            if let entry {
                await processEntry(entry)
            }
        }
    }

    func processPendingTasks() async {
        let context = storage.backgroundContext()
        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "status == %@", ProcessingTask.Status.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ProcessingTask.createdAt, ascending: true)]
        request.fetchLimit = 10

        do {
            let tasks = try context.performAndWait { try context.fetch(request) }
            for task in tasks {
                // ProcessingTask no longer has a relationship to
                // JournalEntry (stores split, see task #19). Fetch the
                // entry by entryId on the same context — the Cloud
                // store is loaded on the same coordinator.
                let entry: JournalEntry? = context.performAndWait {
                    let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
                    req.predicate = NSPredicate(format: "id == %@", task.entryId as CVarArg)
                    req.fetchLimit = 1
                    return try? context.fetch(req).first
                }
                guard let entry else { continue }
                await processEntry(entry)
            }
        } catch {
            Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
        }
    }

    // MARK: - Shared Organize Helpers

    /// Reads existing topic names + this-entry mentions used to seed an
    /// organize pass. Cloud and on-device paths both consume this so
    /// the model refines vs. paraphrases on re-organize.
    private func readExistingOrganizeContext(objectID: NSManagedObjectID, context: NSManagedObjectContext) async -> (topics: [String], mentions: [String]) {
        let existingTopics: [String] = await context.perform {
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            let topics = (try? context.fetch(request)) ?? []
            return topics.map(\.name)
        }
        let existingMentions: [String] = await context.perform {
            guard let entry = try? context.existingObject(with: objectID) as? JournalEntry,
                  let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return [] }
            var seen: Set<String> = []
            var out: [String] = []
            for e in entities {
                let trimmed = e.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    out.append(trimmed)
                }
            }
            return out
        }
        return (existingTopics, existingMentions)
    }

    /// Applies a successful `AnalysisResult` to the entry — stores
    /// entities, assigns topics (queueing unknowns for approval),
    /// triggers album sync, writes the inference summary and
    /// `OrganizePass`, marks the task complete, saves. Returns true
    /// if the save committed cleanly; false if `markFailed` was
    /// invoked. Shared by the on-device and cloud paths.
    private func applyAnalysisResult(_ result: ClaudeAPIService.AnalysisResult, to objectID: NSManagedObjectID, in context: NSManagedObjectContext) async -> Bool {
        await context.perform { [self] in
            do {
                let entry = try context.existingObject(with: objectID) as! JournalEntry
                storeEntities(from: result, for: entry, in: context)
                let newTopics = assignTopics(from: result, for: entry, in: context)
                queueNewTopics(newTopics, entryObjectID: objectID)
                checkAlbumSync(for: entry, topics: result.topics, context: context)
                storeInference(from: result, for: entry, in: context)
                storeOrganizePass(from: result, for: entry, in: context)
                markCompleted(entry)
                try context.save()
                return true
            } catch {
                self.markFailed(objectID: objectID, error: error, context: context)
                return false
            }
        }
    }

    // MARK: - Cloud Processing Helpers

    private func storeEntities(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) {
        // Snapshot existing (type, normalizedValue) on the entry so a second
        // processing pass — whether from a CloudKit re-import after Change
        // Token Expired, an unforeseen re-trigger, or a bg/view race —
        // doesn't double-insert mentions the user already has.
        let existingKeys: Set<String> = {
            guard let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return [] }
            return Set(entities.map { Self.entityKey(type: $0.entityType, value: $0.value) })
        }()

        for entityResult in result.entities {
            guard let type = ExtractedEntity.EntityType(rawValue: entityResult.type) else { continue }
            let key = Self.entityKey(type: type.rawValue, value: entityResult.value)
            if existingKeys.contains(key) { continue }
            let entity = ExtractedEntity(context: context)
            entity.id = UUID()
            entity.entryId = entry.id
            entity.entityType = type.rawValue
            entity.value = entityResult.value
            entity.confidenceScore = entityResult.confidence
            entity.processingMethod = "cloud"
            entity.createdAt = Date()
            entity.entry = entry
        }
    }

    /// Normalized key for entity-dedup: case-folded, trimmed value
    /// only. Type is intentionally excluded — the same string with
    /// different types ("Bob" classified as `person` in pass A and
    /// `project` in pass B) is the same entity, just classified
    /// inconsistently. Type accepts the `type` param to preserve the
    /// call-site shape; it does not affect the key.
    static func entityKey(type: String, value: String) -> String {
        _ = type
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns names of topics that need user approval (don't exist yet).
    private func assignTopics(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) -> [String] {
        var newTopicNames: [String] = []
        for topicName in result.topics {
            let slug = TopicSlugHelper.slugify(topicName)
            let request = NSFetchRequest<Topic>(entityName: "Topic")
            request.predicate = NSPredicate(format: "slug == %@", slug)
            request.fetchLimit = 1
            if let existing = try? context.fetch(request).first {
                entry.addToTopics(existing)
            } else {
                newTopicNames.append(topicName)
            }
        }
        return newTopicNames
    }

    private func queueNewTopics(_ names: [String], entryObjectID: NSManagedObjectID) {
        guard !names.isEmpty else { return }
        Task { @MainActor in
            for name in names {
                TopicApprovalService.shared.suggest(name: name, entryObjectID: entryObjectID)
            }
        }
    }

    private func checkAlbumSync(for entry: JournalEntry, topics: [String], context: NSManagedObjectContext) {
        // Photos albums hold images and videos. Voice/audio refs aren't in
        // PhotoKit and shouldn't trigger the "create an album for this topic"
        // prompt — that question is meaningless for voice-only memories.
        let visualMediaIds = entry.mediaReferencesArray
            .filter { $0.mediaTypeEnum == .image || $0.mediaTypeEnum == .video }
            .map(\.osIdentifier)
        guard !visualMediaIds.isEmpty else { return }

        let existingTopics = topics.filter { topicName in
            let slug = TopicSlugHelper.slugify(topicName)
            let req = NSFetchRequest<Topic>(entityName: "Topic")
            req.predicate = NSPredicate(format: "slug == %@", slug)
            req.fetchLimit = 1
            return (try? context.fetch(req).first) != nil
        }
        guard !existingTopics.isEmpty else { return }
        Task { @MainActor in
            for name in existingTopics {
                if AlbumSyncService.shared.isAutoSyncEnabled(for: name) {
                    AlbumSyncService.shared.addNewMedia(topicName: name, identifiers: visualMediaIds)
                } else {
                    AlbumSyncService.shared.proposeIfNeeded(topicName: name)
                }
            }
        }
    }

    private func storeInference(from result: ClaudeAPIService.AnalysisResult, for entry: JournalEntry, in context: NSManagedObjectContext) {
        let summary = InferenceSummary(context: context)
        summary.id = UUID()
        summary.entryId = entry.id
        summary.summaryText = result.summary
        summary.createdAt = Date()
        summary.entry = entry
        // Per v5 pricing UX: AI-suggested titles no longer auto-write
        // into `entry.title`. They land on `OrganizePass.suggestedTitle`
        // (see `storeOrganizePass` below) and flow into the entry only
        // when the user accepts via the Title row of the
        // AISuggestionsCard. This prevents silent overwrites of
        // user-authored titles by background auto-org passes.
    }

    /// Writes the per-pass `OrganizePass` record alongside the legacy
    /// `InferenceSummary`. The two coexist for now — the new memory
    /// detail Done state reads from `OrganizePass`, but old entries
    /// without one fall back to the legacy `InferenceCard` which reads
    /// `InferenceSummary`. When the prompt is updated to return Next
    /// steps and Related memories, those fields populate here.
    private func storeOrganizePass(
        from result: ClaudeAPIService.AnalysisResult,
        for entry: JournalEntry,
        in context: NSManagedObjectContext
    ) {
        let pass = OrganizePass(context: context)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.summaryText = result.summary
        pass.suggestedTitle = result.title
        pass.setSuggestedTopics(result.topics)
        // Related memories isn't yet returned by the server prompt
        // and was deliberately cut from the v5 Review card (the
        // Review card is the contract for "this memory"; other-memory
        // discovery happens elsewhere — search, tag drilldown).
        // Field reserved for future use; not populated.
        pass.relatedEntryIDsJSON = nil
        pass.dismissedAt = nil
        pass.entry = entry
        // The lastOrganizedAt timestamp drives the "N new clips since
        // last organize" Re-organize callout. Set on every successful
        // pass — Free manual taps and Plus auto-runs both qualify.
        entry.lastOrganizedAt = pass.createdAt
    }

    private func markCompleted(_ entry: JournalEntry) {
        if let task = entry.latestProcessingTask() {
            task.status = ProcessingTask.Status.completed.rawValue
            task.progressDescription = nil
            task.processedAt = Date()
        }
    }

    private func markFailed(objectID: NSManagedObjectID, error: Error, context: NSManagedObjectContext) {
        do {
            let entryInContext = try context.existingObject(with: objectID) as! JournalEntry
            if let task = entryInContext.latestProcessingTask() {
                task.status = ProcessingTask.Status.failed.rawValue
                task.errorMessage = error.localizedDescription
                task.progressDescription = error.localizedDescription
                task.processedAt = Date()
            }
            try context.save()
        } catch {
            Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
        }
    }
}

// MARK: - Core Data Relationship Helpers

extension JournalEntry {
    @objc(addTopicsObject:)
    @NSManaged func addToTopics(_ value: Topic)

    @objc(removeTopicsObject:)
    @NSManaged func removeFromTopics(_ value: Topic)
}
