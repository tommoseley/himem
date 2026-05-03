import Testing
import Foundation
@testable import MemoryStream

/// Tests for ProjectDetailView.composeProjectText — the share-sheet output
/// the user sees when sharing a project. Pure formatter; no Core Data or
/// SwiftUI dependencies.
struct ProjectDetailViewTextTests {

    private func entry(title: String, content: String, locality: String? = nil) -> EntryDisplayModel {
        EntryDisplayModel(
            id: UUID(),
            displayTitle: title,
            content: content,
            inputType: .typed,
            createdAt: Date(),
            processingStatus: nil,
            progressDescription: nil,
            tags: [],
            topicNames: [],
            audioFilePath: nil,
            inferenceSummary: nil,
            feedbackState: nil,
            userCorrection: nil,
            mediaItems: [],
            recycledAt: nil,
            latitude: nil,
            longitude: nil,
            locationName: locality
        )
    }

    @Test func composeProjectText_namePurposeAndOneEntry() {
        let result = ProjectDetailView.composeProjectText(
            name: "Garden Plans",
            purpose: "Bed-by-bed planting log for 2026",
            entries: [entry(title: "Bed 3", content: "Tomatoes and basil.")]
        )
        #expect(result == """
        GARDEN PLANS
        Bed-by-bed planting log for 2026

        ---

        Bed 3
        Tomatoes and basil.

        """)
    }

    @Test func composeProjectText_noPurpose_skipsLine() {
        let result = ProjectDetailView.composeProjectText(
            name: "Quick Project",
            purpose: nil,
            entries: [entry(title: "First", content: "Hello.")]
        )
        // No purpose line; blank line after the name still present.
        #expect(result.hasPrefix("QUICK PROJECT\n\n---"))
    }

    @Test func composeProjectText_emptyPurpose_skipsLine() {
        let result = ProjectDetailView.composeProjectText(
            name: "Quick Project",
            purpose: "",
            entries: []
        )
        // Header (uppercased name) + the trailing blank-line separator.
        #expect(result == "QUICK PROJECT\n")
    }

    @Test func composeProjectText_noName_omitsHeader() {
        let result = ProjectDetailView.composeProjectText(
            name: nil,
            purpose: nil,
            entries: [entry(title: "Solo entry", content: "A note.")]
        )
        #expect(result == """
        ---

        Solo entry
        A note.

        """)
    }

    @Test func composeProjectText_multipleEntries_separatedByThreeDashes() {
        let result = ProjectDetailView.composeProjectText(
            name: "Logs",
            purpose: nil,
            entries: [
                entry(title: "First", content: "One."),
                entry(title: "Second", content: "Two."),
                entry(title: "Third", content: "Three.")
            ]
        )
        // Three "---" separators, one before each entry.
        #expect(result.components(separatedBy: "---").count == 4)
    }

    @Test func composeProjectText_uppercasesName() {
        let result = ProjectDetailView.composeProjectText(
            name: "lowercase project",
            purpose: nil,
            entries: []
        )
        #expect(result.hasPrefix("LOWERCASE PROJECT\n"))
    }

    @Test func composeProjectText_emptyAll_returnsEmpty() {
        let result = ProjectDetailView.composeProjectText(name: nil, purpose: nil, entries: [])
        #expect(result == "")
    }
}
