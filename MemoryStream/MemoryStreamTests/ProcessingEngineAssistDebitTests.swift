import Testing
import Foundation
import CoreData
@testable import HiMem

// Serialized for the same reason as `ProcessingEngineFallbackTests` —
// `LocalEntityExtractor.shared.tagger` (NLTagger) isn't thread-safe, and
// also because `ErrorState.shared` is a process-wide singleton observed
// across tests.
@MainActor
@Suite(.serialized)
struct ProcessingEngineAssistDebitTests {

    /// Stub that returns a deterministic cloud-style result so the engine
    /// reaches the assist-debit branch (only fired on successful save).
    private struct SuccessfulAnalyzer: EntryAnalyzer {
        let title: String
        let entityValue: String
        let topic: String
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            ClaudeAPIService.AnalysisResult(
                entities: [.init(type: "person", value: entityValue, confidence: 0.95)],
                topics: [topic],
                summary: "cloud summary",
                title: title,
                nextSteps: nil
            )
        }
    }

    private struct DebitFailure: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    /// Money test for the silent-debit-loss bug. Before 2026-06-01 the
    /// debit call was `try? EntitlementService.shared.tryConsumeAssist()`
    /// — a failure (Core Data error, ledger corruption, race) silently
    /// vanished. The user got the organize pass but the counter never
    /// moved. Real money state, zero observability.
    ///
    /// Contract: a `tryConsumeAssist` failure must (a) surface to
    /// `ErrorState` so the user sees something went wrong, and (b) NOT
    /// roll back the successful pass — the analyzer ran, the Core Data
    /// save committed, the entry is in a good state. The user being
    /// told to retry is the recovery, not a forced re-pass.
    @Test func consumeAssist_failure_surfacesToErrorState_andLeavesPassSucceeded() async throws {
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden", entityValue: "Sarah", topic: "Garden"),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { throw DebitFailure(detail: "ledger save returned NSCoreDataError") }
        )

        ErrorState.shared.dismiss()

        let entry = try storage.createEntry(
            content: "Met with Sarah about the garden.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)
        storage.viewContext.refreshAllObjects()

        // Pass succeeded — task is .completed, entity persisted.
        let taskRequest = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        taskRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        #expect(try storage.viewContext.fetch(taskRequest).first?.statusEnum == .completed)

        let entityRequest = NSFetchRequest<ExtractedEntity>(entityName: "ExtractedEntity")
        entityRequest.predicate = NSPredicate(format: "entryId == %@", entry.id as CVarArg)
        #expect(try storage.viewContext.fetch(entityRequest).isEmpty == false)

        // Debit failure surfaced to the user.
        guard let current = ErrorState.shared.current else {
            Issue.record("ErrorState.current is nil — debit failure was swallowed silently")
            return
        }
        // Specifically a processingFailed (the closest matching case
        // in `AppError`); the detail string carries the propagated
        // closure error.
        switch current {
        case .processingFailed(let detail):
            #expect(detail.contains("ledger save returned NSCoreDataError"))
        default:
            Issue.record("ErrorState.current was \(current); expected .processingFailed")
        }
    }

    /// On the happy path the closure is invoked exactly once per pass —
    /// not zero (silent skip), not more than once (double-debit). The
    /// existing fallback / success tests cover the cloud / local branch
    /// outputs; this locks the debit-call cardinality.
    @Test func consumeAssist_success_invokedExactlyOncePerPass() async throws {
        let callCounter = AssistCallCounter()
        let storage = StorageService(inMemory: true)
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: SuccessfulAnalyzer(title: "Garden", entityValue: "Sarah", topic: "Garden"),
            localExtractor: LocalEntityExtractor(),
            consumeAssist: { callCounter.bump() }
        )

        let entry = try storage.createEntry(
            content: "Met with Sarah about the garden.",
            inputType: .typed
        )
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)

        #expect(callCounter.count == 1)
    }

    @MainActor
    private final class AssistCallCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }
}
