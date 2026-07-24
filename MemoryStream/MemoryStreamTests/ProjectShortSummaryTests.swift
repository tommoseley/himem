import Testing
import Foundation
@testable import HiMem

/// Money tests for the project **short** summary (2026-07-23): it is derived by
/// compressing the LONG summary on-device, gated against the long by
/// TruthReconciler, with a deterministic extractive fallback. These stub the
/// on-device compressor to drive the gate/fallback branches without a device.
@Suite
struct ProjectShortSummaryTests {

    @MainActor
    private func vm(compress: @escaping @MainActor (String) async -> String?) -> ProjectAssistViewModel {
        ProjectAssistViewModel(compressLongSummary: compress)
    }

    /// A compressed one-liner fully grounded in the long summary passes the
    /// gate and is used verbatim.
    @MainActor
    @Test func groundedShort_isReturnedVerbatim() async {
        let long = "You're exploring cooking and sausage making across several memories."
        let model = vm { _ in "You're exploring cooking and sausage making." }
        let short = await model.deriveShortSummary(fromLong: long)
        #expect(short == "You're exploring cooking and sausage making.")
    }

    /// The whole honesty point: a short that introduces a name the long never
    /// states is a fabrication → gate strips it → both attempts fail → falls
    /// back to the extractive lead sentence of the long (which cannot contain
    /// the invented name).
    @MainActor
    @Test func fabricatedShort_fallsBackToExtractive() async {
        let long = "You explored cooking and sausage making. Bar Oliver taught you charcuterie."
        let model = vm { _ in "You and Ferdinand explored cooking together." }
        let short = await model.deriveShortSummary(fromLong: long)
        #expect(!short.lowercased().contains("ferdinand"))
        #expect(short.lowercased().contains("cooking"))
    }

    /// Foundation Models unavailable (older device) → compressor returns nil →
    /// deterministic extractive one-liner from the long. Never re-reads the
    /// memories; drawn from the long's own text.
    @MainActor
    @Test func modelUnavailable_fallsBackToExtractive() async {
        let long = "You explored cooking and sausage making across the week."
        let model = vm { _ in nil }
        let short = await model.deriveShortSummary(fromLong: long)
        #expect(short == "You explored cooking and sausage making across the week")
    }

    @MainActor
    @Test func emptyLong_yieldsEmptyShort() async {
        let model = vm { _ in "anything" }
        #expect(await model.deriveShortSummary(fromLong: "   ").isEmpty)
    }

    // MARK: - Card subtitle fallback (short → goal → nothing)

    private func model(purpose: String?, short: String?) -> ProjectDisplayModel {
        ProjectDisplayModel(
            id: UUID(), name: "P", purpose: purpose, shortSummary: short,
            memoryCount: 1, topicNames: [], updatedAt: Date(timeIntervalSince1970: 0), previewText: nil
        )
    }

    @Test func cardSubtitle_prefersShortOverGoal() {
        #expect(model(purpose: "my goal", short: "the short").cardSubtitle == "the short")
    }

    @Test func cardSubtitle_fallsBackToGoal_whenNoThread() {
        #expect(model(purpose: "my goal", short: nil).cardSubtitle == "my goal")
        #expect(model(purpose: "my goal", short: "   ").cardSubtitle == "my goal")
    }

    @Test func cardSubtitle_nil_whenNeither() {
        #expect(model(purpose: nil, short: nil).cardSubtitle == nil)
    }
}
