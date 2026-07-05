import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClipClusterProposer.dedupByOverlap` per spec
/// § "One clip set = one candidate" (locked July 4 2026). The
/// exact case from Tom's screenshot: three "Pennsylvania" clips
/// overlapping with two "little town" clips must not render as
/// two cards. A clip may appear in at most one rendered candidate.
///
/// Signal strength: proper-noun word-match ≈ time+place (tier 2)
/// > distinctive bigram (tier 1).
struct ClipClusterProposerDedupTests {

    // MARK: - Fixtures

    private func proposal(
        clipIds: [UUID],
        ruleTag: ClusterProposal.RuleTag = .wordMatch,
        proposedName: String = "test"
    ) -> ClusterProposal {
        ClusterProposal(
            clipIds: clipIds,
            ruleTag: ruleTag,
            whyText: "test",
            proposedName: properDisplayName(proposedName),
            previewLines: []
        )
    }

    /// A proper-noun proposedName has no space; a bigram does.
    /// This encodes the signal-strength sniff used by
    /// `signalStrength`.
    private func properDisplayName(_ s: String) -> String { s }

    // MARK: - Exact / superset / substantial overlap

    /// Two proposals with identical clip sets — the exact case
    /// where both rules point at the same clips. Keep only the
    /// stronger signal.
    @Test
    func identicalClipSets_keepStronger() {
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let strong = proposal(clipIds: [a, b, c],
                              ruleTag: .wordMatch,
                              proposedName: "Pennsylvania") // proper noun (no space)
        let weak = proposal(clipIds: [a, b, c],
                            ruleTag: .wordMatch,
                            proposedName: "little town")    // bigram (space)

        let deduped = ClipClusterProposer.dedupByOverlap([strong, weak])

        #expect(deduped.count == 1, "Identical clip sets must produce one candidate")
        #expect(deduped.first?.proposedName == "Pennsylvania", "Strongest signal must win")
    }

    /// The exact case from Tom's July 4 screenshot: Pennsylvania
    /// cluster is a proper-noun superset of the "little town"
    /// bigram cluster. Drop the weaker.
    @Test
    func supersetProperNoun_dropsBigramSubset_perTomScreenshot() {
        let a = UUID()  // Milford ("little town")
        let b = UUID()  // Nazareth ("little town")
        let c = UUID()  // Nazareth summer (Pennsylvania only)

        let pennsylvania = proposal(clipIds: [a, b, c],
                                    ruleTag: .wordMatch,
                                    proposedName: "Pennsylvania")
        let littleTown = proposal(clipIds: [a, b],
                                  ruleTag: .wordMatch,
                                  proposedName: "little town")

        let deduped = ClipClusterProposer.dedupByOverlap([pennsylvania, littleTown])

        #expect(deduped.count == 1)
        #expect(deduped.first?.proposedName == "Pennsylvania")
    }

    /// Time+place cluster overlaps ≥50% with a bigram cluster.
    /// Time+place is tier 2 (stronger); bigram is tier 1. Drop
    /// the bigram.
    @Test
    func timePlace_beats_bigram_onSubstantialOverlap() {
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let timePlace = proposal(clipIds: [a, b, c],
                                 ruleTag: .timePlace,
                                 proposedName: "Together at Sun 6:09 PM")
        let bigram = proposal(clipIds: [a, b],
                              ruleTag: .wordMatch,
                              proposedName: "vintage guitars")  // has space

        let deduped = ClipClusterProposer.dedupByOverlap([timePlace, bigram])

        #expect(deduped.count == 1)
        #expect(deduped.first?.ruleTag == .timePlace)
    }

    /// Minor overlap (< 50% of the smaller set) → both proposals
    /// stay. Two otherwise-distinct clusters that share one
    /// incidental clip aren't the double-filing case; the batch
    /// commit is what enforces "one clip lands in at most one new
    /// memory" (post-v1 per-clip reassignment refines further).
    @Test
    func minorOverlap_bothProposalsSurvive() {
        let a = UUID()
        let b = UUID()
        let c = UUID()  // shared
        let d = UUID()
        let e = UUID()

        let first = proposal(clipIds: [a, b, c],
                             ruleTag: .wordMatch,
                             proposedName: "Nazareth")
        let second = proposal(clipIds: [c, d, e],
                              ruleTag: .wordMatch,
                              proposedName: "Milford")

        let deduped = ClipClusterProposer.dedupByOverlap([first, second])

        // Overlap for `second` against claimed after `first`:
        // intersection = {c} → 1 clipId of 3 → 33% — below 50%
        // gate. Both survive.
        #expect(deduped.count == 2, "Minor overlap must not collapse otherwise-distinct clusters")
    }

    /// Two disjoint proposals both survive.
    @Test
    func disjointProposals_bothSurvive() {
        let s1 = proposal(clipIds: [UUID(), UUID()],
                          ruleTag: .wordMatch,
                          proposedName: "Pennsylvania")
        let s2 = proposal(clipIds: [UUID(), UUID()],
                          ruleTag: .timePlace,
                          proposedName: "Together at Fri 6:09 PM")

        let deduped = ClipClusterProposer.dedupByOverlap([s1, s2])
        #expect(deduped.count == 2)
    }

    /// Empty input → empty output. Guard.
    @Test
    func emptyInput_returnsEmpty() {
        #expect(ClipClusterProposer.dedupByOverlap([]).isEmpty)
    }
}
