import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `EntryLifecycleService.appendClips` — the Captured
/// Clips "Add to existing memory" path.
///
/// Spec contract (`docs/design/Captured Clips · session-first · spec.md`
/// → Bundle confirm sheet · Add-to-existing-memory mode):
/// > **On Add**: clips are appended to the chosen memory in chronological
/// > order. Behavior follows AI Organize spec § 8 (Provenance, editing,
/// > refresh) — the destination memory shows its existing Title + Summary
/// > plus the amber footer `"N new clips · Refresh · 1 assist"`. **No
/// > automatic re-organize.** Refresh runs only on the user's tap.
///
/// The regression guard here is `noProcessingTaskQueued` — that's the one
/// that would let an assist leak silently if someone "fixes" appendClips
/// by piggy-backing on the existing `append()` path.
@MainActor
@Suite(.serialized)
struct EntryLifecycleServiceAppendClipsTests {

    private func makeService() -> (StorageService, EntryLifecycleService) {
        let storage = StorageService(inMemory: true)
        let service = EntryLifecycleService(storage: storage, processingEngine: nil)
        return (storage, service)
    }

    private func seedEntry(in storage: StorageService) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "seed content", inputType: .typed)
        try storage.viewContext.save()
        return entry
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? storage.viewContext.fetch(request).first
    }

    @Test func appendClips_addsVoiceFragmentsInChronologicalOrder() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        let originalOrganizedAt = entry.lastOrganizedAt

        let t0 = Date()
        // Intentionally out-of-order — appendClips must sort by capturedAt.
        let clips: [(audioFilename: String, transcript: String, capturedAt: Date)] = [
            ("clip-c.caf", "third capture", t0.addingTimeInterval(20)),
            ("clip-a.caf", "first capture", t0),
            ("clip-b.caf", "second capture", t0.addingTimeInterval(10)),
        ]

        let count = service.appendClips(entryId: entry.id, clips: clips)
        #expect(count == 3)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        let voiceRefs = refreshed.mediaReferencesArray.filter { $0.mediaTypeEnum == .voice }
        #expect(voiceRefs.count == 3)

        let byTime = voiceRefs.sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
        #expect(byTime.map { $0.osIdentifier } == ["clip-a.caf", "clip-b.caf", "clip-c.caf"])
        #expect(byTime.map { $0.transcript } == ["first capture", "second capture", "third capture"])

        // lastOrganizedAt is unchanged — append marks the memory stale by
        // adding fragments past the last-organize watermark, never by
        // rewinding the watermark itself.
        #expect(refreshed.lastOrganizedAt == originalOrganizedAt)
    }

    /// The regression guard. If someone "simplifies" `appendClips` by
    /// calling `append()` in a loop, this test fails because `append()`
    /// queues a ProcessingTask which fires `processEntry` and drains the
    /// user's assist budget on every clip. The Captured Clips spec is
    /// explicit: refresh is user-tap-only.
    @Test func appendClips_doesNotQueueProcessingTask() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)

        let clips: [(audioFilename: String, transcript: String, capturedAt: Date)] = [
            ("c1.caf", "first", Date()),
            ("c2.caf", "second", Date().addingTimeInterval(5)),
        ]
        service.appendClips(entryId: entry.id, clips: clips)

        let req = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        req.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let tasks = try storage.viewContext.fetch(req)
        #expect(tasks.isEmpty, "appendClips must not queue a ProcessingTask — refresh is user-tap-only per AI Organize §8")
    }

    @Test func appendClips_emptyList_noOp() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        let originalCount = entry.mediaReferencesArray.count

        let count = service.appendClips(entryId: entry.id, clips: [])
        #expect(count == 0)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        #expect(refreshed.mediaReferencesArray.count == originalCount)
    }

    @Test func appendClips_missingEntry_returnsZero() throws {
        let (_, service) = makeService()
        let count = service.appendClips(
            entryId: UUID(),
            clips: [(audioFilename: "x.caf", transcript: "t", capturedAt: Date())]
        )
        #expect(count == 0)
    }

    @Test func appendClips_singleClip_appendsAsVoiceFragment() throws {
        let (storage, service) = makeService()
        let entry = try seedEntry(in: storage)
        let originalCount = entry.mediaReferencesArray.filter { $0.mediaTypeEnum == .voice }.count

        let captured = Date()
        let count = service.appendClips(
            entryId: entry.id,
            clips: [(audioFilename: "one.caf", transcript: "lone capture", capturedAt: captured)]
        )
        #expect(count == 1)

        let refreshed = try #require(fetchEntry(entry.id, in: storage))
        let voiceRefs = refreshed.mediaReferencesArray.filter { $0.mediaTypeEnum == .voice }
        #expect(voiceRefs.count == originalCount + 1)
        let appended = try #require(voiceRefs.first(where: { $0.osIdentifier == "one.caf" }))
        #expect(appended.transcript == "lone capture")
    }
}
