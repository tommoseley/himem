import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for 2026-05-18 Problem 1 (server-prompt half): the existing
/// mentions get sent up to the analyzer so the model refines them instead of
/// inventing new paraphrases. The server prompt
/// (`docs/design/mentions-server-prompt.md`) handles the reuse-vs-paraphrase
/// decision.
///
/// **Updated 2026-07-26 for B4 Phase 2 (library-backed mentions).** The gather
/// is now **library-wide** — `readExistingOrganizeContext` reads the `Mention`
/// entity (all mentions, populated by organize via `findOrCreateMention`), not
/// the old entry-scoped `ExtractedEntity` set, so a recurring person/place is
/// reused across memories instead of re-paraphrased. These tests previously
/// seeded `ExtractedEntity` (invisible to the new gather) and so read red on
/// `main`; they now seed `Mention`, matching the shipped code. Not a code bug —
/// a stale test caught up to the current design.
@MainActor
@Suite(.serialized)
struct ExistingMentionsRefinementTests {

    /// Records the `existingMentions` arg passed to `analyzeEntry`,
    /// so the test can assert the engine actually forwarded the
    /// entity values on the entry. Returns a benign success result —
    /// the assertion is on the input, not the output.
    private final class RecordingAnalyzer: EntryAnalyzer, @unchecked Sendable {
        var capturedExistingMentions: [String] = []
        var capturedExistingTopics: [String] = []
        var capturedTier: String = ""
        var capturedAction: String = ""
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult {
            capturedExistingTopics = existingTopics
            capturedExistingMentions = existingMentions
            capturedTier = tier
            capturedAction = action
            return ClaudeAPIService.AnalysisResult(
                entities: [],
                topics: [],
                summary: "",
                title: nil
            )
        }
    }

    @Test func processEntry_forwardsLibraryMentionsToAnalyzer() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: analyzer, useOnDevice: false
        )
        let entry = try storage.createEntry(content: "We discussed sausage with Bob.", inputType: .typed)
        // Library-backed mentions (what a prior organize would have created via
        // findOrCreateMention). `Mention.MentionType` is person/place/idea.
        _ = try storage.findOrCreateMention(name: "Bob", type: .person)
        _ = try storage.findOrCreateMention(name: "John", type: .person)
        _ = try storage.findOrCreateMention(name: "Sausage making process", type: .idea)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        let sent = Set(analyzer.capturedExistingMentions)
        #expect(sent == ["Bob", "John", "Sausage making process"],
                "the library's mentions are forwarded to the analyzer for reuse")
    }

    @Test func processEntry_emptyMentionLibrary_forwardsEmpty() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: analyzer, useOnDevice: false
        )
        let entry = try storage.createEntry(content: "Garden notes", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        #expect(analyzer.capturedExistingMentions.isEmpty,
                "no mentions in the library → nothing to refine against")
    }

    /// Case/whitespace variants of the same name collapse to one library
    /// `Mention` (findOrCreateMention normalizes + dedups on
    /// `normalizedName`), so the analyzer payload carries no duplicate noise.
    @Test func processEntry_libraryMentions_dedupedByNormalization() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: analyzer, useOnDevice: false
        )
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        _ = try storage.findOrCreateMention(name: "Bob", type: .person)
        _ = try storage.findOrCreateMention(name: "bob", type: .person)
        _ = try storage.findOrCreateMention(name: "  Bob  ", type: .person)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        #expect(analyzer.capturedExistingMentions.count == 1)
    }
}
