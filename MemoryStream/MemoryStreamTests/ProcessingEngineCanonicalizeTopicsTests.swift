import Testing
import Foundation
@testable import HiMem

/// Money tests for `ProcessingEngine.canonicalizeTopics(result:against:)`
/// — the integration seam that applies AI Organize spec §2c's
/// "palette discipline" rule to a fresh `AnalysisResult` from the
/// organizer.
///
/// The contract: returned topics matching an existing palette entry
/// (case-insensitive, whitespace-trimmed) are rewritten to the
/// palette's canonical form. Non-matches pass through unchanged.
/// Non-topic fields (entities, summary, title, nextSteps) are
/// preserved bit-for-bit — canonicalization MUST NOT touch any other
/// field.
///
/// Why this seam is worth a test on its own (TopicPalette has its own
/// suite): a copy-construction bug here would silently drop a field
/// — entities forgotten on rewrite, title swapped to nil, etc. —
/// the kind of regression that compiles fine and passes most tests.
@Suite
struct ProcessingEngineCanonicalizeTopicsTests {

    private func sampleResult(topics: [String]) -> ClaudeAPIService.AnalysisResult {
        ClaudeAPIService.AnalysisResult(
            entities: [.init(type: "person", value: "Sarah", confidence: 0.9)],
            topics: topics,
            summary: "a sample summary",
            title: "A Sample Title",
            nextSteps: ["call Sarah"]
        )
    }

    @Test func returnedTopicsMatchPaletteByCase_rewrittenToPaletteForm() {
        let input = sampleResult(topics: ["garden", "WORK"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden", "Work"])
        #expect(canonical.topics == ["Garden", "Work"])
    }

    @Test func returnedTopicsWithNoPaletteMatch_passThroughUnchanged() {
        let input = sampleResult(topics: ["Pottery", "Bonsai"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden"])
        #expect(canonical.topics == ["Pottery", "Bonsai"])
    }

    @Test func mixedMatches_canonicalFirstThenNew() {
        let input = sampleResult(topics: ["Garden", "Pottery"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden", "Work"])
        // Per `TopicPalette.Partition` shape: matches come first,
        // genuine novelties follow. Caller (storage) doesn't care
        // about order; this test pins the contract.
        #expect(canonical.topics == ["Garden", "Pottery"])
    }

    @Test func canonicalizationPreservesEntities() {
        let input = sampleResult(topics: ["garden"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden"])
        #expect(canonical.entities.count == input.entities.count)
        #expect(canonical.entities.first?.value == "Sarah")
    }

    @Test func canonicalizationPreservesSummaryAndTitle() {
        let input = sampleResult(topics: ["garden"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden"])
        #expect(canonical.summary == "a sample summary")
        #expect(canonical.title == "A Sample Title")
    }

    @Test func canonicalizationPreservesNextSteps() {
        let input = sampleResult(topics: ["garden"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden"])
        #expect(canonical.nextSteps == ["call Sarah"])
    }

    @Test func emptyPalette_topicsPassThrough() {
        let input = sampleResult(topics: ["Garden", "Work"])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: [])
        #expect(canonical.topics == ["Garden", "Work"])
    }

    @Test func emptyTopics_emptyResult() {
        let input = sampleResult(topics: [])
        let canonical = ProcessingEngine.canonicalizeTopics(result: input, against: ["Garden"])
        #expect(canonical.topics == [])
    }
}
