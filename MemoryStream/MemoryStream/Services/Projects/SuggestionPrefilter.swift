import Foundation

/// Local prefilter for project memory suggestions. Reduces the
/// library to a bounded candidate set (default 20–30) that the AI
/// re-ranks server-side. Pure scoring — no I/O, no Core Data
/// dependencies beyond reading the inputs.
///
/// Signals (combined into a single score):
///
///   • **Topic overlap** — strong signal. Same topic = same thread.
///   • **Entity overlap** — strong signal. Same people/projects.
///   • **Phrase overlap** — light signal. Shared content tokens.
///   • **Date proximity** — light signal. Memories captured around
///     the same window as the project's existing memories.
///
/// The AI gets the top N by score and decides which to surface to
/// the user with Likely / Maybe bands + one-sentence rationale.
enum SuggestionPrefilter {
    static let defaultLimit: Int = 25

    struct CandidateInput {
        let id: UUID
        let topicNames: [String]
        let entityValues: [String]
        let content: String
        let createdAt: Date
    }

    struct ProjectContext {
        let topicNames: [String]
        let entityValues: [String]
        let memberMemoryIDs: Set<UUID>
        /// Date window the project's memories cluster around. The
        /// median createdAt is a decent shorthand; finer windowing
        /// is post-MVP.
        let centerDate: Date?
    }

    struct Scored {
        let id: UUID
        let score: Double
    }

    /// Returns the top `limit` candidates by score, descending.
    /// Excludes any memory already in the project.
    static func rank(
        candidates: [CandidateInput],
        context: ProjectContext,
        limit: Int = defaultLimit
    ) -> [Scored] {
        let projectTopics = Set(context.topicNames.map { $0.lowercased() })
        let projectEntities = Set(context.entityValues.map { $0.lowercased() })

        let scored: [Scored] = candidates.compactMap { c in
            guard !context.memberMemoryIDs.contains(c.id) else { return nil }
            var score: Double = 0
            // Topic overlap — 2.0 per match (strong).
            let topicMatches = Set(c.topicNames.map { $0.lowercased() }).intersection(projectTopics).count
            score += Double(topicMatches) * 2.0
            // Entity overlap — 1.5 per match (strong).
            let entityMatches = Set(c.entityValues.map { $0.lowercased() }).intersection(projectEntities).count
            score += Double(entityMatches) * 1.5
            // Date proximity — up to 1.0 within 7 days, decays to 0 at 60 days.
            if let center = context.centerDate {
                let days = abs(c.createdAt.timeIntervalSince(center)) / 86_400
                if days <= 60 {
                    score += max(0, 1.0 - days / 60.0)
                }
            }
            guard score > 0 else { return nil }
            return Scored(id: c.id, score: score)
        }

        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }
}
