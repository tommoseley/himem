import Foundation
import CoreData

/// Abstraction over the cloud entry analyzer so ProcessingEngine can be
/// driven by a stub in tests (and to keep the fallback-on-failure path
/// exercised without real network access).
protocol EntryAnalyzer {
    func analyzeEntry(_ text: String, existingTopics: [String]) async throws -> ClaudeAPIService.AnalysisResult
}

extension ClaudeAPIService: EntryAnalyzer {}

final class ProcessingEngine {
    static let shared = ProcessingEngine()

    private let storage: StorageService
    private let analyzer: EntryAnalyzer
    private let localExtractor: LocalEntityExtractor
    private let connectivity: ConnectivityMonitor

    init(
        storage: StorageService = .shared,
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        localExtractor: LocalEntityExtractor = .shared,
        connectivity: ConnectivityMonitor = .shared
    ) {
        self.storage = storage
        self.analyzer = analyzer
        self.localExtractor = localExtractor
        self.connectivity = connectivity
    }

    // MARK: - Process Entry

    func processEntry(_ entry: JournalEntry) async {
        let objectID = entry.objectID
        let content = entry.content
        let context = storage.backgroundContext()

        // Mark as processing — using the background context's copy
        await context.perform {
            do {
                let bgEntry = try context.existingObject(with: objectID) as! JournalEntry
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

            let result = try await analyzer.analyzeEntry(content, existingTopics: existingTopics)

            await context.perform { [self] in
                do {
                    let entry = try context.existingObject(with: objectID) as! JournalEntry
                    storeEntities(from: result, for: entry, in: context)
                    let newTopics = assignTopics(from: result, for: entry, in: context)
                    queueNewTopics(newTopics, entryObjectID: objectID)
                    checkAlbumSync(for: entry, topics: result.topics, context: context)
                    storeInference(from: result, for: entry, in: context)
                    markCompleted(entry)
                    try context.save()
                } catch {
                    self.markFailed(objectID: objectID, error: error, context: context)
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
        for entityResult in result.entities {
            guard let type = ExtractedEntity.EntityType(rawValue: entityResult.type) else { continue }
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
        let mediaIds = entry.mediaReferencesArray.map(\.osIdentifier)
        guard !mediaIds.isEmpty else { return }
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
                    AlbumSyncService.shared.addNewMedia(topicName: name, identifiers: mediaIds)
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
        if let title = result.title {
            entry.title = title
        }
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
