import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for 2026-05-18 Problem 1 (server-prompt half): on a
/// re-organize pass, the existing mentions attached to the entry get
/// sent up to the analyzer so the model refines them instead of
/// inventing new paraphrases. Client packaging is half the work; the
/// server prompt (`docs/design/mentions-server-prompt.md`) handles
/// the reuse-vs-paraphrase decision.
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
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            capturedExistingTopics = existingTopics
            capturedExistingMentions = existingMentions
            return ClaudeAPIService.AnalysisResult(
                entities: [],
                topics: [],
                summary: "",
                title: nil,
                nextSteps: nil
            )
        }
    }

    @Test func processEntry_sendsExistingMentionValuesToAnalyzer() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(storage: storage, analyzer: analyzer)
        let entry = try storage.createEntry(content: "We discussed sausage with Bob.", inputType: .typed)
        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Bob", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "John", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .project, value: "Sausage making process", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        let sent = Set(analyzer.capturedExistingMentions)
        #expect(sent == ["Bob", "John", "Sausage making process"])
    }

    @Test func processEntry_firstOrganize_sendsEmptyExistingMentions() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(storage: storage, analyzer: analyzer)
        let entry = try storage.createEntry(content: "Garden notes", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        #expect(analyzer.capturedExistingMentions.isEmpty)
    }

    /// Same case-folded value attached multiple times (different
    /// types pre-fix, or any other historical accumulation) collapses
    /// to one entry in the payload — no point shipping noise to the
    /// model.
    @Test func processEntry_existingMentions_dedupedCaseInsensitively() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = RecordingAnalyzer()
        let engine = ProcessingEngine(storage: storage, analyzer: analyzer)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Bob", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .project, value: "bob", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .idea, value: "  Bob  ", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createProcessingTask(for: entry)
        try storage.viewContext.save()

        await engine.processEntry(entry)

        #expect(analyzer.capturedExistingMentions.count == 1)
    }
}
