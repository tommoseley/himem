import Testing
import Foundation
import CoreData
@testable import HiMem

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
        addEntity: Bool = false
    ) throws -> JournalEntry {
        let entry = try storage.createEntry(content: content, inputType: .typed)
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

    /// Money test for the "edited title is silently dropped" bug. EntryExpandedView
    /// captured editedTitle locally but never passed it through to lifecycle.edit,
    /// so user title edits never persisted.
    @Test func edit_settingNewTitle_persistsTitle() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "some content")

        service.edit(entryId: entry.id, newContent: "some content", newTitle: "My Caption")

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.title == "My Caption")
    }

    /// Money test for the "after first capture, return to home instead of
    /// opening the new memory" bug. The fix path requires save() to return
    /// the newly-created entry's id so the JournalView can navigate to it.
    @Test func save_returnsNewEntryId() throws {
        let (storage, service) = makeService()

        let id = service.save(content: "fresh capture", inputType: .typed)

        let unwrapped = try #require(id)
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", unwrapped as CVarArg)
        let fetched = try storage.viewContext.fetch(request)
        #expect(fetched.count == 1)
        #expect(fetched.first?.content == "fresh capture")
    }

    /// nil newTitle (the default) means "don't touch the title" — distinct from
    /// "clear it." Used when the user only edits content/topics/etc.
    @Test func edit_newTitleNil_preservesExistingTitle() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage, content: "original")
        entry.title = "Original Title"
        try storage.viewContext.save()

        service.edit(entryId: entry.id, newContent: "changed content")

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.title == "Original Title")
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
        // Queries live on EntryQueryService since CRAP Batch 3 (2026-05-28).
        let queries = EntryQueryService(storage: storage)
        // Active entry tagged Garden — should NOT count.
        _ = try seedEntry(in: storage, content: "active garden", topicNames: ["Garden"])
        // Recycled entry tagged Garden — should count.
        let trashedGarden = try seedEntry(in: storage, content: "trashed garden", topicNames: ["Garden"])
        service.recycle(entryId: trashedGarden.id)
        // Recycled entry tagged Cooking — should NOT count for Garden.
        let trashedCooking = try seedEntry(in: storage, content: "trashed cooking", topicNames: ["Cooking"])
        service.recycle(entryId: trashedCooking.id)

        #expect(queries.recycledCountForTopic("Garden") == 1)
        #expect(queries.recycledCountForTopic("Cooking") == 1)
        #expect(queries.recycledCountForTopic("Nonexistent") == 0)
    }

    @Test func loadRecycledEntries_returnsRecycledOnlySortedNewestFirst() throws {
        let (storage, service) = makeService()
        let queries = EntryQueryService(storage: storage)
        let activeEntry = try seedEntry(in: storage, content: "active")
        let firstTrashed = try seedEntry(in: storage, content: "first trashed")
        service.recycle(entryId: firstTrashed.id)
        // Force a small time gap so recycledAt timestamps differ deterministically.
        Thread.sleep(forTimeInterval: 0.01)
        let secondTrashed = try seedEntry(in: storage, content: "second trashed")
        service.recycle(entryId: secondTrashed.id)

        let recycled = queries.loadRecycledEntries()

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

    // MARK: - migrateOrphanedContentIfNeeded
    //
    // Money test for the duplicate-note compounding bug observed
    // 2026-05-11: opening a detail view repeatedly minted new `.note`
    // fragments whose body was the joined output of the existing notes,
    // because the old guard only skipped on an exact match between
    // `entry.content` and a single note's text. After `regenerateContent`
    // joined two notes, the joined string matched neither, so each open
    // added one more duplicate, and the next regenerateContent folded it
    // back in.

    @Test func migrateOrphanedContentIfNeeded_skipsWhenAnyNoteFragmentExists() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let refA = try storage.createNoteFragment(for: entry, text: "A", createdAt: Date(timeIntervalSinceReferenceDate: 0))
        let refB = try storage.createNoteFragment(for: entry, text: "B", createdAt: Date(timeIntervalSinceReferenceDate: 1))
        // Simulate post-regenerateContent state: entry.content is the
        // joined output of the two notes, matching neither individually.
        entry.content = "A\n\nB"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: entry.id)

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let noteRefs = refs.filter { $0.mediaTypeEnum == .note }
        #expect(noteRefs.count == 2)
        #expect(noteRefs.map(\.id).sorted() == [refA.id, refB.id].sorted())
    }

    @Test func migrateOrphanedContentIfNeeded_repeatedCalls_doNotCompound() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        _ = try storage.createNoteFragment(for: entry, text: "original", createdAt: Date())
        entry.content = "original"
        try storage.viewContext.save()

        // Simulate opening the detail view 5 times in a row.
        for _ in 0..<5 {
            service.migrateOrphanedContentIfNeeded(entryId: entry.id)
        }

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        #expect(refs.filter { $0.mediaTypeEnum == .note }.count == 1)
    }

    @Test func migrateOrphanedContentIfNeeded_legacyVoiceOnly_mintsNoteForOrphanedContent() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let voiceRef = try storage.createMediaReference(for: entry, localIdentifier: "v.m4a", mediaType: .voice)
        voiceRef.transcript = "voice transcript"
        // Orphaned typed content that the voice transcript does NOT cover.
        entry.content = "typed body unrelated to voice"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: entry.id)

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let noteRefs = refs.filter { $0.mediaTypeEnum == .note }
        #expect(noteRefs.count == 1)
        #expect(noteRefs.first?.text == "typed body unrelated to voice")
    }

    /// Money test for 2026-05-12: an entry with multiple voice fragments
    /// whose joined transcripts ARE `entry.content` was triggering the
    /// auto-migrator to mint a consolidated `.note` containing the joined
    /// blob — the old guard only matched single-voice equality, so a
    /// 3-voice entry's joined content matched none of the transcripts
    /// individually and the migrator minted. Every detail-view open
    /// recreated it after the user deleted it, including in CloudKit.
    @Test func migrateOrphanedContentIfNeeded_skipsWhenContentEqualsJoinedFromMultipleVoices() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let v1 = try storage.createMediaReference(for: entry, localIdentifier: "v1.m4a", mediaType: .voice)
        v1.transcript = "first voice"
        v1.createdAt = Date(timeIntervalSinceReferenceDate: 0)
        let v2 = try storage.createMediaReference(for: entry, localIdentifier: "v2.m4a", mediaType: .voice)
        v2.transcript = "second voice"
        v2.createdAt = Date(timeIntervalSinceReferenceDate: 1)
        let v3 = try storage.createMediaReference(for: entry, localIdentifier: "v3.m4a", mediaType: .voice)
        v3.transcript = "third voice"
        v3.createdAt = Date(timeIntervalSinceReferenceDate: 2)
        entry.content = "first voice\n\nsecond voice\n\nthird voice"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: entry.id)

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        #expect(refs.filter { $0.mediaTypeEnum == .note }.isEmpty)
    }

    @Test func migrateOrphanedContentIfNeeded_voiceTranscriptMatchesContent_doesNotMint() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let voiceRef = try storage.createMediaReference(for: entry, localIdentifier: "v.m4a", mediaType: .voice)
        voiceRef.transcript = "shared text"
        entry.content = "shared text"
        try storage.viewContext.save()

        service.migrateOrphanedContentIfNeeded(entryId: entry.id)

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        #expect(refs.filter { $0.mediaTypeEnum == .note }.isEmpty)
    }

    // MARK: - isEntryEmpty
    //
    // Drives the "delete this memory?" prompt that fires after the user
    // removes the last fragment via swipe-delete in the detail view.

    @Test func isEntryEmpty_returnsTrueWhenNoFragments() throws {
        let (_, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        #expect(service.isEntryEmpty(entryId: entry.id) == true)
    }

    @Test func isEntryEmpty_returnsFalseWithAnyFragment() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        _ = try storage.createNoteFragment(for: entry, text: "x", createdAt: Date())
        try storage.viewContext.save()
        #expect(service.isEntryEmpty(entryId: entry.id) == false)
    }

    @Test func isEntryEmpty_returnsTrueAfterDeletingLastFragment() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        let note = try storage.createNoteFragment(for: entry, text: "only fragment", createdAt: Date())
        try storage.viewContext.save()
        #expect(service.isEntryEmpty(entryId: entry.id) == false)

        service.deleteMediaReferences(ids: [note.id])

        #expect(service.isEntryEmpty(entryId: entry.id) == true)
    }

    @Test func delete_removesEntryFromStore() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        // Snapshot the id — once the entry is deleted, reading `@NSManaged`
        // properties off the tombstone object crashes in the UUID bridge.
        let entryId = entry.id

        service.delete(entryId: entryId)

        #expect(fetchEntry(entryId, in: storage) == nil)
    }

    // MARK: - append (per-capture fragments)
    //
    // Money tests for the "captures accumulate in one panel" bug observed
    // 2026-05-11: the user dictated/typed multiple paragraphs into the
    // same entry and the detail view rendered them all stacked inside a
    // single note panel. Root cause was that `append` concatenated text
    // into `entry.content` instead of minting a fragment per capture,
    // then `migrateOrphanedContentIfNeeded` (pre-fix) saw the joined
    // blob as orphaned and minted one big `.note` containing every
    // paragraph. Time is the spine of the memory — each capture should
    // be its own fragment, its own row, its own timestamp.

    @Test func append_typedNote_createsOwnFragmentPerCall() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)

        service.append(entryId: entry.id, additionalContent: "First thought")
        service.append(entryId: entry.id, additionalContent: "Second thought")
        service.append(entryId: entry.id, additionalContent: "Third thought")

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let notes = refs.filter { $0.mediaTypeEnum == .note }
        #expect(notes.count == 3)
        let texts = Set(notes.compactMap(\.text))
        #expect(texts == ["First thought", "Second thought", "Third thought"])
    }

    @Test func append_voiceClip_storesTranscriptOnVoiceFragmentNotInContent() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)

        service.append(
            entryId: entry.id,
            additionalContent: "spoken words here",
            voiceFilename: "clip.m4a"
        )

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let voices = refs.filter { $0.mediaTypeEnum == .voice }
        let notes = refs.filter { $0.mediaTypeEnum == .note }
        #expect(voices.count == 1)
        #expect(voices.first?.transcript == "spoken words here")
        // No phantom note fragment for voice transcripts — the transcript
        // lives on the voice ref and renders through VoiceClipPanel.
        #expect(notes.isEmpty)
    }

    @Test func append_emptyText_withoutMedia_doesNotMintNote() throws {
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)

        service.append(entryId: entry.id, additionalContent: "   ")

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        #expect(refs.isEmpty)
    }

    @Test func append_preservesLegacyOrphanContent_byPromotingItToNoteFragment() throws {
        // Legacy entry: typed-only `save` left text in `entry.content` with
        // no `.note` fragment. When the user later appends, the new path
        // regenerates `entry.content` from fragments — if we don't promote
        // the orphan first, the original text disappears.
        let (storage, service) = makeService()
        let entry = try service.createEmptyEntry(inputType: .composed)
        entry.content = "legacy typed text"
        try storage.viewContext.save()

        service.append(entryId: entry.id, additionalContent: "new thought")

        let refs = (entry.mediaReferences as? Set<MediaReference>) ?? []
        let notes = refs.filter { $0.mediaTypeEnum == .note }
        let texts = Set(notes.compactMap(\.text))
        #expect(notes.count == 2)
        #expect(texts == ["legacy typed text", "new thought"])
    }
}
