import Testing
import Foundation
import CoreData
@testable import MemoryStream

// Serialized because LocalEntityExtractor.shared.tagger (NLTagger) isn't
// thread-safe. Concurrent tests crash inside the local-fallback path.
@MainActor
@Suite(.serialized)
struct ProcessingEngineFallbackTests {

    /// Stubbed analyzer that throws — simulates a 1-bar/weak-connection
    /// timeout, transient 5xx, or any other cloud failure.
    private struct ThrowingAnalyzer: EntryAnalyzer {
        struct StubError: Error {}
        func analyzeEntry(_ text: String, existingTopics: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            throw StubError()
        }
    }

    /// Stub that returns a deterministic cloud-style result.
    private struct SuccessfulAnalyzer: EntryAnalyzer {
        let title: String
        let entityValue: String
        let topic: String
        func analyzeEntry(_ text: String, existingTopics: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            ClaudeAPIService.AnalysisResult(
                entities: [.init(type: "person", value: entityValue, confidence: 0.95)],
                topics: [topic],
                summary: "cloud summary",
                title: title
            )
        }
    }

    /// Money test for the "stuck on Queued / Processing" report. When the
    /// cloud call fails (weak connection, server unreachable), the engine
    /// MUST fall back to local extraction so the entry isn't left in a
    /// half-state. Task ends `.completed`; entities exist with
    /// `processingMethod == "local"`.
    @Test func processEntry_cloudFailure_fallsBackToLocal() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: ThrowingAnalyzer(),
            localExtractor: LocalEntityExtractor()
        )

        let entry = try storage.createEntry(
            content: "Met with Sarah at Stanford about the new garden project.",
            inputType: .typed
        )
        let task = try storage.createProcessingTask(for: entry)
        #expect(task.statusEnum == .pending)

        await engine.processEntry(entry)

        // Refresh from store so we see the background-context updates.
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let refreshedTask = try storage.viewContext.fetch(request).first
        #expect(refreshedTask?.statusEnum == .completed)

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(entityRequest)
        #expect(!entities.isEmpty)
        #expect(entities.allSatisfy { $0.processingMethod == "local" })
    }

    /// Money test for the connectivity-restored re-processing path. An entry
    /// processed via the local fallback should be re-analyzed via cloud once
    /// `reprocessLocallyHandledEntries()` fires (which the app wires to a
    /// connectivity-restored transition).
    /// Happy path: cloud analyzer succeeds → entry gets entities, topics,
    /// and an inference summary; task ends .completed with method=cloud.
    @Test func processEntry_cloudSuccess_storesEverything() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden"),
            localExtractor: LocalEntityExtractor()
        )

        let entry = try storage.createEntry(
            content: "Met with Sarah about the garden.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let task = try storage.viewContext.fetch(request).first
        #expect(task?.statusEnum == .completed)

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(entityRequest)
        #expect(entities.count == 1)
        #expect(entities.first?.value == "Sarah")
        #expect(entities.first?.processingMethod == "cloud")

        let summaryRequest = NSFetchRequest<InferenceSummary>(entityName: "InferenceSummary")
        summaryRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let summary = try storage.viewContext.fetch(summaryRequest).first
        #expect(summary?.summaryText == "cloud summary")

        // Title from the analyzer flows back to the entry.
        let entryRequest = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        entryRequest.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
        let refreshed = try storage.viewContext.fetch(entryRequest).first
        #expect(refreshed?.title == "Garden meeting")
    }

    /// processPendingTasks fetches pending ProcessingTasks and runs them.
    /// Useful for entries created before the engine was ready (e.g. during
    /// the brief startup window) — they shouldn't sit pending forever.
    @Test func processPendingTasks_picksUpQueuedEntries() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Note", entityValue: "Bob", topic: "Work"),
            localExtractor: LocalEntityExtractor()
        )

        let entry = try storage.createEntry(content: "Coffee with Bob.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processPendingTasks()
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let task = try storage.viewContext.fetch(request).first
        #expect(task?.statusEnum == .completed)
    }

    /// Money test for the duplicated-mentions bug: when processEntry runs a
    /// second time on the same entry without a clearForReprocessing in
    /// between (e.g. CloudKit re-import after a Change Token Expired reset,
    /// or any other unforeseen re-trigger), the existing entities must NOT
    /// be re-created. storeEntities has to be idempotent on (entry, type, value).
    @Test func processEntry_runTwice_doesNotDuplicateEntities() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden")
        )

        let entry = try storage.createEntry(content: "Met with Sarah", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        // Sanity: first pass produced exactly one Sarah entity.
        let firstFetch = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        firstFetch.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        #expect((try storage.viewContext.fetch(firstFetch)).count == 1)

        // Re-trigger processing with no clearForReprocessing between runs.
        _ = try storage.createProcessingTask(for: entry)
        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(request)
        #expect(entities.count == 1, "storeEntities must be idempotent on (entry, type, value)")
    }

    /// Sweep test: existing duplicate ExtractedEntity rows (same entry, type,
    /// value) get collapsed to one canonical row. Mirrors mergeDuplicateTopics.
    @Test func mergeDuplicateEntities_collapsesDuplicates() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "test", inputType: .typed)

        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Sarah", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .person, value: "Sarah", confidence: 0.9, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .nextAction, value: "Plant potatoes", confidence: 0.85, method: "cloud", entry: entry)
        _ = try storage.createEntity(entryId: entry.id, type: .nextAction, value: "Plant potatoes", confidence: 0.85, method: "cloud", entry: entry)
        try storage.viewContext.save()

        try storage.mergeDuplicateEntities()

        let request = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        request.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        let entities = try storage.viewContext.fetch(request)
        #expect(entities.count == 2, "Two unique (type, value) pairs collapse to two entities")
    }

    @Test func reprocess_upgradesLocalEntriesToCloud() async throws {
        let storage = StorageService(inMemory: true)
        let offlineEngine = ProcessingEngine(storage: storage, analyzer: ThrowingAnalyzer())

        let entry = try storage.createEntry(
            content: "Met with Sarah at Stanford about the new garden project.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)

        await offlineEngine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        // Sanity: it really was processed locally.
        let preEntities = try storage.viewContext.fetch(NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity"))
        #expect(preEntities.allSatisfy { $0.processingMethod == "local" })

        // Connectivity returns: simulate the reprocessor firing on the
        // online transition.
        let onlineEngine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden meeting", entityValue: "Sarah", topic: "Garden")
        )
        await onlineEngine.reprocessLocallyHandledEntries()
        storage.viewContext.refreshAllObjects()

        let postEntities = try storage.viewContext.fetch(NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity"))
        #expect(!postEntities.isEmpty)
        #expect(postEntities.allSatisfy { $0.processingMethod == "cloud" })
        #expect(postEntities.contains { $0.value == "Sarah" })
    }
}
