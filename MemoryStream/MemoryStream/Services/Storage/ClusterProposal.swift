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

/// Model-A transient-trim resolution for the Sort cluster editor
/// (`Captured Clips · session-first · spec.md` §87 "Adjust =
/// expand-in-place + Remove (subtractive)", ruling 2026-07-15).
///
/// The expanded cluster card holds a per-fingerprint set of removed
/// clipIds in **view-state only** — trims are provisional-and-reversible
/// until the batch commit. These pure functions turn that trim into what
/// the commit keeps. Nothing here touches the proposer or any store: a
/// removed clip is simply excluded from the commit, so it stays in the
/// inbox as a loose clip (`SortBatchCommit` removes only the clips it's
/// handed). That is the whole mechanism by which "Not together at clip
/// granularity" works without a new set-aside — no proposer change.
enum ClusterTrim {

    /// Kept clipIds per proposal after applying the per-fingerprint
    /// removed sets. A cluster trimmed to empty is **dropped** — never
    /// commit an empty memory (spec edge, 2026-07-15). Clip order within
    /// a cluster is preserved.
    static func keptForCommit(
        proposals: [ClusterProposal],
        removedByFingerprint: [String: Set<UUID>]
    ) -> [(proposal: ClusterProposal, keptClipIds: [UUID])] {
        proposals.compactMap { proposal in
            let removed = removedByFingerprint[proposal.fingerprint.rawValue] ?? []
            let kept = proposal.clipIds.filter { !removed.contains($0) }
            guard !kept.isEmpty else { return nil }
            return (proposal, kept)
        }
    }

    /// Live count of Memories the commit will create — clusters with at
    /// least one kept clip. Drives the "Keep these · N memories" label so
    /// it always tells the truth as clips are trimmed, and reaches 0 only
    /// when every cluster is fully trimmed (commit then disabled).
    static func committableCount(
        proposals: [ClusterProposal],
        removedByFingerprint: [String: Set<UUID>]
    ) -> Int {
        keptForCommit(proposals: proposals, removedByFingerprint: removedByFingerprint).count
    }
}

/// **The cluster card's one-line description** (F43, 2026-08-02).
///
/// One definition, called twice: by `ClipClusterProposer` for the proposal's
/// own `whyText`, and by the card for the KEPT set after a trim. The card
/// previously rendered the stored `whyText`, which is fixed at construction
/// — so it kept describing the original membership while the user removed
/// clips from it.
///
/// **The span is computed from the clips passed in, not from the proposal.**
/// On device the header read "125 minutes apart" and was correct only
/// because the kept set retained both endpoints; setting aside the last clip
/// would have left the number plausible and wrong. Two of three numbers
/// accidentally right is more dangerous than all three visibly broken.
///
/// Observation, never conclusion (J5): how many clips, how many sittings,
/// how far apart. Never that they belong together.
enum ClusterSubtitleBuilder {

    /// **All three numbers from ONE set of items** (2026-08-12).
    ///
    /// The three-argument form below cannot stop a caller supplying three
    /// numbers scoped to different sets, and `SessionListView.clusterSubtitle`
    /// did exactly that: `clipCount` counted voice **plus media**, while
    /// `sittingCount` grouped and `capturedAts` ranged over **voice alone**.
    /// On device that read *"4 clips from 3 sittings"* and *"5 clips from 3
    /// sittings"* — correct only because every seeded photo happened to sit
    /// inside a voice sitting. A photo captured between two sittings, or after
    /// the last clip, makes the count move while the sitting count and the
    /// span do not.
    ///
    /// This is F35(a)/F38's shape — a number computed from a different set
    /// than the one being described — surviving in the cluster card because
    /// the card's subtitle was never migrated to the composed bench. Media is
    /// an item; grouping it media-agnostically through `UnifiedBenchGrouper`
    /// is what makes the sitting count answer the same question the clip count
    /// does.
    static func subtitle(items: [BenchClipItem], soloIds: Set<UUID> = []) -> String {
        subtitle(
            clipCount: items.count,
            sittingCount: UnifiedBenchGrouper.group(items, soloIds: soloIds).count,
            capturedAts: items.map(\.capturedAt)
        )
    }

    /// The primitive. Prefer `subtitle(items:)` — this cannot check that its
    /// three arguments describe the same set, which is precisely how they came
    /// apart.
    static func subtitle(clipCount: Int, sittingCount: Int, capturedAts: [Date]) -> String {
        let clipsWord = clipCount == 1 ? "clip" : "clips"
        let sittingsWord = sittingCount == 1 ? "sitting" : "sittings"
        let minutes: Int = {
            guard let first = capturedAts.min(), let last = capturedAts.max() else { return 1 }
            return max(1, Int((last.timeIntervalSince(first) / 60).rounded()))
        }()
        let minutesWord = minutes == 1 ? "minute" : "minutes"
        return "\(clipCount) \(clipsWord) from \(sittingCount) \(sittingsWord)"
            + " · \(minutes) \(minutesWord) apart"
    }
}
