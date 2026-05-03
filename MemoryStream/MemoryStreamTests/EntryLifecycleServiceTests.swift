import Testing
import Foundation
import CoreData
@testable import MemoryStream

@MainActor
@Suite(.serialized)
struct EntryLifecycleServiceTests {

    // MARK: - Setup

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        // processingEngine: nil so edit() doesn't fire a real cloud analyze.
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    @discardableResult
    private func seedEntry(
        in storage: StorageService,
        content: String = "seed content",
        topicNames: [String] = [],
        addEntity: Bool = false,
        audioFilePath: String? = nil
    ) throws -> JournalEntry {
        let entry = try storage.createEntry(content: content, inputType: .typed)
        entry.audioFilePath = audioFilePath
        for name in topicNames {
            let topic = try storage.findOrCreateTopic(name: name)
            entry.addToTopics(topic)
        }
        if addEntity {
            _ = try storage.createEntity(
                entryId: entry.id,
                type: .person,
                value: "Sarah",
                confidence: 0.9,
                method: "cloud",
                entry: entry
            )
        }
        try storage.viewContext.save()
        return entry
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    // MARK: - Edit

    @Test func edit_changingContent_clearsExtractedEntitiesAndQueuesNewTask() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "original", addEntity: true)
        // Confirm the seeded entity actually exists before the edit.
        #expect(entry.entitiesArray.count == 1)

