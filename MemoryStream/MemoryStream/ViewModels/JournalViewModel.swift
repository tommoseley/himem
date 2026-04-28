import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class JournalViewModel: ObservableObject {
    @Published var entries: [EntryDisplayModel] = []
    @Published var topics: [String] = []
    @Published var selectedTopic: String? = nil

    private let storage: StorageService
    private let lifecycle: EntryLifecycleService
    private var contextObserver: AnyCancellable?
    private var useMockData = false

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.lifecycle = EntryLifecycleService(storage: storage, processingEngine: processingEngine)
        if useMockData {
            loadMockData()
        } else {
            observeStorageChanges()
            loadEntries()
        }
    }

    /// Live lookup by id. Use this in views that need to re-render after the
    /// underlying entry changes; snapshot values captured at navigation time
    /// will not reflect subsequent appends.
    func currentEntry(id: UUID) -> EntryDisplayModel? {
        entries.first { $0.id == id }
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

    // MARK: - Entry Operations (delegated to EntryLifecycleService)

    func saveEntry(content: String, inputType: JournalEntry.InputType, audioFilePath: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [], topicName: String? = nil) {
        if useMockData { saveMockEntry(content: content, inputType: inputType); return }
        lifecycle.save(content: content, inputType: inputType, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures, topicName: topicName)
    }

    func editEntry(entryId: UUID, newContent: String, removedTagIds: Set<UUID> = [], removedMediaIds: Set<UUID> = [], addedTopicNames: Set<String> = [], removedTopicNames: Set<String> = [], discardAudio: Bool = false) {
        guard !useMockData else { return }
        lifecycle.edit(entryId: entryId, newContent: newContent, removedTagIds: removedTagIds, removedMediaIds: removedMediaIds, addedTopicNames: addedTopicNames, removedTopicNames: removedTopicNames, discardAudio: discardAudio)
    }

    func appendToEntry(entryId: UUID, additionalContent: String, audioFilePath: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []) {
        guard !useMockData else { return }
        lifecycle.append(entryId: entryId, additionalContent: additionalContent, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures)
    }

    func deleteEntry(entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        guard !useMockData else { return }
        lifecycle.delete(entryId: entryId)
    }

    func recycleEntry(entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        guard !useMockData else { return }
        lifecycle.recycle(entryId: entryId)
    }

    func restoreEntry(entryId: UUID) {
        guard !useMockData else { return }
        lifecycle.restore(entryId: entryId)
    }

    func loadRecycledEntries() -> [EntryDisplayModel] {
        guard !useMockData else { return [] }
        return lifecycle.loadRecycledEntries()
    }

    func recycledCountForTopic(_ topicName: String) -> Int {
        guard !useMockData else { return 0 }
        return lifecycle.recycledCountForTopic(topicName)
    }

    func emptyRecycleBin() {
        guard !useMockData else { return }
        lifecycle.emptyRecycleBin()
    }

    func submitFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String? = nil) {
        // Optimistic UI update
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let current = entries[index]
        entries[index] = EntryDisplayModel(
            id: current.id, displayTitle: current.displayTitle, content: current.content,
            inputType: current.inputType, createdAt: current.createdAt,
            processingStatus: current.processingStatus, progressDescription: current.progressDescription,
            tags: current.tags, topicNames: current.topicNames, audioFilePath: current.audioFilePath,
            inferenceSummary: current.inferenceSummary, feedbackState: state,
            mediaItems: current.mediaItems, recycledAt: current.recycledAt
        )
        if !useMockData {
            lifecycle.submitFeedback(entryId: entryId, state: state, correction: correction)
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
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    private func loadTopics() {
        let request = Topic.fetchAll()
        do {
            let topicEntities = try storage.viewContext.fetch(request)
            topics = topicEntities.map(\.name)
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    private func mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel {
        EntryMapper.mapToDisplayModel(entry)
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
            mediaItems: [],
            recycledAt: nil
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
                mediaItems: [],
            recycledAt: nil
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
                mediaItems: [],
            recycledAt: nil
            ),
        ]
    }
}
