import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class JournalViewModel: ObservableObject {
    @Published var entries: [EntryDisplayModel] = []
    @Published var topics: [String] = []
    @Published var selectedTopic: String? = nil
    @Published var entityFilter: String? = nil
    @Published private(set) var filteredEntries: [EntryDisplayModel] = []
    @Published private(set) var groupedEntries: [DayGroup] = []
    @Published private(set) var recycledCount: Int = 0

    struct DayGroup: Identifiable {
        let date: Date
        let label: String
        let entries: [EntryDisplayModel]
        var id: Date { date }
    }

    private let storage: StorageService
    private let lifecycle: EntryLifecycleService
    private var contextObserver: AnyCancellable?
    private var remoteChangeObserver: AnyCancellable?
    private var foregroundObserver: AnyCancellable?
    private var recomputeCancellables = Set<AnyCancellable>()

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.lifecycle = EntryLifecycleService(storage: storage, processingEngine: processingEngine)
        observeStorageChanges()
        observeRemoteChanges()
        observeForeground()
        observeFilterInputs()
        loadEntries()
        // Sweep up CloudKit-induced duplicate topics on launch.
        try? storage.mergeDuplicateTopics()
        try? storage.mergeDuplicateEntities()
    }

    func refresh() {
        storage.viewContext.refreshAllObjects()
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

    /// `NSPersistentStoreRemoteChange` fires when a background context save
    /// propagates through the persistent store coordinator (e.g. when the
    /// ProcessingEngine finishes its analysis on a bg context and saves the
    /// inference + completed task). The viewContext's auto-merge picks the
    /// change up, BUT the StorageService also calls `refreshAllObjects()` in
    /// the same notification path, which turns viewContext objects into
    /// faults without firing `ObjectsDidChange`. As a result, the
    /// observeStorageChanges path above doesn't reload, and the journal feed
    /// keeps showing the EntryDisplayModel snapshot from before the bg save.
    /// This observer closes the loop so the feed reloads as soon as the
    /// remote change lands.
    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.publisher(
            for: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: storage.container.persistentStoreCoordinator
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.loadEntries()
            // CloudKit may have pulled duplicate topics from another
            // device; merge before they're displayed to the user.
            try? self.storage.mergeDuplicateTopics()
            try? self.storage.mergeDuplicateEntities()
        }
    }

    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )
        .sink { [weak self] _ in
            guard let self else { return }
            self.refresh()
            // Re-sweep duplicates on every foreground in case CloudKit
            // pulled in fresh duplicates while we were backgrounded.
            try? self.storage.mergeDuplicateTopics()
            try? self.storage.mergeDuplicateEntities()
        }
    }

    // MARK: - Entry Operations (delegated to EntryLifecycleService)

    @discardableResult
    func saveEntry(content: String, inputType: JournalEntry.InputType, voiceFilename: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [], topicName: String? = nil) -> UUID? {
        let id = lifecycle.save(content: content, inputType: inputType, voiceFilename: voiceFilename, mediaCaptures: mediaCaptures, topicName: topicName)
        loadEntries()
        return id
    }

    func editEntry(entryId: UUID, newContent: String, newTitle: String? = nil, removedTagIds: Set<UUID> = [], removedMediaIds: Set<UUID> = [], addedTopicNames: Set<String> = [], removedTopicNames: Set<String> = []) {
        lifecycle.edit(entryId: entryId, newContent: newContent, newTitle: newTitle, removedTagIds: removedTagIds, removedMediaIds: removedMediaIds, addedTopicNames: addedTopicNames, removedTopicNames: removedTopicNames)
        loadEntries()
    }

    func appendToEntry(entryId: UUID, additionalContent: String, voiceFilename: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []) {
        lifecycle.append(entryId: entryId, additionalContent: additionalContent, voiceFilename: voiceFilename, mediaCaptures: mediaCaptures)
        loadEntries()
    }

    func deleteEntry(entryId: UUID) {
        lifecycle.delete(entryId: entryId)
        loadEntries()
    }

    func recycleEntry(entryId: UUID) {
        lifecycle.recycle(entryId: entryId)
        loadEntries()
    }

    func restoreEntry(entryId: UUID) {
        lifecycle.restore(entryId: entryId)
        loadEntries()
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

    /// Records that the user opened an entry. Powers the Forgotten card's
    /// "haven't viewed in 3 months" filter.
    func markEntryViewed(_ entryId: UUID) {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        request.fetchLimit = 1
        let ctx = storage.viewContext
        guard let entry = try? ctx.fetch(request).first else { return }
        entry.lastViewedAt = Date()
        try? ctx.save()
    }

    func submitFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String? = nil) {
        // Optimistic UI update — reflect the new feedback state immediately,
        // then let the persisted save catch up via loadEntries.
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            entries[index] = entries[index].with(feedbackState: state, userCorrection: correction)
        }
        lifecycle.submitFeedback(entryId: entryId, state: state, correction: correction)
        loadEntries()
    }

    // MARK: - Derived State

    private func observeFilterInputs() {
        // Recompute filtered/grouped whenever entries, selectedTopic, or entityFilter change
        Publishers.CombineLatest3($entries, $selectedTopic, $entityFilter)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] entries, topic, filter in
                self?.recomputeFiltered(entries: entries, topic: topic, filter: filter)
            }
            .store(in: &recomputeCancellables)
    }

    private func recomputeFiltered(entries: [EntryDisplayModel], topic: String?, filter: String?) {
        var result = entries
        if let topic {
            result = result.filter { $0.topicNames.contains(topic) }
        }
        if let filter, !filter.isEmpty {
            result = result.filter { entry in
                entry.tags.contains { $0.value.localizedCaseInsensitiveContains(filter) }
            }
        }
        filteredEntries = result
        recomputeGrouped(from: result)
        recomputeRecycledCount(topic: topic)
    }

    private func recomputeGrouped(from entries: [EntryDisplayModel]) {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }
        groupedEntries = grouped.sorted { $0.key > $1.key }.map { date, entries in
            DayGroup(date: date, label: Self.dateLabel(for: date, calendar: calendar), entries: entries)
        }
    }

    private func recomputeRecycledCount(topic: String?) {
        if let topic {
            recycledCount = lifecycle.recycledCountForTopic(topic)
        } else {
            recycledCount = lifecycle.recycledCount()
        }
    }

    private static func dateLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
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
            // De-duplicate by name. CloudKit merges occasionally produce two
            // Topic entities with the same name (e.g. both devices created
            // "Garden" before they synced). The UI keys ForEach on name, so
            // duplicates trigger SwiftUI "ID occurs multiple times" warnings.
            var seen: Set<String> = []
            topics = topicEntities.compactMap { topic in
                guard !seen.contains(topic.name) else { return nil }
                seen.insert(topic.name)
                return topic.name
            }
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
    }

    private func mapToDisplayModel(_ entry: JournalEntry) -> EntryDisplayModel {
        EntryMapper.mapToDisplayModel(entry)
    }
}
