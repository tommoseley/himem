import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the "Add to a memory" picker fetch/filter
/// (`ExistingMemoryPickerView`). The picker listed only memories with a
/// clip in the last 7 days and disabled its "Search all" escape, so on a
/// 30–40 memory library only a handful appeared and the rest were
/// unreachable (device bug, 2026-07-21). It must now surface **every**
/// non-recycled memory, most-recent first, filterable by title/date.
@MainActor
@Suite(.serialized)
struct ExistingMemoryPickerFetchTests {

    private func makeStore() -> StorageService { StorageService(inMemory: true) }

    /// A memory whose single clip was captured `daysAgo` days ago.
    @discardableResult
    private func seedMemory(in storage: StorageService, title: String, daysAgo: Double) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = title
        let when = Date().addingTimeInterval(-daysAgo * 86_400)
        _ = try storage.createVoiceFragment(for: entry, audioFilename: "\(title).caf", transcript: title, createdAt: when)
        try storage.viewContext.save()
        return entry
    }

    /// **The money test.** A memory whose only clip is 30 days old MUST
    /// appear — the 7-day window used to drop it, leaving it unreachable.
    @Test func fetchAll_includesMemoriesOlderThanSevenDays() throws {
        let storage = makeStore()
        try seedMemory(in: storage, title: "Ancient", daysAgo: 30)
        try seedMemory(in: storage, title: "Recent", daysAgo: 1)

        let all = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)
        let titles = all.map { ExistingMemoryPickerView.rowTitle($0) }
        #expect(titles.contains("Ancient"), "A memory with only an old clip must still be reachable — no 7-day window")
        #expect(titles.contains("Recent"))
    }

    @Test func fetchAll_sortsMostRecentClipFirst() throws {
        let storage = makeStore()
        try seedMemory(in: storage, title: "Old", daysAgo: 20)
        try seedMemory(in: storage, title: "Newest", daysAgo: 0.5)
        try seedMemory(in: storage, title: "Middle", daysAgo: 5)

        let titles = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)
            .map { ExistingMemoryPickerView.rowTitle($0) }
        #expect(titles == ["Newest", "Middle", "Old"], "Most-recent-clip first")
    }

    @Test func fetchAll_excludesRecycledMemories() throws {
        let storage = makeStore()
        let gone = try seedMemory(in: storage, title: "Deleted", daysAgo: 2)
        gone.isRecycled = true
        gone.recycledAt = Date()
        try seedMemory(in: storage, title: "Alive", daysAgo: 2)
        try storage.viewContext.save()

        let titles = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)
            .map { ExistingMemoryPickerView.rowTitle($0) }
        #expect(titles.contains("Alive"))
        #expect(!titles.contains("Deleted"), "A recycled memory is not a placement target")
    }

    @Test func filter_byTitleSubstring_caseInsensitive() throws {
        let storage = makeStore()
        try seedMemory(in: storage, title: "Kingfisher Wharf", daysAgo: 1)
        try seedMemory(in: storage, title: "Integrity Reflection", daysAgo: 1)
        let all = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)

        let hits = ExistingMemoryPickerView.filter(all, query: "kingfisher")
            .map { ExistingMemoryPickerView.rowTitle($0) }
        #expect(hits == ["Kingfisher Wharf"])
    }

    @Test func filter_byDate_matchesMonthName() throws {
        let storage = makeStore()
        // A clip on a fixed month so the date-name search is deterministic.
        let entry = try storage.createEntry(content: "", inputType: .typed)
        entry.title = "Beach day"
        let july = DateComponents(calendar: .current, year: 2026, month: 7, day: 4).date!
        _ = try storage.createVoiceFragment(for: entry, audioFilename: "b.caf", transcript: "x", createdAt: july)
        try storage.viewContext.save()
        let all = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)

        #expect(ExistingMemoryPickerView.filter(all, query: "jul").count == 1, "Date-name search reaches the memory")
        #expect(ExistingMemoryPickerView.filter(all, query: "beach").count == 1)
        #expect(ExistingMemoryPickerView.filter(all, query: "december").isEmpty)
    }

    @Test func filter_emptyQuery_returnsEverything() throws {
        let storage = makeStore()
        try seedMemory(in: storage, title: "One", daysAgo: 1)
        try seedMemory(in: storage, title: "Two", daysAgo: 2)
        let all = ExistingMemoryPickerView.fetchAllMemories(in: storage.viewContext)
        #expect(ExistingMemoryPickerView.filter(all, query: "   ").count == 2)
    }

    /// **The money test (#3, 2026-07-25).** A memory whose `isRecycled` is a
    /// genuine SQL NULL — the state CloudKit-synced or pre-attribute records
    /// land in — MUST still list in the picker. The old `isRecycled != YES`
    /// predicate compiled to `<> 1`, and `NULL <> 1` is NULL (not true), so it
    /// silently dropped that memory (device: "my only memory won't list").
    ///
    /// This MUST run against a real SQLite store: the in-memory store used by
    /// the other tests evaluates the predicate via Foundation with a scalar
    /// `Bool` default of `false`, where `!= YES` spuriously PASSES — masking
    /// the bug. Reverting the fix to `isRecycled != YES` makes this fail; the
    /// nil-safe `== NO OR == nil` makes it pass.
    @Test func fetchAll_includesMemoryWithNullRecycledFlag_sqliteStore() throws {
        let (container, url) = StorageService.makeSQLiteTestContainer()
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let ctx = container.viewContext

        // Seed three memories: one with a genuine NULL isRecycled, one live
        // (false), one recycled (true).
        for title in ["NullFlag", "LiveFalse", "RecycledTrue"] {
            let e = JournalEntry(context: ctx)
            e.id = UUID()
            e.createdAt = Date()
            e.title = title
            e.isRecycled = (title == "RecycledTrue")
        }
        try ctx.save()

        // Force a genuine SQL NULL on NullFlag via a batch update — this writes
        // straight to the store, bypassing the scalar-Bool coercion that would
        // otherwise store 0. (NSBatchUpdateRequest is unsupported in-memory,
        // which is the other reason this test needs the SQLite store.)
        let batch = NSBatchUpdateRequest(entityName: "JournalEntry")
        batch.predicate = NSPredicate(format: "title == %@", "NullFlag")
        batch.propertiesToUpdate = ["isRecycled": NSExpression(forConstantValue: nil)]
        batch.resultType = .updatedObjectIDsResultType
        let result = try ctx.execute(batch) as? NSBatchUpdateResult
        let updated = (result?.result as? [NSManagedObjectID]) ?? []
        #expect(updated.count == 1, "batch update should NULL exactly the NullFlag row")
        // Batch updates bypass the context — drop cached state so the fetch
        // reads the store's NULL, not the in-memory 0.
        ctx.reset()

        let titles = ExistingMemoryPickerView.fetchAllMemories(in: ctx)
            .map { ExistingMemoryPickerView.rowTitle($0) }
        #expect(titles.contains("NullFlag"), "A NULL-isRecycled memory must list (the #3 bug)")
        #expect(titles.contains("LiveFalse"))
        #expect(!titles.contains("RecycledTrue"), "A genuinely recycled memory stays out")
    }
}
