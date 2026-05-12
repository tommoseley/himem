import Testing
import Foundation
import CoreData
@testable import MemoryStream

@MainActor
@Suite(.serialized)
struct FragmentMigrationTests {

    // MARK: - Setup

    private func makeStorage() -> StorageService {
        // Reset the migration flag at the start of every test so the
        // completion gate doesn't carry across runs.
        UserDefaults.standard.removeObject(forKey: FragmentMigration.completionFlagKey)
        return StorageService(inMemory: true)
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    // MARK: - Resurrection (money tests for 2026-05-11)

    /// Pure-content entries no longer get a `.note` minted by the migrator
    /// (path 3 removed 2026-05-11). They render via the detail view's
    /// plain-text fallback. This locks in the no-mint contract — the
    /// previous behavior repeatedly resurrected user-deleted notes on
    /// every relaunch.
    @Test func migrate_doesNotMintNoteForPureContentEntry() throws {
        let storage = makeStorage()
        let entry = try storage.createEntry(content: "consolidated text", inputType: .typed)
        try storage.viewContext.save()
        let entryId = entry.id

        FragmentMigration.runIfNeeded(in: storage.viewContext, force: true)

        let refs = (fetchEntry(entryId, in: storage)?.mediaReferences as? Set<MediaReference>) ?? []
        #expect(refs.filter { $0.mediaTypeEnum == .note }.isEmpty)
        // Entry.content stays put — the plain-text fallback renders it.
        #expect(fetchEntry(entryId, in: storage)?.content == "consolidated text")
    }

    /// Path 3 (pure-content → .note mint) must skip entries that already
    /// have any MediaReference attached. Without this, a legacy
    /// audioFilePath-free entry that picked up a photo would still trigger
    /// path 3's mint on every walk — and after the user deletes the
    /// photo-era's accompanying note, it'd resurrect.
    @Test func migrate_doesNotMintNoteForEntry_withExistingPhoto() throws {
        let storage = makeStorage()
        let entry = try storage.createEntry(content: "typed alongside a photo", inputType: .composed)
        _ = try storage.createMediaReference(for: entry, localIdentifier: "photo-1", mediaType: .image)
        try storage.viewContext.save()
        let entryId = entry.id

        FragmentMigration.runIfNeeded(in: storage.viewContext, force: true)

        let refs = (fetchEntry(entryId, in: storage)?.mediaReferences as? Set<MediaReference>) ?? []
        let notes = refs.filter { $0.mediaTypeEnum == .note }
        // Path 3 must skip when the entry already has any MediaReference —
        // promotion of orphan content happens via the detail-view
        // `migrateOrphanedContentIfNeeded` path, not the launch migrator.
        #expect(notes.isEmpty)
    }

    /// Flag must be set after the first successful walk so future launches
    /// short-circuit — regardless of how many entries the walk touched.
    /// The legacy condition (touched == 0) meant migration ran every
    /// launch indefinitely for stores with any work to do.
    @Test func runIfNeeded_setsCompletionFlag_afterFirstSuccessfulWalk() throws {
        let storage = makeStorage()
        _ = try storage.createEntry(content: "X", inputType: .typed)
        try storage.viewContext.save()

        FragmentMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(FragmentMigration.hasCompleted)
    }

    @Test func runIfNeeded_doesNotSetFlag_onEmptyStore() throws {
        // Empty store — CloudKit hasn't synced yet. Flag must stay unset so
        // the next launch retries the walk.
        let storage = makeStorage()

        FragmentMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(!FragmentMigration.hasCompleted)
    }
}
