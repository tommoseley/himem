import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the reorganize-payload-freshness bug (2026-07-24): reorganize
/// read the cached `entry.content` instead of rebuilding `joinedContent` from
/// the memory's live clips, so a clip added after the last cache write (e.g. a
/// voice clip whose transcript landed late) was invisible to the model — the
/// summary only echoed the original quote and ignored the added "dad" context.
@MainActor  // B24: `viewContext` is NSMainQueueConcurrencyType; without this the
            // suite body runs on the Swift cooperative pool and `save()` aborts the host.
@Suite(.serialized)
struct ReorganizePayloadFreshnessTests {

    /// Captures the `content` handed to the organizer so we can assert the
    /// reorganize payload reflects the CURRENT clips, not a stale snapshot.
    private final class ContentCapturingOrganizer: Organizer, @unchecked Sendable {
        var capturedContent: String = ""
        func organize(content: String, existingTopics: [String], existingMentions: [String]) async throws -> ClaudeAPIService.AnalysisResult {
            capturedContent = content
            // Grounded, gate-clean result so no retry/extractive-fallback fires.
            return ClaudeAPIService.AnalysisResult(entities: [], topics: [], summary: "A quiet moment.", title: "Reflection")
        }
    }

    private final class StubExtractor: EntityExtractor, @unchecked Sendable {
        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(entities: [])
        }
    }

    @MainActor
    @Test func reorganize_rebuildsPayloadFromLiveClips_notStaleCachedContent() async throws {
        let storage = StorageService(inMemory: true)
        let organizer = ContentCapturingOrganizer()
        // Route to the ON-DEVICE path deterministically: Free + AI-available →
        // shouldTryAnthropic is false regardless of connectivity, so the cloud
        // path (and its network flakiness) never runs.
        let engine = ProcessingEngine(
            storage: storage,
            onDeviceOrganizer: organizer,
            localExtractor: StubExtractor(),
            useOnDevice: true,
            hasAvailableAI: { true },
            isPlus: { false }
        )

        // A memory with two voice clips: the original quote, and a later-added
        // clip carrying the emotional throughline.
        let entry = try storage.createEntry(content: "", inputType: .typed)
        _ = try storage.createVoiceFragment(for: entry, audioFilename: "quote.m4a",
            transcript: "I am not bound to win, but I am bound to be true.")
        _ = try storage.createVoiceFragment(for: entry, audioFilename: "dad.m4a",
            transcript: "This is my dad, who is not a Lincoln fan. It makes me cry.")

        // Simulate the stale cache: `entry.content` lags the live clips — it
        // holds only the original quote, exactly as a late transcript leaves it.
        entry.content = "I am not bound to win, but I am bound to be true."
        try storage.viewContext.save()

        await engine.processReorganize(entry)

        // The reorganize payload MUST reflect the current clips (live
        // joinedContent), so the added clip's words are present.
        #expect(organizer.capturedContent.contains("dad"))
        #expect(organizer.capturedContent.contains("makes me cry"))
    }
}
