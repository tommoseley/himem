import Foundation

/// Server-backed `Organizer` — wraps `ClaudeAPIService.analyzeEntry`
/// (via the existing `EntryAnalyzer` protocol) so the cloud path
/// matches the `Organizer` shape.
///
/// Introduced in PR 8a so `ProcessingEngine` can route between
/// on-device and server using one common interface. Until the assist-
/// quota retirement (PR 8e), `ProcessingEngine`'s default path still
/// calls the analyzer directly with its assist-debit handling — this
/// type is only used when the on-device debug flag is on but
/// Foundation Models is unavailable, providing a parallel-shape
/// fallback that exercises the routing.
///
/// Reads `tier` at call time so the server's COGS log
/// (`docs/api/himem-cost-logging.md`) attributes spend to the
/// tier that authorized the assist.
struct ServerOrganizer: Organizer {
    let analyzer: EntryAnalyzer
    let readTier: @MainActor () -> String

    init(
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        readTier: @escaping @MainActor () -> String = { EntitlementService.shared.tier.rawValue }
    ) {
        self.analyzer = analyzer
        self.readTier = readTier
    }

    func organize(
        content: String,
        existingTopics: [String],
        existingMentions: [String]
    ) async throws -> ClaudeAPIService.AnalysisResult {
        let tier = await MainActor.run { readTier() }
        return try await analyzer.analyzeEntry(
            content,
            existingTopics: existingTopics,
            existingMentions: existingMentions,
            tier: tier,
            action: "memory_organize"
        )
    }
}
