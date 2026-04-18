import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class JournalViewModel: ObservableObject {
    @Published var entries: [EntryDisplayModel] = []
    @Published var topics: [String] = []
    @Published var selectedTopic: String? = nil

    private let storage = StorageService.shared
    private let processingEngine = ProcessingEngine.shared
    private var contextObserver: AnyCancellable?
    private var useMockData = false

    init() {
        if useMockData {
            loadMockData()
        } else {
            observeStorageChanges()
            loadEntries()
        }
    }

    // MARK: - Observe Core Data Changes

    private func observeStorageChanges() {
        contextObserver = NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: storage.viewContext
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.loadEntries()
        }
    }

    // MARK: - Entry Creation

    func saveEntry(
        content: String,
        inputType: JournalEntry.InputType,
        audioFilePath: String? = nil,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    ) {
        if useMockData {
            saveMockEntry(content: content, inputType: inputType)
            return
        }

        do {
            let entry = try storage.createEntry(content: content, inputType: inputType)
            entry.audioFilePath = audioFilePath
            try storage.save(context: storage.viewContext)
            let _ = try storage.createProcessingTask(for: entry)

            // Create MediaReference records for any captured media
            var savedRefs: [MediaReference] = []
            for capture in mediaCaptures {
                let ref = try storage.createMediaReference(
                    for: entry,
                    localIdentifier: capture.localIdentifier,
                    mediaType: capture.mediaType
                )
                savedRefs.append(ref)
            }

            loadEntries()

            // Cache thumbnails in background
            if !savedRefs.isEmpty {
                Task.detached {
                    for ref in savedRefs {
                        let filename = await ThumbnailService.shared.cacheThumbnail(for: ref.osIdentifier)
                        if let filename {
                            try? StorageService.shared.updateThumbnailFilename(ref, filename: filename)
                        }
                    }
                }
            }

            // Kick off background processing
            Task.detached { [processingEngine] in
                await processingEngine.processEntry(entry)
            }
        } catch {
            print("Failed to save entry: \(error)")
        }
    }

    // MARK: - Edit and Re-process

    func editEntry(entryId: UUID, newContent: String, removedTagIds: Set<UUID> = [], discardAudio: Bool = false) {
        guard !useMockData else { return }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        request.fetchLimit = 1

        do {
            guard let entry = try storage.viewContext.fetch(request).first else { return }

            let textChanged = entry.content != newContent

            // Discard audio if requested
            if discardAudio, let audioPath = entry.audioFilePath {
                AudioPlayerService.deleteAudio(filename: audioPath)
                entry.audioFilePath = nil
            }

            // Remove specific tags
            if !removedTagIds.isEmpty {
                if let entities = entry.extractedEntities as? Set<ExtractedEntity> {
                    for entity in entities where removedTagIds.contains(entity.id) {
                        storage.viewContext.delete(entity)
                    }
                }
            }

            if textChanged {
                entry.content = newContent

                // Clear remaining entities (will be re-extracted)
                if let entities = entry.extractedEntities as? Set<ExtractedEntity> {
                    for entity in entities {
                        storage.viewContext.delete(entity)
                    }
                }

                // Clear old inference summary
                if let summary = entry.inferenceSummary {
                    storage.viewContext.delete(summary)
                }

                // Clear old topics associations
                if let topics = entry.topics as? Set<Topic> {
                    for topic in topics {
                        entry.removeFromTopics(topic)
                    }
                }

                // Clear old processing tasks
                if let tasks = entry.processingTasks as? Set<ProcessingTask> {
                    for task in tasks {
                        storage.viewContext.delete(task)
                    }
                }

                // Create new processing task
                let _ = try storage.createProcessingTask(for: entry)
                try storage.save(context: storage.viewContext)
                loadEntries()

                // Re-process
                Task.detached { [processingEngine] in
                    await processingEngine.processEntry(entry)
                }
            } else {
                // Tags-only change, no re-processing needed
                try storage.save(context: storage.viewContext)
                loadEntries()
            }
        } catch {
            print("Failed to edit entry: \(error)")
        }
    }

    // MARK: - Delete

    func deleteEntry(entryId: UUID) {
        // Optimistic UI removal
        entries.removeAll { $0.id == entryId }

        if !useMockData {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
            request.fetchLimit = 1
            do {
                if let entry = try storage.viewContext.fetch(request).first {
                    storage.viewContext.delete(entry)
                    try storage.save(context: storage.viewContext)
                }
            } catch {
                print("Failed to delete entry: \(error)")
                loadEntries() // Reload to restore state on failure
            }
        }
    }

    // MARK: - Feedback

    func submitFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String? = nil) {
        // Optimistic UI update
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let current = entries[index]
        entries[index] = EntryDisplayModel(
            id: current.id,
            displayTitle: current.displayTitle,
            content: current.content,
            inputType: current.inputType,
            createdAt: current.createdAt,
            processingStatus: current.processingStatus,
            progressDescription: current.progressDescription,
            tags: current.tags,
            topicNames: current.topicNames,
            audioFilePath: current.audioFilePath,
            inferenceSummary: current.inferenceSummary,
            feedbackState: state,
            mediaItems: current.mediaItems
        )

        if !useMockData {
            persistFeedback(entryId: entryId, state: state, correction: correction)
        }
    }

    private func persistFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String?) {
        let request = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        request.predicate = NSPredicate(format: "entryId == %@", entryId as CVarArg)
        request.fetchLimit = 1

        do {
            if let summary = try storage.viewContext.fetch(request).first {
                try storage.updateFeedback(summary, state: state, correction: correction)
            }
        } catch {
            print("Failed to persist feedback: \(error)")
        }
    }

    // MARK: - Load from Core Data

    private func loadEntries() {
        let request = JournalEntry.fetchAllChronological()
        do {
            let journalEntries = try storage.viewContext.fetch(request)
            entries = journalEntries.map { mapToDisplayModel($0) }
            loadTopics()
        } catch {
            print("Failed to load entries: \(error)")
        }
    }

    private func loadTopics() {
        let request = Topic.fetchAll()
        do {
            let topicEntities = try storage.viewContext.fetch(request)
            topics = topicEntities.map(\.name)
        } catch {
            print("Failed to load topics: \(error)")
        }
    }

    private func mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel {
        let task = entry.latestProcessingTask
        let inference = entry.inferenceSummary

        return EntryDisplayModel(
            id: entry.id,
            displayTitle: entry.displayTitle,
            content: entry.content,
            inputType: entry.inputTypeEnum,
            createdAt: entry.createdAt,
            processingStatus: task?.statusEnum,
            progressDescription: task?.progressDescription,
            tags: entry.entitiesArray.map { entity in
                TagDisplayModel(
                    id: entity.id,
                    value: entity.value,
                    entityType: entity.entityTypeEnum,
                    confidence: entity.confidenceScore
                )
            },
            topicNames: entry.topicsArray.map(\.name),
            audioFilePath: entry.audioFilePath,
            inferenceSummary: inference?.summaryText,
            feedbackState: inference?.feedbackStateEnum,
            mediaItems: entry.mediaReferencesArray.map { ref in
                MediaDisplayItem(
                    id: ref.id,
                    localIdentifier: ref.osIdentifier,
                    mediaType: ref.mediaTypeEnum,
                    thumbnailCacheFilename: ref.thumbnailCacheFilename,
                    isAccessible: ref.isAccessible
                )
            }
        )
    }

    // MARK: - Mock Data

    private func saveMockEntry(content: String, inputType: JournalEntry.InputType) {
        let entry = EntryDisplayModel(
            id: UUID(),
            displayTitle: inputType == .typed ? "Journal entry" : "Hands-free capture",
            content: content,
            inputType: inputType,
            createdAt: Date(),
            processingStatus: .pending,
            progressDescription: nil,
            tags: [],
            topicNames: [],
            audioFilePath: nil,
            inferenceSummary: nil,
            feedbackState: nil,
            mediaItems: []
        )
        entries.insert(entry, at: 0)
    }

    private func loadMockData() {
        topics = ["Garden", "Combine", "Astro"]

        let calendar = Calendar.current
        let today = Date()

        entries = [
            EntryDisplayModel(
                id: UUID(),
                displayTitle: "Hands-free capture",
                content: "The peppers in Bed 4 need more water \u{2014} leaves are curling, and I should probably film this for YouTube later.",
                inputType: .siri,
                createdAt: calendar.date(bySettingHour: 11, minute: 6, second: 0, of: today)!,
                processingStatus: .processing,
                progressDescription: "Raw note saved. The app is extracting beds, plant condition, and content intent.",
                tags: [
                    TagDisplayModel(id: UUID(), value: "Bed 4", entityType: .project, confidence: 0.92),
                    TagDisplayModel(id: UUID(), value: "Peppers", entityType: .project, confidence: 0.88),
                    TagDisplayModel(id: UUID(), value: "Water stress", entityType: .issue, confidence: 0.85),
                    TagDisplayModel(id: UUID(), value: "YouTube idea", entityType: .idea, confidence: 0.78),
                ],
                topicNames: ["Garden"],
                audioFilePath: nil,
                inferenceSummary: "Saved immediately from Siri, linked to Bed 4, and flagged as both a plant-health note and a content opportunity.",
                feedbackState: nil,
                mediaItems: []
            ),
            EntryDisplayModel(
                id: UUID(),
                displayTitle: "Garden session",
                content: "I weeded the garden today. Beds 1 and 2 were really bad.",
                inputType: .typed,
                createdAt: calendar.date(bySettingHour: 9, minute: 42, second: 0, of: today)!,
                processingStatus: .completed,
                progressDescription: nil,
                tags: [],
                topicNames: ["Garden"],
                audioFilePath: nil,
                inferenceSummary: nil,
                feedbackState: .confirmed,
                mediaItems: []
            ),
        ]
    }
}
