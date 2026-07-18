import Testing
import Foundation
@testable import HiMem

/// Tests for `EntryDisplayModel.displayStatus` — the small pill that shows
/// "Parsing now", "Processed", "Confirmed", etc. on each card. Specifically
/// checks the inference-summary suppression rule: when an inference is
/// already showing, the pill should be silent regardless of what the
/// underlying ProcessingTask.status says.
struct EntryDisplayStatusTests {

    private func makeEntry(
        inputType: JournalEntry.InputType = .voiceInApp,
        processingStatus: ProcessingTask.Status? = nil,
        inferenceSummary: String? = nil,
        feedbackState: InferenceSummary.FeedbackState? = nil
    ) -> EntryDisplayModel {
        EntryDisplayModel(
            id: UUID(),
            displayTitle: "Test",
            content: "content",
            inputType: inputType,
            createdAt: Date(),
            processingStatus: processingStatus,
            progressDescription: nil,
            tags: [],
            topicNames: [],
            inferenceSummary: inferenceSummary,
            feedbackState: feedbackState,
            userCorrection: nil,
            mediaItems: [],
            recycledAt: nil,
            latitude: nil,
            longitude: nil,
            locationName: nil,
            renderedSummary: nil,
            projectMemberships: [],
            mentions: []
        )
    }

    @Test func processing_withoutInference_showsParsingNow() {
        let entry = makeEntry(processingStatus: .processing, inferenceSummary: nil)
        #expect(entry.displayStatus?.text == "Parsing now")
    }

    @Test func processing_withInferenceSet_pillSuppressed() {
        // The bug: a stale .processing task + a successfully landed
        // inferenceSummary should NOT show the "Parsing now" pill — the
        // inference card itself is the user-facing signal.
        let entry = makeEntry(processingStatus: .processing, inferenceSummary: "An inference summary text")
        #expect(entry.displayStatus == nil)
    }

    @Test func completed_withInferenceSet_pillSuppressed() {
        let entry = makeEntry(processingStatus: .completed, inferenceSummary: "Some inference")
        #expect(entry.displayStatus == nil)
    }

    @Test func completed_withoutInference_showsProcessed() {
        let entry = makeEntry(processingStatus: .completed, inferenceSummary: nil)
        #expect(entry.displayStatus?.text == "Processed")
    }

    @Test func feedbackConfirmed_overridesProcessing() {
        let entry = makeEntry(
            processingStatus: .processing,
            inferenceSummary: "x",
            feedbackState: .confirmed
        )
        // feedbackState branch takes precedence over the suppression branch.
        #expect(entry.displayStatus != nil)
    }
}
