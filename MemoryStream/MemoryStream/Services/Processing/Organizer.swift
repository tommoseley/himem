import Foundation

/// One AI-organize pass against an entry's content. Implementations
/// differ in backend (on-device Foundation Models vs. server-side
/// frontier model) but produce the same shape so `ProcessingEngine`
/// can route between them without changing the storage code.
///
/// Returns `ClaudeAPIService.AnalysisResult` for now to avoid churn
/// in the storage layer (`storeEntities`, `storeInference`,
/// `storeOrganizePass`). Renaming the result type to a backend-
/// neutral `OrganizeResult` is a follow-up after the assist-quota
/// retirement (PR 8e).
///
/// Introduced in PR 8a behind a debug flag —
/// `himem.organize.useOnDevice` UserDefaults bool. Production keeps
/// the existing `EntryAnalyzer`-driven cloud path until the
/// flag flip in PR 8e.
protocol Organizer {
    /// - Parameters:
    ///   - content: raw entry text. The on-device implementation
    ///     wraps this in a per-memory prompt; the server path passes
    ///     it through to `/himem/analyze`.
    ///   - existingTopics: topic names already present in the user's
    ///     library. The server uses these to prefer existing names
    ///     over inventing new ones; on-device receives them but the
    ///     iter-5 prompt doesn't reference them yet (no measurable
    ///     improvement in the spike).
    ///   - existingMentions: case-folded-deduped entity values
    ///     already attached to this entry. Empty on first organize;
    ///     populated on re-organize so the model refines instead of
    ///     paraphrasing.
    func organize(
        content: String,
        existingTopics: [String],
        existingMentions: [String]
    ) async throws -> ClaudeAPIService.AnalysisResult
}
