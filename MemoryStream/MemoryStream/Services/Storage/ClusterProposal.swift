import Foundation
import CryptoKit

/// One confident cluster proposal on the Captured Clips workbench.
/// Per `docs/design/Captured Clips · session-first · spec.md`
/// v3 § "Sort is the moment" and § "Clustering is Honest-Label":
/// clusters are pre-accepted proposals shown only when confident.
/// The user's "Keep these" bottom commit turns each into a draft
/// Memory; "Not together" adds its fingerprint to the manifest's
/// dismissal store so Sort won't re-propose it.
///
/// Pure/Codable. All fields deterministic from the clipIds + rule
/// so the same input always produces the same proposal (and the
/// same fingerprint).
struct ClusterProposal: Equatable, Hashable, Codable {

    /// The clips this cluster gathers. Order is by capturedAt
    /// ascending so the preview lines read chronologically. The
    /// clipIds are the identity of the cluster — two proposals with
    /// the same set of clipIds are the same proposal regardless of
    /// which rule surfaced them (dismissal suppresses future
    /// re-proposals across rules).
    let clipIds: [UUID]

    /// Which deterministic rule produced this cluster. Encoded as
    /// a string tag (not an enum with associated values) so the
    /// fingerprint is stable across schema evolution.
    let ruleTag: RuleTag

    /// Templated "why" string per spec § 80 — filled from the
    /// signals, not LLM prose. Examples:
    ///   `"5 clips · one 18-minute stretch, same place"`
    ///   `"2 clips mention \"Hosta Hideaway\""`
    let whyText: String

    /// Proposed cluster name used as the draft-Memory title on
    /// commit (spec § 74: "each new Memory is titled with its
    /// proposed cluster name and created as Draft organized").
    let proposedName: String

    /// One-line preview per member clip, ordered chronologically.
    /// `(timeHHMM, truncatedTranscript)`. Rendered inside the
    /// cluster card as a mini clip stack.
    let previewLines: [PreviewLine]

    struct PreviewLine: Equatable, Hashable, Codable {
        let timeLabel: String        // "6:12"
        let transcriptSnippet: String
    }

    /// Which deterministic rule surfaced this cluster. Used only
    /// for the fingerprint's rule differentiator + for logs /
    /// debug UI. Two rules that surface the same clipId set still
    /// share a fingerprint if the tag matches; the "either rule"
    /// dedup happens at the proposer level before dismissal.
    enum RuleTag: String, Codable, CaseIterable {
        /// Deterministic time-window + coord-proximity match.
        /// Requires location on every member clip.
        case timePlace
        /// Distinctive-token match — proper noun or low-frequency
        /// term in the user's own inbox corpus.
        case wordMatch
    }

    /// Stable fingerprint for the dismissal store. Hash of the
    /// sorted clipId UUIDs plus the rule tag. **Exact-set
    /// suppression only** (spec § "Sort is the bench's resting
    /// state" + Tom's Q3 answer): if the user later captures a
    /// sixth clip that fits, the new 6-element cluster is a
    /// different fingerprint and is proposed fresh. Never fuzzy.
    var fingerprint: ClusterFingerprint {
        ClusterFingerprint.derive(clipIds: clipIds, ruleTag: ruleTag)
    }
}

/// One user-dismissed cluster, stored on `InboxManifest`. Kept as
/// `clipIds + ruleTag` (not just the fingerprint) so the manifest
/// can prune-on-write: when a clipId leaves the inbox (placed into
/// a Memory), the fingerprint referencing it is dead — the proposer
/// only ever sees current clipIds and can never re-propose a cluster
/// with a missing member. Storing the source clipIds lets us detect
/// that dead-ness and drop the record.
///
/// Spec § "Sort is the bench's resting state" + Tom's Q3 answer:
/// prune-on-write, exact-set suppression only. Never fuzzy.
struct DismissedCluster: Equatable, Hashable, Codable {
    let clipIds: Set<UUID>
    let ruleTag: ClusterProposal.RuleTag

    var fingerprint: ClusterFingerprint {
        ClusterFingerprint.derive(clipIds: Array(clipIds), ruleTag: ruleTag)
    }
}

/// SHA-256-derived deterministic identifier for a cluster
/// proposal. Wraps a hex string so it's `Codable`/`Hashable` cleanly
/// for `Set<ClusterFingerprint>` persistence on `InboxManifest`.
struct ClusterFingerprint: Hashable, Codable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Deterministic derivation: sort clipId UUIDs
    /// case-insensitively (their string form is canonical anyway),
    /// join with a null separator, append `\u{1}` + the rule tag,
    /// SHA-256, take the first 16 bytes hex-encoded. 128 bits is
    /// far more than enough collision safety for the number of
    /// clusters a single user's inbox can hold.
    static func derive(clipIds: [UUID], ruleTag: ClusterProposal.RuleTag) -> ClusterFingerprint {
        let sortedIds = clipIds
            .map { $0.uuidString.lowercased() }
            .sorted()
        let joined = sortedIds.joined(separator: "\u{0}")
            + "\u{1}"
            + ruleTag.rawValue
        let digest = SHA256.hash(data: Data(joined.utf8))
        // Take 16 bytes (128 bits) → 32-hex-char fingerprint.
        let hex = digest.prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return ClusterFingerprint(rawValue: hex)
    }
}
