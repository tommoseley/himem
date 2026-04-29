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
    private var foregroundObserver: AnyCancellable?
    private var syncPollTimer: AnyCancellable?
    private var recomputeCancellables = Set<AnyCancellable>()

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.lifecycle = EntryLifecycleService(storage: storage, processingEngine: processingEngine)
        observeStorageChanges()
        observeForeground()
        observeFilterInputs()
        loadEntries()
    }

    func refresh() {
        print("🔄 [SYNC] Pull-to-refresh triggered")
        storage.viewContext.reset()
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
            print("🔄 [SYNC] NSManagedObjectContextObjectsDidChange fired")
            self?.loadEntries()
        }
    }

    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )
        .sink { [weak self] _ in
            print("🔄 [SYNC] App entering foreground — refreshing")
            self?.refresh()
            self?.startSyncPoll()
        }

        // Also stop polling when backgrounded
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncPollTimer?.cancel()
            self?.syncPollTimer = nil
        }

        startSyncPoll()
    }

    private func startSyncPoll() {
        print("🔄 [SYNC] Starting 15s poll timer")
        syncPollTimer?.cancel()
        syncPollTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                print("🔄 [SYNC] Poll tick — resetting context and reloading")
                self?.storage.viewContext.reset()
                self?.loadEntries()
            }
    }

    // MARK: - Entry Operations (delegated to EntryLifecycleService)

    func saveEntry(content: String, inputType: JournalEntry.InputType, audioFilePath: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [], topicName: String? = nil) {
        lifecycle.save(content: content, inputType: inputType, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures, topicName: topicName)
        loadEntries()
    }

    func editEntry(entryId: UUID, newContent: String, removedTagIds: Set<UUID> = [], removedMediaIds: Set<UUID> = [], addedTopicNames: Set<String> = [], removedTopicNames: Set<String> = [], discardAudio: Bool = false) {
        lifecycle.edit(entryId: entryId, newContent: newContent, removedTagIds: removedTagIds, removedMediaIds: removedMediaIds, addedTopicNames: addedTopicNames, removedTopicNames: removedTopicNames, discardAudio: discardAudio)
        loadEntries()
    }

    func appendToEntry(entryId: UUID, additionalContent: String, audioFilePath: String? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []) {
        lifecycle.append(entryId: entryId, additionalContent: additionalContent, audioFilePath: audioFilePath, mediaCaptures: mediaCaptures)
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
            userCorrection: correction ?? current.userCorrection,
            mediaItems: current.mediaItems, recycledAt: current.recycledAt
        )

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
            recycledCount = lifecycle.loadRecycledEntries().count
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
            let firstContent = journalEntries.first?.content.prefix(40) ?? "none"
            print("🔄 [SYNC] loadEntries: \(journalEntries.count) entries, first: \"\(firstContent)\"")
            entries = journalEntries.map { mapToDisplayModel($0) }
            loadTopics()
        } catch {
            print("🔄 [SYNC] loadEntries FAILED: \(error.localizedDescription)")
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
