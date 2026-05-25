import Testing
import Foundation
import CoreData
@testable import HiMem

@MainActor
struct SearchEngineTests {

    private func makeContext() -> (StorageService, NSManagedObjectContext, SearchEngine) {
        let storage = StorageService(inMemory: true)
        let engine = SearchEngine(storage: storage)
        return (storage, storage.viewContext, engine)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return cal.date(from: comps)!
    }

    @discardableResult
    private func makeEntry(
        in storage: StorageService,
        content: String,
        inputType: JournalEntry.InputType = .typed,
        createdAt: Date = Date(),
        title: String? = nil,
        topics: [String] = [],
        media: [(id: String, type: MediaReference.MediaType)] = [],
        lastViewedAt: Date? = nil
    ) -> JournalEntry {
        let entry = try! storage.createEntry(content: content, inputType: inputType, title: title)
        entry.createdAt = createdAt
        entry.lastViewedAt = lastViewedAt
        for name in topics {
            let topic = try! storage.findOrCreateTopic(name: name)
            entry.addToTopics(topic)
        }
        for m in media {
            _ = try! storage.createMediaReference(for: entry, localIdentifier: m.id, mediaType: m.type)
        }
        try! storage.viewContext.save()
        return entry
    }

    // MARK: - Filters

    @Test func search_textOnly_matchesContent() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "tomato seedlings doing well")
        makeEntry(in: storage, content: "kale ready to harvest")

        let hits = try engine.search(parsed: ScopeParser.parse("tomato"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content.contains("tomato") == true)
    }

    @Test func search_topicScope_filtersByTopic() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "garden bed three", topics: ["Garden"])
        makeEntry(in: storage, content: "book club notes", topics: ["Reading"])

        let hits = try engine.search(parsed: ScopeParser.parse("topic:garden"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.topicsArray.first?.slug == "garden")
    }

    @Test func search_typePhoto_matchesEntriesWithImageMedia() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "sunset", media: [("p1", .image)])
        makeEntry(in: storage, content: "voice memo", media: [("v1", .voice)])
        makeEntry(in: storage, content: "just text")

        let hits = try engine.search(parsed: ScopeParser.parse("type:photo"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content == "sunset")
    }

    @Test func search_typeVideo_matchesEntriesWithVideoMedia() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "trail clip", media: [("v1", .video)])
        makeEntry(in: storage, content: "photo only", media: [("p1", .image)])

        let hits = try engine.search(parsed: ScopeParser.parse("type:video"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content == "trail clip")
    }

    @Test func search_typeVoice_matchesVoiceInputAndVoiceMedia() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "siri capture", inputType: .siri)
        makeEntry(in: storage, content: "in-app voice", inputType: .voiceInApp)
        makeEntry(in: storage, content: "typed with voice clip", inputType: .typed, media: [("v1", .voice)])
        makeEntry(in: storage, content: "plain typed", inputType: .typed)

        let hits = try engine.search(parsed: ScopeParser.parse("type:voice"), context: ctx)
        let contents = Set(hits.map { $0.entry.content })
        #expect(contents == ["siri capture", "in-app voice", "typed with voice clip"])
    }

    @Test func search_typeText_excludesEntriesWithMedia() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "pure text note", inputType: .typed)
        makeEntry(in: storage, content: "typed with photo", inputType: .typed, media: [("p1", .image)])
        makeEntry(in: storage, content: "siri capture", inputType: .siri)

        let hits = try engine.search(parsed: ScopeParser.parse("type:text"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content == "pure text note")
    }

    @Test func search_dateRange_filtersByCreatedAt() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "old", createdAt: date(2024, 3, 15))
        makeEntry(in: storage, content: "recent", createdAt: date(2026, 4, 20))

        let parsed = ScopeParser.parse("date:2026")
        let hits = try engine.search(parsed: parsed, context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content == "recent")
    }

    @Test func search_composesTopicTypeAndDate() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "garden voice 2024", inputType: .voiceInApp,
                  createdAt: date(2024, 5, 1), topics: ["Garden"])
        makeEntry(in: storage, content: "garden voice 2026", inputType: .voiceInApp,
                  createdAt: date(2026, 5, 1), topics: ["Garden"])
        makeEntry(in: storage, content: "garden text 2026", inputType: .typed,
                  createdAt: date(2026, 5, 1), topics: ["Garden"])

        let hits = try engine.search(parsed: ScopeParser.parse("topic:garden type:voice date:2026"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.content == "garden voice 2026")
    }

    @Test func search_excludesRecycledEntries() throws {
        let (storage, ctx, engine) = makeContext()
        let kept = makeEntry(in: storage, content: "tomato keeper")
        let trashed = makeEntry(in: storage, content: "tomato trash")
        trashed.isRecycled = true
        try ctx.save()

        let hits = try engine.search(parsed: ScopeParser.parse("tomato"), context: ctx)
        #expect(hits.count == 1)
        #expect(hits.first?.entry.id == kept.id)
    }

    /// Money test for "pill says 3 but search shows 2." Reproduction:
    /// a topic has 3 entries (2 active, 1 in Recently Deleted). The pill
    /// counts all 3 (Topic.entryCount includes recycled). Active search
    /// shows 2. Without searchRecycled, the 3rd entry is unreachable from
    /// the search field.
    @Test func searchRecycled_returnsOnlyRecycledMatches() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "active note", topics: ["Garden"])
        let trashed = makeEntry(in: storage, content: "deleted note", topics: ["Garden"])
        trashed.isRecycled = true
        try ctx.save()

        let parsed = ScopeParser.parse("topic:garden")
        let active = try engine.search(parsed: parsed, context: ctx)
        let recycled = try engine.searchRecycled(parsed: parsed, context: ctx)

        #expect(active.count == 1)
        #expect(active.first?.entry.content == "active note")
        #expect(recycled.count == 1)
        #expect(recycled.first?.entry.id == trashed.id)
    }

    /// Money test for the topic-pill expander bug. Tapping a topic pill in
    /// pre-search calls toggleTopicScope, which sets queryText programmatically
    /// and runs executeSearch (committed=true → state=.results). SwiftUI's
    /// TextField binding then echoes the new value back through its set
    /// callback (onQueryChanged), which used to reset committed=false and
    /// flip state to .typing — hiding the Recently Deleted expander.
    @Test func toggleTopicScope_keepsResultsState_afterBindingEcho() async throws {
        let storage = StorageService(inMemory: true)
        let engine = SearchEngine(storage: storage)
        makeEntry(in: storage, content: "active 1", topics: ["Garden"])
        makeEntry(in: storage, content: "active 2", topics: ["Garden"])
        let trashed = makeEntry(in: storage, content: "trashed", topics: ["Garden"])
        trashed.isRecycled = true
        try storage.viewContext.save()

        let vm = await SearchViewModel(engine: engine, storage: storage)
        await vm.toggleTopicScope("garden")
        await #expect(vm.state == .results)
        await #expect(vm.recycledHits.count == 1)

        // Simulate SwiftUI's TextField binding echoing queryText through
        // the set callback after a programmatic change.
        let echo = await vm.queryText
        await vm.onQueryChanged(echo)

        await #expect(vm.state == .results)
        await #expect(vm.recycledHits.count == 1)
    }

    @Test func searchRecycled_respectsTextAndTypeScope() throws {
        let (storage, ctx, engine) = makeContext()
        let trashedVoice = makeEntry(in: storage, content: "tomato voice", inputType: .voiceInApp)
        trashedVoice.isRecycled = true
        let trashedText = makeEntry(in: storage, content: "tomato text", inputType: .typed)
        trashedText.isRecycled = true
        try ctx.save()

        let parsed = ScopeParser.parse("type:voice tomato")
        let recycled = try engine.searchRecycled(parsed: parsed, context: ctx)
        #expect(recycled.count == 1)
        #expect(recycled.first?.entry.id == trashedVoice.id)
    }

    // MARK: - Snippet

    @Test func search_returnsSnippet_aroundMatch() throws {
        let (storage, ctx, engine) = makeContext()
        let long = String(repeating: "a ", count: 100) + "tomato " + String(repeating: "b ", count: 100)
        makeEntry(in: storage, content: long)

        let hits = try engine.search(parsed: ScopeParser.parse("tomato"), context: ctx)
        let snippet = try #require(hits.first?.snippet)
        #expect(snippet.matchTerm == "tomato")
        #expect(snippet.text.contains("tomato"))
        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.hasSuffix("…"))
        #expect(snippet.text.count < long.count)
    }

    @Test func search_snippetIsNil_whenNoTextTerm() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "garden notes", topics: ["Garden"])

        let hits = try engine.search(parsed: ScopeParser.parse("topic:garden"), context: ctx)
        #expect(hits.first?.snippet == nil)
    }

    // MARK: - Facet counts

    @Test func topicFacetCounts_ignoreActiveTopicScope() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "tomato in garden", topics: ["Garden"])
        makeEntry(in: storage, content: "tomato in cooking", topics: ["Cooking"])
        makeEntry(in: storage, content: "kale in garden", topics: ["Garden"])

        let parsed = ScopeParser.parse("topic:garden tomato")
        let counts = try engine.topicFacetCounts(for: parsed, context: ctx)
        // Counts should reflect "tomato" matches across topics, not narrowed to garden.
        #expect(counts["garden"] == 1)
        #expect(counts["cooking"] == 1)
    }

    @Test func typeFacetCounts_ignoreActiveTypeScope() throws {
        let (storage, ctx, engine) = makeContext()
        makeEntry(in: storage, content: "tomato photo", media: [("p1", .image)])
        makeEntry(in: storage, content: "tomato voice", inputType: .voiceInApp)
        makeEntry(in: storage, content: "tomato text", inputType: .typed)

        let parsed = ScopeParser.parse("type:photo tomato")
        let counts = try engine.typeFacetCounts(for: parsed, context: ctx)
        #expect(counts[.photo] == 1)
        #expect(counts[.voice] == 1)
        #expect(counts[.text] == 1)
    }

    // MARK: - Forgotten card

    @Test func forgottenCard_returnsOldUnviewedEntry() throws {
        let (storage, ctx, engine) = makeContext()
        let now = date(2026, 5, 1)
        let old = makeEntry(in: storage, content: "memory from a year ago", createdAt: date(2025, 4, 1))
        makeEntry(in: storage, content: "fresh memory", createdAt: date(2026, 4, 25)) // too recent

        let card = try engine.forgottenCard(now: now, calendar: .current, picker: { $0.first }, context: ctx)
        #expect(card?.id == old.id)
    }

    @Test func forgottenCard_excludesRecentlyViewed() throws {
        let (storage, ctx, engine) = makeContext()
        let now = date(2026, 5, 1)
        // Old entry but viewed last week — should be excluded.
        makeEntry(
            in: storage,
            content: "old but viewed",
            createdAt: date(2025, 1, 1),
            lastViewedAt: date(2026, 4, 25)
        )
        let card = try engine.forgottenCard(now: now, calendar: .current, picker: { $0.first }, context: ctx)
        #expect(card == nil)
    }

    @Test func forgottenCard_includesOldAndStaleViewed() throws {
        let (storage, ctx, engine) = makeContext()
        let now = date(2026, 5, 1)
        // Old entry, last viewed 5 months ago — qualifies (viewed > 3 months ago).
        let qualifying = makeEntry(
            in: storage,
            content: "stale view",
            createdAt: date(2025, 1, 1),
            lastViewedAt: date(2025, 12, 1)
        )
        let card = try engine.forgottenCard(now: now, calendar: .current, picker: { $0.first }, context: ctx)
        #expect(card?.id == qualifying.id)
    }

    @Test func forgottenCard_returnsNil_whenNoCandidates() throws {
        let (_, ctx, engine) = makeContext()
        let card = try engine.forgottenCard(now: Date(), context: ctx)
        #expect(card == nil)
    }
}
