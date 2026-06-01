import Foundation
import CoreData

/// One candidate memory the suggester thinks may belong in a
/// project. `matchedTopics` carries the original topic display
/// names (intersection of project ∩ entry) so the review sheet's
/// "Matches: X, Y" line reads naturally rather than echoing slugs.
struct SuggestedMembership: Equatable {
    let entryId: UUID
    let matchedTopics: [String]
}

/// Pure function over Core Data: rank candidate memories for a
/// project based on accepted-topic overlap. No AI, no network, no
/// assists consumed — this is the local prefilter step that
/// `Projects · MVP spec.md` describes as the input to (a future)
/// server-side AI re-rank.
///
/// Candidacy rules (see ProjectMembershipSuggesterTests for the
/// locked contract):
/// - Not already a member of the project.
/// - Not in the caller-supplied `dismissed` set.
/// - Has ≥ 1 accepted topic whose slug appears in the project's
///   topic fingerprint. **Suggested topics from an unaccepted
///   OrganizePass do not count** — only the entry's real `topics`
///   relationship.
///
/// Ranked by overlap count desc, then `createdAt` desc.
enum ProjectMembershipSuggester {

    static func candidates(
        for project: Project,
        in context: NSManagedObjectContext,
        dismissed: Set<UUID>
    ) -> [SuggestedMembership] {
        // Project topic fingerprint — slug-keyed for canonical
        // matching, value-keyed by the *display name* so the
        // reason row says "Matches: Photography" not
        // "Matches: photography". When two project memories
        // contribute the same slug under different display names
        // (rare but possible), the first one wins; the join
        // remains canonical.
        var projectSlugToName: [String: String] = [:]
        for entry in project.entriesArray {
            for topic in entry.topicsArray {
                let key = canonicalSlug(for: topic)
                if !key.isEmpty, projectSlugToName[key] == nil {
                    projectSlugToName[key] = topic.name
                }
            }
        }

        if projectSlugToName.isEmpty {
            return []
        }

        let memberIds: Set<UUID> = Set(project.entriesArray.map(\.id))

        // Fetch all non-recycled entries, newest first. The 500
        // cap mirrors AddMemoryToProjectSheet — at expected
        // volumes this is the full set; if a power user blows
        // past it, the affordance still works on the most-recent
        // 500 (post-launch concern; not v1).
        let request = JournalEntry.fetchAllChronological(limit: 500)
        let entries = (try? context.fetch(request)) ?? []

        var candidates: [SuggestedMembership] = []
        for entry in entries {
            guard !memberIds.contains(entry.id) else { continue }
            guard !dismissed.contains(entry.id) else { continue }

            var matchedNames: [String] = []
            var seenSlugs: Set<String> = []
            for topic in entry.topicsArray {
                let slug = canonicalSlug(for: topic)
                guard !slug.isEmpty else { continue }
                guard let projectName = projectSlugToName[slug] else { continue }
                if seenSlugs.insert(slug).inserted {
                    matchedNames.append(projectName)
                }
            }

            guard !matchedNames.isEmpty else { continue }
            candidates.append(SuggestedMembership(
                entryId: entry.id,
                matchedTopics: matchedNames
            ))
        }

        // Rank: overlap count desc, then createdAt desc.
        // `entries` is already createdAt-desc from
        // fetchAllChronological, so stable-sorting by count desc
        // preserves the date order within equal counts.
        let entryDates: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.id, $0.createdAt) }
        )
        return candidates.sorted { lhs, rhs in
            if lhs.matchedTopics.count != rhs.matchedTopics.count {
                return lhs.matchedTopics.count > rhs.matchedTopics.count
            }
            let lDate = entryDates[lhs.entryId] ?? .distantPast
            let rDate = entryDates[rhs.entryId] ?? .distantPast
            return lDate > rDate
        }
    }

    /// Topic.slug is set on creation (see
    /// ProcessingEngine.assignTopics), but fall back to recomputing
    /// from the name so a defensively-empty slug doesn't silently
    /// drop a topic from the match.
    private static func canonicalSlug(for topic: Topic) -> String {
        if !topic.slug.isEmpty { return topic.slug }
        return TopicSlugHelper.slugify(topic.name)
    }
}
