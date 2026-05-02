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
            analyzer: ThrowingAnalyzer()
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
