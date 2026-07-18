import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class JournalViewModel: ObservableObject {
    @Published var entries: [EntryDisplayModel] = []
    @Published var topics: [String] = []
    @Published var selectedTopic: String? = nil
    /// Active mention filter (B4 Phase 2). Set by a mention read-chip tap
    /// (via `MentionFilterBus`); the Memories list filters to memories
    /// carrying it and shows a dismissable banner. No filter strip — it's
    /// reachable only from a mention chip, cleared from the banner.
    @Published var selectedMention: MentionChip? = nil
    @Published private(set) var filteredEntries: [EntryDisplayModel] = []
    @Published private(set) var groupedEntries: [DayGroup] = []
    /// Month-year label for the oldest stored memory (e.g., "March 2024").
    /// Nil when the library is empty. Drives the "The beginning · Your
    /// first memory, ‹month year›" tail marker per Memories list spec §8.
    @Published private(set) var firstMemoryMonthLabel: String? = nil

    struct DayGroup: Identifiable {
        let date: Date
        let label: String
        let entries: [EntryDisplayModel]
        var id: Date { date }
    }

    private let storage: StorageService
    private let lifecycle: EntryLifecycleService
    private let queries: EntryQueryService
    private var contextObserver: AnyCancellable?
    private var remoteChangeObserver: AnyCancellable?
    private var foregroundObserver: AnyCancellable?
    private var recomputeCancellables = Set<AnyCancellable>()

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.lifecycle = EntryLifecycleService(storage: storage, processingEngine: processingEngine)
        self.queries = EntryQueryService(storage: storage)
        observeStorageChanges()
        observeRemoteChanges()
        observeForeground()
        observeFilterInputs()
        // Cold-launch fix 2026-06-02: heavy fetches moved to loadInitial().
        // Previously init ran loadEntries + mergeDuplicateTopics +
        // mergeDuplicateEntities synchronously on the main thread — that
        // blocked the JournalView's first paint by 1–3s on populated
        // devices (mergeDuplicateEntities scales with every entity row in
        // the library). JournalView fires loadInitial() in `.task`, so
        // the work runs after the first frame is rendered. Tests can call
        // loadInitial() directly when they need populated state.
        // See feedback_cold_launch_target memory.
    }

    /// First-paint load. Runs the same work that previously lived in
    /// `init`, but invoked AFTER the view has had a chance to render its
    /// empty/skeleton state. Idempotent — safe to call multiple times.
    func loadInitial() async {
        LaunchSignposter.interval("journalVM.loadInitial") {
            loadEntries()
            // Sweep up CloudKit-induced duplicate topics + entities on launch.
            // These still use viewContext (main-only), but running them after
            // loadEntries means the feed renders first; the merges happen
            // immediately after on the same MainActor turn.
            LaunchSignposter.interval("journalVM.mergeDuplicateTopics") {
                try? storage.mergeDuplicateTopics()
            }
            LaunchSignposter.interval("journalVM.mergeDuplicateEntities") {
                try? storage.mergeDuplicateEntities()
            }
        }
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
            LaunchSignposter.signposter.emitEvent("journalVM.observeStorageChange")
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
    ///
    /// Cold-launch fix 2026-06-02: duplicate-merging was previously
    /// invoked here on every remote-change batch. During CloudKit's
    /// initial mirror import (the slow 10+s post-launch window) the
    /// debounced sink fired up to once every 250ms; each fire ran two
    /// scaled-with-library Core Data fetches on the main thread, leaving
    /// the feed unresponsive during the entire import. The merges are
    /// now invoked in `loadInitial()` (once per launch) and
    /// `observeForeground` (rare user-driven event), which catches all
    /// the duplicate-introduction cases without hammering the runloop.
    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.publisher(
            for: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: storage.container.persistentStoreCoordinator
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            LaunchSignposter.signposter.emitEvent("journalVM.observeRemoteChange")
            self?.loadEntries()
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
    /// `voiceCapturedAt` carries the wall-clock the voice clip *began*
    /// recording (orchestrator-computed from master start + Next-tap
    /// offsets). When nil, the lifecycle save falls back to `Date()` —
    /// the historical behavior for non-roll callers.
    func saveEntry(content: String, inputType: JournalEntry.InputType, voiceFilename: String? = nil, voiceCapturedAt: Date? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [], topicName: String? = nil) -> UUID? {
        let id = lifecycle.save(content: content, inputType: inputType, voiceFilename: voiceFilename, voiceCapturedAt: voiceCapturedAt, mediaCaptures: mediaCaptures, topicName: topicName)
        loadEntries()
        return id
    }

    func editEntry(entryId: UUID, newContent: String, newTitle: String? = nil, removedTagIds: Set<UUID> = [], removedMediaIds: Set<UUID> = [], addedTopicNames: Set<String> = [], removedTopicNames: Set<String> = []) {
        lifecycle.edit(entryId: entryId, newContent: newContent, newTitle: newTitle, removedTagIds: removedTagIds, removedMediaIds: removedMediaIds, addedTopicNames: addedTopicNames, removedTopicNames: removedTopicNames)
        loadEntries()
    }

    func appendToEntry(entryId: UUID, additionalContent: String, voiceFilename: String? = nil, voiceCapturedAt: Date? = nil, mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []) {
        lifecycle.append(entryId: entryId, additionalContent: additionalContent, voiceFilename: voiceFilename, voiceCapturedAt: voiceCapturedAt, mediaCaptures: mediaCaptures)
        loadEntries()
    }

    /// Creates a `.note` MediaReference attached to `entryId`. Used by
    /// the typed-note capture flow so the text shows up as a fragment in
    /// the chronological capture stream alongside any photos/videos.
    /// Without this, `entry.content` would render in the feed (which
    /// reads it directly) but disappear from the detail view's stream
    /// (which walks only `mediaReferences`).
    @discardableResult
    func createNoteFragment(forEntryId entryId: UUID, text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ref = try? lifecycle.createNoteFragment(forEntryId: entryId, text: trimmed)
        loadEntries()
        return ref?.id
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
        return queries.loadRecycledEntries()
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
        // Recompute filtered/grouped whenever entries or selectedTopic change.
        // (Entity-tap filtering was retired with the Memories list redesign —
        // see docs/design/Memories list · spec.md §3.)
        Publishers.CombineLatest3($entries, $selectedTopic, $selectedMention)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] entries, topic, mention in
                self?.recomputeFiltered(entries: entries, topic: topic, mention: mention)
            }
            .store(in: &recomputeCancellables)
    }

    private func recomputeFiltered(entries: [EntryDisplayModel], topic: String?, mention: MentionChip?) {
        var result = entries
        if let topic {
            result = result.filter { $0.topicNames.contains(topic) }
        }
        if let mention {
            result = result.filter { entry in entry.mentions.contains { $0.id == mention.id } }
        }
        filteredEntries = result
        recomputeGrouped(from: result)
        recomputeFirstMemoryLabel(from: entries)
    }

    /// Computes the month-year label for the oldest memory in the
    /// unfiltered list. The tail marker is about the Memory Box's
    /// overall beginning, not the current filter — so we sample from
    /// `entries` not `filteredEntries`.
    private func recomputeFirstMemoryLabel(from entries: [EntryDisplayModel]) {
        // `entries` is sorted descending by createdAt; the last element
        // is the oldest among loaded (subject to the 500-row cap).
        guard let oldest = entries.last?.createdAt else {
            firstMemoryMonthLabel = nil
            return
        }
        firstMemoryMonthLabel = Self.monthYearLabel(for: oldest)
    }

    private static func monthYearLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
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

    private static func dateLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    // MARK: - Load from Core Data

    private func loadEntries() {
        LaunchSignposter.interval("journalVM.loadEntries") {
            let request = JournalEntry.fetchAllChronological()
            do {
                let journalEntries = try storage.viewContext.fetch(request)
                entries = journalEntries.map { mapToDisplayModel($0) }
                loadTopics()
            } catch {
                ErrorState.shared.report(.saveFailed(error.localizedDescription))
            }
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
