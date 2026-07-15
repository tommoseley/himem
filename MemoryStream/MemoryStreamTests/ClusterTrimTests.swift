import Testing
import Foundation
@testable import HiMem

/// Money tests for the Sort cluster editor's transient trim (Model A,
/// ruling 2026-07-15). `ClusterTrim` is the pure core: it turns a
/// per-fingerprint set of removed clipIds (held in the expanded card's
/// view-state) into what the batch commit keeps.
///
/// These confirm the two Bug-First guarantees Tom named:
///   1. **Removed clips stay loose** — a removed clip is excluded from
///      the kept-for-commit set, so `SortBatchCommit` (which removes only
///      the clips it's handed) never places it; it remains in the inbox.
///   2. **Trim-to-0 never commits an empty memory** — a fully-trimmed
///      cluster is dropped, and `committableCount` reaches 0 so the
///      commit disables.
/// (Check 2's "Sort won't re-propose a trimmed-out clip into the same
/// grouping" is structural under Model A: there is no persistent set-aside
/// for Sort to undo, and after commit the kept clips leave the inbox so
/// the grouping cannot reform — nothing to re-propose.)
@Suite
struct ClusterTrimTests {

    private func proposal(_ clipIds: [UUID], rule: ClusterProposal.RuleTag = .timePlace) -> ClusterProposal {
        ClusterProposal(
            clipIds: clipIds,
            ruleTag: rule,
            whyText: "why",
            proposedName: "name",
            previewLines: []
        )
    }

    @Test func keptForCommit_excludesRemovedClips_theyStayLoose() {
        let a = UUID(), b = UUID(), c = UUID()
        let p = proposal([a, b, c])
        let removed = [p.fingerprint.rawValue: Set([b])]

        let kept = ClusterTrim.keptForCommit(proposals: [p], removedByFingerprint: removed)

        #expect(kept.count == 1)
        #expect(kept[0].keptClipIds == [a, c], "order preserved; the removed clip is gone")
        #expect(!kept[0].keptClipIds.contains(b),
                "removed clip must not be committed — it stays in the inbox as a loose clip")
    }

    @Test func keptForCommit_dropsFullyTrimmedCluster_keepsPartial() {
        let a = UUID(), b = UUID()
        let x = UUID(), y = UUID()
        let full = proposal([a, b])      // fully trimmed → dropped
        let partial = proposal([x, y])   // one kept

        let removed = [
            full.fingerprint.rawValue: Set([a, b]),
            partial.fingerprint.rawValue: Set([x])
        ]

        let kept = ClusterTrim.keptForCommit(proposals: [full, partial], removedByFingerprint: removed)

        #expect(kept.count == 1, "the fully-trimmed cluster is dropped — never commit an empty memory")
        #expect(kept[0].proposal.fingerprint == partial.fingerprint)
        #expect(kept[0].keptClipIds == [y])
    }

    @Test func keptForCommit_noTrim_keepsEveryClip() {
        let a = UUID(), b = UUID()
        let p = proposal([a, b])

        let kept = ClusterTrim.keptForCommit(proposals: [p], removedByFingerprint: [:])

        #expect(kept.count == 1)
        #expect(kept[0].keptClipIds == [a, b])
    }

    @Test func committableCount_updatesLiveWithTrims() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let p1 = proposal([a, b])
        let p2 = proposal([c, d])

        // No trim → both commit.
        #expect(ClusterTrim.committableCount(proposals: [p1, p2], removedByFingerprint: [:]) == 2)

        // Trim p1 to empty → label reads 1.
        let one = [p1.fingerprint.rawValue: Set([a, b])]
        #expect(ClusterTrim.committableCount(proposals: [p1, p2], removedByFingerprint: one) == 1)

        // Trim both to empty → 0, commit disables.
        let zero = [p1.fingerprint.rawValue: Set([a, b]),
                    p2.fingerprint.rawValue: Set([c, d])]
        #expect(ClusterTrim.committableCount(proposals: [p1, p2], removedByFingerprint: zero) == 0)
    }
}
