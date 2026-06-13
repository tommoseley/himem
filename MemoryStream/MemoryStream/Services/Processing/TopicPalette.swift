import Foundation

/// Partitions the topics an organizer returned into "existing in the
/// user's palette" vs "genuinely new" — the data-side of AI Organize
/// spec §2c's NEW-flag discipline.
///
/// Comparison is **case-insensitive** and **whitespace-trimmed**. When a
/// returned topic matches an existing palette entry only by casing
/// ("garden" returned, palette has "Garden"), the partition emits the
/// **palette's canonical form** — the user sees their familiar
/// capitalization, not the model's variant. This prevents the silent
/// proliferation of *Garden / garden / GARDEN* as three "different"
/// topics.
///
/// **Strict equality only — for now.** Spec §2c calls out the
/// sibling case explicitly: the on-device path coins "Gardening" while
/// the palette has "Garden". Under this strict-match implementation,
/// they're distinct and "Gardening" is flagged NEW. Fuzzy match
/// (Jaro-Winkler, embedding similarity, normalized singular/plural) is
/// a deliberate post-launch improvement — held back so the failure
/// shape is honest until real user data shows which fuzzy rules are
/// worth the complexity.
///
/// Why this is a set-diff rather than a model-self-flag: models
/// invent novelty and miss matches. A diff against the actual palette
/// is the only honest answer.
enum TopicPalette {

    struct Partition: Equatable {
        /// Returned topics that match a palette entry. Canonicalized
        /// to the palette's existing form so the user sees the
        /// capitalization they're already used to.
        let existing: [String]
        /// Returned topics that don't match any palette entry. These
        /// are the NEW chips the review sheet flags AI-blue dashed
        /// per spec §2c.
        let new: [String]
    }

    /// Partitions `returned` against `existing`. Empty / whitespace-only
    /// entries in `returned` are filtered (defensive; the model
    /// shouldn't emit these). Duplicate matches are NOT deduped — the
    /// caller (review UI) gets the model's output count and decides
    /// what to do with duplicates.
    static func partition(returned: [String], existing: [String]) -> Partition {
        // Build a normalized-key → palette-canonical-form lookup.
        // First-wins on duplicate palette keys (palette uniqueness is
        // the system's invariant elsewhere; we don't enforce it here).
        var lookup: [String: String] = [:]
        for topic in existing {
            let key = normalize(topic)
            guard !key.isEmpty, lookup[key] == nil else { continue }
            lookup[key] = topic
        }
        var matched: [String] = []
        var fresh: [String] = []
        for raw in returned {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if let canonical = lookup[key] {
                matched.append(canonical)
            } else {
                fresh.append(trimmed)
            }
        }
        return Partition(existing: matched, new: fresh)
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
