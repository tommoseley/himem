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

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.lifecycle = EntryLifecycleService(storage: storage, processingEngine: processingEngine)
        observeStorageChanges()
        loadEntries()
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
        lifecycle.save(content: content, inputType: inputType, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures, topicName: topicName)
    }

    func editEntry(entryId: UUID, newContent: String, removedTagIds: Set<UUID> = [], removedMediaIds: Set<UUID> = [], addedTopicNames: Set<String> = [], removedTopicNames: Set<String> = [], discardAudio: Bool = false) {
        lifecycle.edit(entryId: entryId, newContent: newContent, removedTagIds: removedTagIds, removedMediaIds: removedMediaIds, addedTopicNames: addedTopicNames, removedTopicNames: removedTopicNames, discardAudio: discardAudio)
    }

    func appendToEntry(entryId: UUID, additionalContent: String, audioFilePath: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []) {
        lifecycle.append(entryId: entryId, additionalContent: additionalContent, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures)
    }

    func deleteEntry(entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        lifecycle.delete(entryId: entryId)
    }

    func recycleEntry(entryId: UUID) {
        entries.removeAll { $0.id == entryId }
        lifecycle.recycle(entryId: entryId)
    }

    func restoreEntry(entryId: UUID) {
        lifecycle.restore(entryId: entryId)
    }

    func loadRecycledEntries() -> [EntryDisplayModel] {
        return lifecycle.loadRecycledEntries()
    }

    func recycledCountForTopic(_ topicName: String) -> Int {
        return lifecycle.recycledCountForTopic(topicName)
    }

    func emptyRecycleBin() {
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

        lifecycle.submitFeedback(entryId: entryId, state: state, correction: correction)
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
}
