import Foundation
import CoreData

final class ProcessingEngine {
    static let shared = ProcessingEngine()

    private let storage = StorageService.shared
    private let claudeAPI = ClaudeAPIService.shared
    private let localExtractor = LocalEntityExtractor.shared
    private let connectivity = ConnectivityMonitor.shared

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
                print("Failed to mark as processing: \(error)")
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
            let result = try await claudeAPI.analyzeEntry(content)

            await context.perform { [self] in
                do {
                    let entryInContext = try context.existingObject(with: objectID) as! JournalEntry

                    // Store extracted entities
                    for entityResult in result.entities {
                        guard let type = ExtractedEntity.EntityType(rawValue: entityResult.type) else { continue }
                        let entity = ExtractedEntity(context: context)
                        entity.id = UUID()
                        entity.entryId = entryInContext.id
                        entity.entityType = type.rawValue
                        entity.value = entityResult.value
                        entity.confidenceScore = entityResult.confidence
                        entity.processingMethod = "cloud"
                        entity.createdAt = Date()
                        entity.entry = entryInContext
                    }

                    // Assign existing topics, queue new ones for approval
                    var newTopicNames: [String] = []
                    for topicName in result.topics {
                        let slug = topicName.lowercased().replacingOccurrences(of: " ", with: "-")
                        let request = NSFetchRequest<Topic>(entityName: "Topic")
                        request.predicate = NSPredicate(format: "slug == %@", slug)
                        request.fetchLimit = 1

                        if let existing = try context.fetch(request).first {
                            entryInContext.addToTopics(existing)
                        } else {
                            newTopicNames.append(topicName)
                        }
                    }

                    // Queue new topics for user approval on main thread
                    if !newTopicNames.isEmpty {
                        let entryObjID = objectID
                        Task { @MainActor in
                            let approval = TopicApprovalService.shared
                            for name in newTopicNames {
                                approval.suggest(name: name, entryObjectID: entryObjID)
                            }
                        }
                    }

                    // Store inference summary
                    let summary = InferenceSummary(context: context)
                    summary.id = UUID()
                    summary.entryId = entryInContext.id
                    summary.summaryText = result.summary
                    summary.createdAt = Date()
                    summary.entry = entryInContext

                    // Update title if provided
                    if let title = result.title {
                        entryInContext.title = title
                    }

                    // Mark task completed
                    if let task = entryInContext.latestProcessingTask {
                        task.status = ProcessingTask.Status.completed.rawValue
                        task.progressDescription = nil
                        task.processedAt = Date()
                    }

                    try context.save()
                } catch {
                    self.markFailed(objectID: objectID, error: error, context: context)
                }
            }
        } catch {
            await context.perform {
                self.markFailed(objectID: objectID, error: error, context: context)
            }
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
            print("Failed to fetch pending tasks: \(error)")
        }
    }

    // MARK: - Helpers

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
            print("Failed to mark task as failed: \(error)")
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
