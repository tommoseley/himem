import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the "duplicate transcript row on Memory Detail" bug
/// (CD review 2026-07-09): a memory renders two rows with identical
/// transcript text.
///
/// Two independent guards:
///
/// 1. **Edge-creation idempotence** (root cause). `StorageService.createEdge`
///    should refuse to create a second edge for the same `(memoryId, clipId)`
///    pair. The `MemoryClipEdge` docstring already claims this invariant
///    ("Uniqueness is enforced at the application layer… via
///    `MemoryClipEdge.exists(clipId:memoryId:in:)`"); the implementation
///    didn't match until this fix.
///
/// 2. **Mapper dedupe** (defense in depth). `EntryMapper.mapToDisplayModel`
///    dedupes `mediaItems` by ref id so a memory whose data already has
///    dupe edges (from CloudKit merge, pre-fix devices, or an unknown
///    write path) still renders one row per unique clip.
@MainActor
@Suite(.serialized)
struct MediaReferenceDuplicateRenderingTests {

    private func makeStorage() -> StorageService {
        StorageService(inMemory: true)
    }

    private func seedMemory(in storage: StorageService, title: String) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        try storage.viewContext.save()
        return entry
    }

    // MARK: - Guard 1: createEdge is idempotent

    /// **Bug-first reproducer.** Two calls to `createEdge` with the same
    /// `(memory, clip)` pair must not produce two edges. Fails on the
    /// pre-fix implementation (which blindly inserts a second edge).
    @Test func createEdgeIsIdempotentForSameMemoryAndClip() throws {
        let storage = makeStorage()
        let memory = try seedMemory(in: storage, title: "Food Discussion")
        let clip = try storage.createVoiceFragment(
            for: memory,
            audioFilename: "cheesecake.caf",
            transcript: "Savory cheesecake. That's different."
        )
        try storage.save(context: storage.viewContext)

        // First edge exists via createVoiceFragment. Now attempt to add
        // a second edge for the same pair — this is what the Sort commit,
        // a re-run of an OrganizePass, or a CloudKit merge could
        // accidentally do.
        try StorageService.createEdge(
            from: memory,
            to: clip,
            linkedAt: Date(),
            in: storage.viewContext
        )
        try storage.save(context: storage.viewContext)

        // The pair-level count must stay at 1 regardless of how many
        // times createEdge was called.
        let edgeCount = memory.edgesArray.filter { $0.clipId == clip.id }.count
        #expect(edgeCount == 1, "createEdge must be idempotent per (memoryId, clipId). Got \(edgeCount) edges.")
        #expect(memory.mediaReferencesArray.count == 1)
    }

    // MARK: - Guard 2: EntryMapper dedupes even if bad data slipped in

    /// **Defense-in-depth.** If dupe edges somehow exist (older bad data
    /// from pre-fix devices, hostile CloudKit merges), the mapper must
    /// still yield one MediaDisplayItem per unique clip so the view
    /// doesn't render two identical rows.
    @Test func entryMapperDedupesMediaItemsByClipId() throws {
        let storage = makeStorage()
        let memory = try seedMemory(in: storage, title: "Food Discussion")
        let clip = try storage.createVoiceFragment(
            for: memory,
            audioFilename: "cheesecake.caf",
            transcript: "Savory cheesecake. That's different."
        )

        // Force a duplicate edge by going around createEdge — mimics
        // corrupted data that already exists on the device.
        let ctx = storage.viewContext
        let extra = MemoryClipEdge(context: ctx)
        extra.id = UUID()
        extra.clipId = clip.id
        extra.memoryId = memory.id
        extra.clip = clip
        extra.memory = memory
        extra.orderInMemory = 1
        extra.linkedAt = Date()
        try storage.save(context: ctx)

        #expect(memory.edgesArray.count == 2, "Precondition: two edges point at the same clip")

        let display = EntryMapper.mapToDisplayModel(memory)
        #expect(display.mediaItems.count == 1, "EntryMapper must dedupe mediaItems by ref id")
        #expect(display.mediaItems.first?.id == clip.id)
    }
}
