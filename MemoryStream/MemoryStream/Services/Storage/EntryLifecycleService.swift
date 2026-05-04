import Foundation
import CoreData

/// Extracted from JournalViewModel — handles all entry CRUD operations.
/// JournalViewModel becomes a thin orchestrator that calls this service
/// and updates @Published state.
@MainActor
final class EntryLifecycleService {
    private let storage: StorageService
    private let processingEngine: ProcessingEngine?

    init(storage: StorageService = .shared, processingEngine: ProcessingEngine? = .shared) {
        self.storage = storage
        self.processingEngine = processingEngine
    }

    // MARK: - Create

    /// Creates a new JournalEntry with no content and no media. Used by
    /// Contribute Mode when the user enters a new-memory session — the entry
    /// is created lazily on the first capture, populated as captures are
    /// taken, and either preserved on Done or deleted on X.
    ///
    /// Unlike `save(content:inputType:...)`, this does NOT enqueue a
    /// processing task or capture location. Those happen at session end (or
    /// per-capture as appropriate) once we know the entry has real content.
    func createEmptyEntry(inputType: JournalEntry.InputType) throws -> JournalEntry {
        return try storage.createEntry(content: "", inputType: inputType)
    }

    /// Creates a single MediaReference attached to the entry with the given
    /// id. Used by Contribute Mode to persist each capture as it's taken
    /// (rather than buffering and committing in batch like the legacy
    /// composer). Throws if the entry can't be found.
    @discardableResult
    func createMediaReference(forEntryId entryId: UUID, localIdentifier: String, mediaType: MediaReference.MediaType) throws -> MediaReference {
        guard let entry = try fetchEntry(id: entryId) else {
            throw NSError(domain: "EntryLifecycleService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry \(entryId) not found"])
        }
        return try storage.createMediaReference(for: entry, localIdentifier: localIdentifier, mediaType: mediaType)
    }

    /// Deletes the specified MediaReferences (and their cached thumbnails, and
    /// for voice refs, the underlying audio file) by id, regardless of which
    /// entry they belong to. Used by Contribute Mode's X-cancel to remove only
    /// this-session captures, leaving any pre-existing captures on an
    /// append-anchor entry untouched.
    func deleteMediaReferences(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            for id in ids {
                let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                guard let ref = try storage.viewContext.fetch(request).first else { continue }
                if let cacheFile = ref.thumbnailCacheFilename {
                    ThumbnailService.shared.evictThumbnail(filename: cacheFile)
                }
                // For voice refs, osIdentifier is the audio file path — delete
                // it from disk so X-discard doesn't leave orphan audio files.
                // (Photos and videos live in PhotoKit, not our sandbox; we
                // intentionally leave those in place.)
                if ref.mediaTypeEnum == .voice {
                    AudioPlayerService.deleteAudio(filename: ref.osIdentifier)
                }
                storage.viewContext.delete(ref)
            }
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func save(
        content: String,
        inputType: JournalEntry.InputType,
        audioFilePath: String? = nil,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = [],
        topicName: String? = nil
    ) {
        do {
            let entry = try storage.createEntry(content: content, inputType: inputType)
            entry.audioFilePath = audioFilePath
            try storage.save(context: storage.viewContext)
            let _ = try storage.createProcessingTask(for: entry)

            if let topicName {
                let paletteKey = TopicPaletteStore.shared.key(for: topicName)
                let topic = try storage.findOrCreateTopic(name: topicName, paletteKey: paletteKey)
                entry.addToTopics(topic)
                try storage.save(context: storage.viewContext)
            }

            let savedRefs = try createMediaReferences(for: entry, mediaCaptures: mediaCaptures)
            cacheThumbnails(for: savedRefs)
            captureLocation(for: entry)
            processEntry(entry)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - Location capture (fire-and-forget, doesn't block save)

    private func captureLocation(for entry: JournalEntry) {
        let entryId = entry.id
        Task { @MainActor in
            let toggleOn = UserDefaults.standard.object(forKey: "tagMemoriesWithLocation") as? Bool ?? true
            guard toggleOn else { return }

            // Existing users who already cleared onboarding never saw the
            // location row, so authorization is still .notDetermined for
            // them. Request it the first time we try to tag — the iOS
            // system prompt fires once per app install.
            let granted = await LocationService.shared.requestWhenInUseAuthorization()
            guard granted else { return }

            guard let fix = await LocationService.shared.currentLocation() else { return }
            guard let entry = try? self.fetchEntry(id: entryId) else { return }
            entry.latitude = NSNumber(value: fix.coordinate.latitude)
            entry.longitude = NSNumber(value: fix.coordinate.longitude)
            try? self.storage.save(context: self.storage.viewContext)

            // Reverse-geocode separately so the lat/lon land immediately even
            // if the network is slow.
            if let name = await LocationService.shared.reverseGeocode(fix) {
                if let refreshed = try? self.fetchEntry(id: entryId) {
                    refreshed.locationName = name
                    try? self.storage.save(context: self.storage.viewContext)
                }
            }
        }
    }

    // MARK: - Edit

    func edit(
        entryId: UUID,
        newContent: String,
        removedTagIds: Set<UUID> = [],
        removedMediaIds: Set<UUID> = [],
        addedTopicNames: Set<String> = [],
        removedTopicNames: Set<String> = [],
        discardAudio: Bool = false
    ) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            let textChanged = entry.content != newContent

            if discardAudio, let audioPath = entry.audioFilePath {
                AudioPlayerService.deleteAudio(filename: audioPath)
                entry.audioFilePath = nil
            }

            removeEntities(from: entry, ids: removedTagIds)
            removeMedia(from: entry, ids: removedMediaIds)
            removeTopics(from: entry, names: removedTopicNames)
            addTopics(to: entry, names: addedTopicNames)

            if textChanged {
                entry.content = newContent
                clearForReprocessing(entry)
                let _ = try storage.createProcessingTask(for: entry)
                try storage.save(context: storage.viewContext)
                processEntry(entry)
            } else {
                try storage.save(context: storage.viewContext)
            }
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
        }
    }

    // MARK: - Append

    func append(
        entryId: UUID,
        additionalContent: String,
        audioFilePath: String? = nil,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    ) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }

            let trimmed = additionalContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entry.content = entry.content + "\n\n" + trimmed
            }

            if let audioFilePath {
                entry.audioFilePath = audioFilePath
            }

            let savedRefs = try createMediaReferences(for: entry, mediaCaptures: mediaCaptures)
            clearForReprocessing(entry)
            let _ = try storage.createProcessingTask(for: entry)
            try storage.save(context: storage.viewContext)
            cacheThumbnails(for: savedRefs)
            processEntry(entry)
        } catch {
            ErrorState.shared.report(.editFailed(error.localizedDescription))
        }
    }

    // MARK: - Delete / Recycle

    func delete(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            storage.viewContext.delete(entry)
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func recycle(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            entry.isRecycled = true
            entry.recycledAt = Date()
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func restore(entryId: UUID) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            entry.isRecycled = false
            entry.recycledAt = nil
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    func emptyRecycleBin() {
        do {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "isRecycled == YES")
            let entries = try storage.viewContext.fetch(request)
            for entry in entries {
                storage.viewContext.delete(entry)
            }
            try storage.save(context: storage.viewContext)
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
        }
    }

    // MARK: - Feedback

    func submitFeedback(entryId: UUID, state: InferenceSummary.FeedbackState, correction: String? = nil) {
        do {
            guard let entry = try fetchEntry(id: entryId) else { return }
            guard let summary = entry.inferenceSummary else { return }
            try storage.updateFeedback(summary, state: state, correction: correction)
        } catch {
            ErrorState.shared.report(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - Queries

    func loadRecycledEntries() -> [EntryDisplayModel] {
        do {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "isRecycled == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.recycledAt, ascending: false)]
            return try storage.viewContext.fetch(request).map { EntryMapper.mapToDisplayModel($0) }
        } catch {
            ErrorState.shared.report(.deleteFailed(error.localizedDescription))
            return []
        }
    }

    func recycledCountForTopic(_ topicName: String) -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == YES AND ANY topics.name == %@", topicName)
        return (try? storage.viewContext.count(for: request)) ?? 0
    }

    /// Counts every recycled entry without materializing the rows. Cheap;
    /// use this in derived state instead of `loadRecycledEntries().count`.
    func recycledCount() -> Int {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == YES")
        return (try? storage.viewContext.count(for: request)) ?? 0
    }

    // MARK: - Private Helpers

    private func fetchEntry(id: UUID) throws -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try storage.viewContext.fetch(request).first
    }

    private func createMediaReferences(
        for entry: JournalEntry,
        mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)]
    ) throws -> [MediaReference] {
        var refs: [MediaReference] = []
        for capture in mediaCaptures {
            let ref = try storage.createMediaReference(
                for: entry,
                localIdentifier: capture.localIdentifier,
                mediaType: capture.mediaType
            )
            refs.append(ref)
        }
        return refs
    }

    private func cacheThumbnails(for refs: [MediaReference]) {
        guard !refs.isEmpty else { return }
        let storage = self.storage
        Task.detached {
            for ref in refs {
                let filename = await ThumbnailService.shared.cacheThumbnail(for: ref.osIdentifier)
                if let filename {
                    try? storage.updateThumbnailFilename(ref, filename: filename)
                }
            }
        }
    }

    private func processEntry(_ entry: JournalEntry) {
        guard let processingEngine else { return }
        Task.detached {
            await processingEngine.processEntry(entry)
        }
    }

    private func removeEntities(from entry: JournalEntry, ids: Set<UUID>) {
        guard !ids.isEmpty, let entities = entry.extractedEntities as? Set<ExtractedEntity> else { return }
        for entity in entities where ids.contains(entity.id) {
            storage.viewContext.delete(entity)
        }
    }

    private func removeMedia(from entry: JournalEntry, ids: Set<UUID>) {
        guard !ids.isEmpty, let refs = entry.mediaReferences as? Set<MediaReference> else { return }
        for ref in refs where ids.contains(ref.id) {
            if let cacheFile = ref.thumbnailCacheFilename {
                ThumbnailService.shared.evictThumbnail(filename: cacheFile)
            }
            storage.viewContext.delete(ref)
        }
    }

    private func removeTopics(from entry: JournalEntry, names: Set<String>) {
        guard !names.isEmpty, let topics = entry.topics as? Set<Topic> else { return }
        for topic in topics where names.contains(topic.name) {
            entry.removeFromTopics(topic)
        }
    }

    private func addTopics(to entry: JournalEntry, names: Set<String>) {
        for topicName in names {
            let paletteKey = TopicPaletteStore.shared.key(for: topicName)
            if let topic = try? storage.findOrCreateTopic(name: topicName, paletteKey: paletteKey) {
                entry.addToTopics(topic)
            }
        }
    }

    private func clearForReprocessing(_ entry: JournalEntry) {
        if let entities = entry.extractedEntities as? Set<ExtractedEntity> {
            for entity in entities { storage.viewContext.delete(entity) }
        }
        if let summary = entry.inferenceSummary {
            storage.viewContext.delete(summary)
        }
        if let topics = entry.topics as? Set<Topic> {
            for topic in topics { entry.removeFromTopics(topic) }
        }
        if let tasks = entry.processingTasks as? Set<ProcessingTask> {
            for task in tasks { storage.viewContext.delete(task) }
        }
    }
}
