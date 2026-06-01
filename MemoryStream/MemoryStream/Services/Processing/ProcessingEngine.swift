import Foundation
import CoreData

/// Abstraction over the cloud entry analyzer so ProcessingEngine can be
/// driven by a stub in tests (and to keep the fallback-on-failure path
/// exercised without real network access).
protocol EntryAnalyzer {
    /// `existingMentions` carries the case-folded-deduped entity values
    /// already attached to this entry. Empty on first-organize. Server
    /// is instructed (via `docs/design/mentions-server-prompt.md`) to
    /// reuse these strings verbatim where they still apply rather than
    /// paraphrasing — kills the "Reusable Sausage Process" /
    /// "Sausage making process" / "Develop Reusable Sausage Process"
    /// paraphrase accumulation observed 2026-05-18.
    func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult
}

extension ClaudeAPIService: EntryAnalyzer {}

final class ProcessingEngine {
    static let shared = ProcessingEngine()

    private let storage: StorageService
    private let analyzer: EntryAnalyzer
    private let localExtractor: LocalEntityExtractor
    private let connectivity: ConnectivityMonitor
    /// Injectable assist-debit closure. Default routes to
    /// `EntitlementService.shared.tryConsumeAssist()`; tests swap
    /// for a throwing closure to exercise the failure-surface path.
    /// Money path — see `ProcessingEngineAssistDebitTests`.
    private let consumeAssist: @MainActor () throws -> Void

    init(
        storage: StorageService = .shared,
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        localExtractor: LocalEntityExtractor = .shared,
        connectivity: ConnectivityMonitor = .shared,
        consumeAssist: @escaping @MainActor () throws -> Void = { try EntitlementService.shared.tryConsumeAssist() }
    ) {
        self.storage = storage
        self.analyzer = analyzer
        self.localExtractor = localExtractor
        self.connectivity = connectivity
        self.consumeAssist = consumeAssist
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
                if bgEntry.latestProcessingTask == nil {
                    _ = try self.storage.createProcessingTask(for: bgEntry, context: context)
                }
                guard let task = bgEntry.latestProcessingTask else { return }
                task.status = ProcessingTask.Status.processing.rawValue
                task.progressDescription = "Raw note saved. The app is extracting entities and content intent."
                try context.save()
            } catch {
                Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
            }
        }

        if connectivity.isConnected {
            await processWithCloud(objectID: objectID, content: content, context: context)
        } else {
            await processLocally(objectID: objectID, content: content, context: context)
        }
    }

    // MARK: - Cloud Processing

    private func processWithCloud(objectID: NSManagedObjectID, content: String, context: NSManagedObjectContext) async {
        do {
            // Fetch existing topic names so the AI prefers them over inventing new ones
            let existingTopics: [String] = await context.perform {
                let request = NSFetchRequest<Topic>(entityName: "Topic")
                let topics = (try? context.fetch(request)) ?? []
                return topics.map(\.name)
            }

            // Existing mentions on THIS entry only — case-folded
            // dedupe so duplicates already in the store don't
            // pollute the payload. Re-organize passes ship this set
            // so the model refines instead of paraphrasing.
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

            let result = try await analyzer.analyzeEntry(
                content,
                existingTopics: existingTopics,
                existingMentions: existingMentions
            )

            let saveSucceeded: Bool = await context.perform { [self] in
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
            // Pricing rule (v2): 1 assist per successful organize pass.
            // Failures cost zero. We deduct ONLY when the Core Data
            // save committed cleanly — a Core Data error, parser blow-
            // up, or anything else in the inner closure that fell into
            // `markFailed` leaves the counter untouched. (The cloud-
            // network failure path doesn't even reach here — it's
            // handled by the outer catch that falls back to local.)
            //
            // Debit failure handling: surface to `ErrorState` (user
            // sees something went wrong) but do NOT mark the pass
            // failed — the analyzer ran, Core Data committed, the
            // entry is in a good state. Rolling back would lose real
            // work; quietly swallowing the debit (the pre-2026-06-01
            // `try?` behavior) loses real money state. The middle
            // path is "log it, tell the user, don't undo the win."
            if saveSucceeded {
                let debitFailure: Error? = await MainActor.run { () -> Error? in
                    do {
                        try self.consumeAssist()
                        return nil
                    } catch {
                        return error
                    }
                }
                if let debitFailure {
                    NSLog("[Himem][Pricing] tryConsumeAssist failed after successful pass: \(debitFailure.localizedDescription)")
                    await MainActor.run {
                        ErrorState.shared.report(.processingFailed("Couldn't record assist usage: \(debitFailure.localizedDescription). Please retry."))
                    }
                }
            }
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
                if let task = entryInContext.latestProcessingTask {
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

    // MARK: - Queue Processing

    /// Finds entries that were processed via the local fallback (extracted
    /// entities all marked `processingMethod = "local"`) and re-runs them
    /// through the cloud analyzer. Wired to fire on connectivity-restored
    /// transitions so memories captured offline get upgraded once the user
    /// is back online.
    func reprocessLocallyHandledEntries() async {
        // Free tier never had AI run on entries, so nothing to reprocess.
        // Plus/Founders may have local-fallback entries from offline
        // creation that should be re-processed when connectivity returns.
        // Each one consumes one assist; bail when the user runs out
        // rather than silently exceed the monthly allowance.
        let entitled: Bool = await MainActor.run {
            EntitlementService.shared.tier != .free
        }
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
            // Precheck — this is auto-org (no user tap), so respect
            // the user's auto-organize threshold. Bail at the first
            // entry where the threshold gate fires rather than firing
            // doomed API calls or eating the user's manual reserve.
            let mayConsume: Bool = await MainActor.run {
                EntitlementService.shared.canAutoOrganize
            }
            guard mayConsume else { break }

            let entry: JournalEntry? = await viewContext.perform {
                guard let entry = try? viewContext.existingObject(with: entryID) as? JournalEntry else { return nil }
                let entities = entry.extractedEntities as? Set<ExtractedEntity> ?? []
                for entity in entities { viewContext.delete(entity) }
                if let summary = entry.inferenceSummary { viewContext.delete(summary) }
                if let task = entry.latestProcessingTask {
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
                guard let entry = task.entry else { continue }
                await processEntry(entry)
            }
        } catch {
            Task { @MainActor in ErrorState.shared.report(.processingFailed(error.localizedDescription)) }
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
        // Next steps — formatted as markdown bullets so the existing
        // `OrganizePass.nextStepsItems` parser handles them and the
        // AISuggestionsCard renders them in its Next steps row.
        // Skips writes when the server returned an empty / nil array
        // so the column stays nil (Next steps row hides cleanly).
        if let steps = result.nextSteps, !steps.isEmpty {
            pass.nextStepsMarkdown = steps
                .map { "- " + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")
        } else {
            pass.nextStepsMarkdown = nil
        }
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
        if let task = entry.latestProcessingTask {
            task.status = ProcessingTask.Status.completed.rawValue
            task.progressDescription = nil
            task.processedAt = Date()
        }
    }

    private func markFailed(objectID: NSManagedObjectID, error: Error, context: NSManagedObjectContext) {
        do {
            let entryInContext = try context.existingObject(with: objectID) as! JournalEntry
            if let task = entryInContext.latestProcessingTask {
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
