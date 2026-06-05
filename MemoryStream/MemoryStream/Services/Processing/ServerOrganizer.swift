import Foundation

/// Server-backed `Organizer` — wraps `ClaudeAPIService.analyzeEntry`
/// via the existing `EntryAnalyzer` protocol so the cloud path
/// matches the `Organizer` shape. After the assist-quota retirement,
/// this type fronts the cloud fallback used when `OnDeviceOrganizer`
/// is unavailable (older devices, Apple Intelligence disabled). Plus
/// users get the frontier polish via Job 4's `FrontierOrganizer`.
///
/// Reads `tier` at call time so the server's COGS log
/// (`docs/api/himem-cost-logging.md`) attributes spend to the
/// tier that authorized the call.
struct ServerOrganizer: Organizer {
    let analyzer: EntryAnalyzer
    let readTier: @MainActor () -> String

    init(
        analyzer: EntryAnalyzer = ClaudeAPIService.shared,
        readTier: @escaping @MainActor () -> String = { Entitlement.shared.tierLabel }
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