        service.edit(entryId: entry.id, newContent: "completely different content")

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.content == "completely different content")
        // Entities cleared (will be re-extracted by processing engine on cloud round-trip).
        #expect(refreshed.entitiesArray.isEmpty)
        // A fresh ProcessingTask should be queued — the new task is the latest.
        #expect(refreshed.latestProcessingTask?.statusEnum == .pending)
    }

    @Test func edit_unchangedContent_doesNotClearEntities() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "stable content", addEntity: true)

        service.edit(entryId: entry.id, newContent: "stable content")

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        // No reprocessing — entities preserved.
        #expect(refreshed.entitiesArray.count == 1)
    }

    @Test func edit_removesSpecifiedTagIds() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "with entity", addEntity: true)
        let tagId = try #require(entry.entitiesArray.first?.id)

        service.edit(entryId: entry.id, newContent: "with entity", removedTagIds: [tagId])

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.entitiesArray.isEmpty)
    }

    @Test func edit_addsAndRemovesTopics() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "topic test", topicNames: ["Garden"])
        #expect(entry.topicsArray.map(\.name) == ["Garden"])

        service.edit(
            entryId: entry.id,
            newContent: "topic test",
            addedTopicNames: ["Cooking"],
            removedTopicNames: ["Garden"]
        )

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        let names = Set(refreshed.topicsArray.map(\.name))
        #expect(names == ["Cooking"])
    }

    @Test func edit_discardAudio_clearsAudioFilePath() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "with audio", audioFilePath: "fake.m4a")
        #expect(entry.audioFilePath == "fake.m4a")

        service.edit(entryId: entry.id, newContent: "with audio", discardAudio: true)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.audioFilePath == nil)
    }

    // MARK: - Delete / Recycle / Restore

    @Test func recycle_setsRecycledFlagAndTimestamp() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        #expect(entry.isRecycled == false)
        #expect(entry.recycledAt == nil)

        service.recycle(entryId: entry.id)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.isRecycled == true)
        #expect(refreshed.recycledAt != nil)
    }

    @Test func restore_clearsRecycledFlagAndTimestamp() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        service.recycle(entryId: entry.id)

        service.restore(entryId: entry.id)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.isRecycled == false)
        #expect(refreshed.recycledAt == nil)
    }

    @Test func emptyRecycleBin_deletesOnlyRecycledEntries() throws {
        let (storage, service) = makeService()
        let kept = try seedEntry(in: storage, content: "kept")
        let trashed = try seedEntry(in: storage, content: "trashed")
        // Snapshot the UUIDs — `trashed.id` is unsafe to read after Core Data
        // deletes the underlying managed object (faulted access crashes).
        let keptId = kept.id
        let trashedId = trashed.id
        service.recycle(entryId: trashedId)

        service.emptyRecycleBin()

        // Active entry survives.
        #expect(fetchEntry(keptId, in: storage) != nil)
        // Recycled entry is gone for good.
        #expect(fetchEntry(trashedId, in: storage) == nil)
    }

    @Test func recycledCountForTopic_countsOnlyRecycledOnesWithThatTopic() throws {
        let (storage, service) = makeService()
        // Active entry tagged Garden — should NOT count.
        _ = try seedEntry(in: storage, content: "active garden", topicNames: ["Garden"])
        // Recycled entry tagged Garden — should count.
        let trashedGarden = try seedEntry(in: storage, content: "trashed garden", topicNames: ["Garden"])
        service.recycle(entryId: trashedGarden.id)
        // Recycled entry tagged Cooking — should NOT count for Garden.
        let trashedCooking = try seedEntry(in: storage, content: "trashed cooking", topicNames: ["Cooking"])
        service.recycle(entryId: trashedCooking.id)

        #expect(service.recycledCountForTopic("Garden") == 1)
        #expect(service.recycledCountForTopic("Cooking") == 1)
        #expect(service.recycledCountForTopic("Nonexistent") == 0)
    }

    @Test func loadRecycledEntries_returnsRecycledOnlySortedNewestFirst() throws {
        let (storage, service) = makeService()
        let activeEntry = try seedEntry(in: storage, content: "active")
        let firstTrashed = try seedEntry(in: storage, content: "first trashed")
        service.recycle(entryId: firstTrashed.id)
        // Force a small time gap so recycledAt timestamps differ deterministically.
        Thread.sleep(forTimeInterval: 0.01)
        let secondTrashed = try seedEntry(in: storage, content: "second trashed")
        service.recycle(entryId: secondTrashed.id)

        let recycled = service.loadRecycledEntries()

        #expect(recycled.count == 2)
        #expect(recycled.first?.id == secondTrashed.id) // newest first
        #expect(recycled.last?.id == firstTrashed.id)
        #expect(!recycled.contains { $0.id == activeEntry.id })
    }

    // MARK: - createEmptyEntry (Contribute Mode lazy-create)

    @Test func createEmptyEntry_persistsRowWithEmptyContent() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)

        #expect(entry.content == "")
        #expect(entry.inputType == JournalEntry.InputType.composed.rawValue)
        let fetched = fetchEntry(entry.id, in: storage)
        #expect(fetched != nil)
        #expect(fetched?.content == "")
    }

    @Test func createEmptyEntry_doesNotEnqueueProcessingTask() throws {
        let (storage, service) = makeService()
        _ = try service.createEmptyEntry(inputType: .voiceInApp)

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        let tasks = try storage.viewContext.fetch(request)
        // Empty entries don't have content to process yet.
        #expect(tasks.isEmpty)
    }

    // MARK: - deleteMediaReferences (Contribute Mode X-cancel)

    @Test func deleteMediaReferences_removesOnlyTheTargetedRefs() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let refA = try storage.createMediaReference(for: entry, localIdentifier: "A", mediaType: .image)
        let refB = try storage.createMediaReference(for: entry, localIdentifier: "B", mediaType: .image)
        let refC = try storage.createMediaReference(for: entry, localIdentifier: "C", mediaType: .voice)

        service.deleteMediaReferences(ids: [refA.id, refC.id])

        let remaining = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let remainingIds = remaining.map(\.id)
        #expect(remainingIds.count == 1)
        #expect(remainingIds.contains(refB.id))
    }

    @Test func deleteMediaReferences_emptySet_isNoOp() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        _ = try storage.createMediaReference(for: entry, localIdentifier: "A", mediaType: .image)

        service.deleteMediaReferences(ids: [])

        let remaining = (entry.mediaReferences as? Set<MediaReference>) ?? []
        #expect(remaining.count == 1)
    }
}
