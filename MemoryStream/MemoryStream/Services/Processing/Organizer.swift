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
    ///     library. Both backends inject these into the prompt and
    ///     direct the model to prefer one of them over coining a new
    ///     name — the "palette discipline" rule from AI Organize
    ///     spec §2c. Returned topics get a post-pass set-diff via
    ///     `TopicPalette.partition(returned:existing:)` so the
    ///     review UI can flag genuinely-new ones AI-blue dashed.
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
