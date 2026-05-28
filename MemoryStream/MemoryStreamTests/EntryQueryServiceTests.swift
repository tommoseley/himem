import Testing
import Foundation
import CoreData
@testable import HiMem

/// **Characterization tests** locking in the behavior of the three
/// recycled-entry query methods before they're extracted from
/// `EntryLifecycleService` into a dedicated `EntryQueryService`
/// (CRAP audit Batch 3). The same assertions must pass before AND
/// after the refactor — if they don't, the extraction lost or
/// changed behavior.
///
/// Methods under test (currently on `EntryLifecycleService`,
/// scheduled to move to `EntryQueryService`):
///
///   - `loadRecycledEntries()` — fetches every `isRecycled == YES`
///     entry, sorted by `recycledAt` descending, mapped to
///     `EntryDisplayModel`.
///   - `recycledCount()` — cheap count of every recycled entry.
///   - `recycledCountForTopic(_:)` — count of recycled entries
///     whose topics include the given name.
@MainActor
@Suite(.serialized)
struct EntryQueryServiceTests {

    // MARK: - Setup

    /// Returns a storage instance + the query service wired to it.
    /// Post-2026-05-28 the query methods live on `EntryQueryService`;
    /// before that they were on `EntryLifecycleService`. The test
    /// bodies are unchanged across the refactor — only this helper
    /// flips.
    private func makeService() -> (StorageService, EntryQueryService) {
        let storage = StorageService(inMemory: true)
        let service = EntryQueryService(storage: storage)
        return (storage, service)
    }

    /// Creates an entry, optionally marking it recycled + assigning
    /// topics. `recycledAt` is set so sort-order assertions can be
    /// deterministic.
    @discardableResult
    private func seedEntry(
        in storage: StorageService,
        content: String = "seed",
        topicNames: [String] = [],
        recycled: Bool = false,
        recycledAt: Date? = nil
    ) throws -> JournalEntry {
        let entry = try storage.createEntry(content: content, inputType: .typed)
        for name in topicNames {
            let topic = try storage.findOrCreateTopic(name: name)
            entry.addToTopics(topic)
        }
        if recycled {
            entry.isRecycled = true
            entry.recycledAt = recycledAt ?? Date()
        }
        try storage.viewContext.save()
        return entry
    }

    // MARK: - recycledCount()

    @Test func recycledCount_emptyStore_returnsZero() {
        let (_, service) = makeService()
        #expect(service.recycledCount() == 0)
    }

    @Test func recycledCount_onlyLiveEntries_returnsZero() throws {
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "live one")
        try seedEntry(in: storage, content: "live two")
        #expect(service.recycledCount() == 0)
    }

    @Test func recycledCount_mixedLiveAndRecycled_returnsRecycledOnly() throws {
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "live")
        try seedEntry(in: storage, content: "recycled A", recycled: true)
        try seedEntry(in: storage, content: "recycled B", recycled: true)
        #expect(service.recycledCount() == 2)
    }

    // MARK: - recycledCountForTopic(_:)

    @Test func recycledCountForTopic_noMatches_returnsZero() throws {
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "x", topicNames: ["work"], recycled: true)
        #expect(service.recycledCountForTopic("personal") == 0)
    }

    @Test func recycledCountForTopic_matchesRecycledOnly() throws {
        let (storage, service) = makeService()
        // Live entry with the topic — must NOT be counted.
        try seedEntry(in: storage, content: "live work", topicNames: ["work"])
        // Recycled entries with the topic — counted.
        try seedEntry(in: storage, content: "recycled A", topicNames: ["work"], recycled: true)
        try seedEntry(in: storage, content: "recycled B", topicNames: ["work"], recycled: true)
        // Recycled with a different topic — not counted.
        try seedEntry(in: storage, content: "recycled C", topicNames: ["other"], recycled: true)
        #expect(service.recycledCountForTopic("work") == 2)
    }

    @Test func recycledCountForTopic_caseSensitiveExactMatch() throws {
        // Locks in the current Core Data predicate semantics
        // (`ANY topics.name == %@`) — case-sensitive exact match.
        // If the predicate ever changes to `[c]` or `LIKE`, this
        // test will fail and we'll review intentionally.
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "x", topicNames: ["Work"], recycled: true)
        #expect(service.recycledCountForTopic("work") == 0)
        #expect(service.recycledCountForTopic("Work") == 1)
    }

    // MARK: - loadRecycledEntries()

    @Test func loadRecycledEntries_emptyStore_returnsEmpty() {
        let (_, service) = makeService()
        #expect(service.loadRecycledEntries().isEmpty)
    }

    @Test func loadRecycledEntries_excludesLive() throws {
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "live")
        try seedEntry(in: storage, content: "recycled", recycled: true)
        let results = service.loadRecycledEntries()
        #expect(results.count == 1)
    }

    @Test func loadRecycledEntries_sortsByRecycledAtDescending() throws {
        let (storage, service) = makeService()
        let now = Date()
        // Oldest first into the store; the result must reverse this
        // because `recycledAt` ascending: false.
        try seedEntry(
            in: storage,
            content: "older",
            recycled: true,
            recycledAt: now.addingTimeInterval(-3600)
        )
        try seedEntry(
            in: storage,
            content: "newer",
            recycled: true,
            recycledAt: now
        )
        let results = service.loadRecycledEntries()
        #expect(results.count == 2)
        // First result is the most-recently-recycled.
        #expect(results.first?.content == "newer")
        #expect(results.last?.content == "older")
    }

    @Test func loadRecycledEntries_countMatchesRecycledCount() throws {
        // Internal consistency: the count and the materialized list
        // must agree. Catches a regression where the cheap counter
        // drifts from the list query (different predicates).
        let (storage, service) = makeService()
        try seedEntry(in: storage, content: "a", recycled: true)
        try seedEntry(in: storage, content: "b", recycled: true)
        try seedEntry(in: storage, content: "c", recycled: true)
        try seedEntry(in: storage, content: "live", recycled: false)

        #expect(service.recycledCount() == service.loadRecycledEntries().count)
        #expect(service.recycledCount() == 3)
    }
}
