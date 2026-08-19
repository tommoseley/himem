import Testing
import Foundation
@testable import HiMem

/// **The instrument's own guard.**
///
/// `[ClusterTrace]` exists to separate two outcomes that look identical from
/// outside `ClipClusterProposer.propose` — *a proposal formed and was
/// discarded* versus *the token never qualified, so nothing formed*. Sparrow
/// Quarry did not cluster on a real bench while Harbor Lantern and Thistle
/// Beacon did, and four theories were spent on an adjacent clip because the
/// screen shows the same nothing either way.
///
/// **These tests exist because a diagnostic that cannot be shown to
/// discriminate is worthless.** On 2026-08-09 a diagnostic written specifically
/// to be falsifiable *passed by matching nothing*: `synthesizedRows` and
/// `emptyGroups` were both reductions over an empty set, so both printed 0
/// regardless of the truth — in the very line intended to end the guessing.
/// So the discrimination itself is asserted here, in both directions, rather
/// than assumed from the trace being present.
///
/// Uses `StubEntityExtractor` for the same reason the word-match suite does:
/// NLTagger is unreliable on the iOS 26 simulator, and a trace test that
/// depended on it would be measuring the tagger, not the trace.
struct ClusterProposalTraceTests {

    // MARK: - Fixtures

    private func session(at time: Date, transcript: String) -> ClipGroup {
        ClipGroup(clips: [
            InboxClip(
                clipId: UUID(),
                capturedAt: time,
                duration: 30,
                transcript: transcript,
                latitude: nil,
                longitude: nil,
                source: "watch",
                audioFilename: "\(UUID()).caf",
                transcriptionAttempted: true,
                rollGroupId: nil
            )
        ])
    }

    private final class StubEntityExtractor: EntityExtractor {
        var defaultEntities: [LocalEntityExtractor.LocalEntity] = []
        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(entities: defaultEntities)
        }
    }

    private func proposal(
        clipIds: [UUID],
        ruleTag: ClusterProposal.RuleTag = .wordMatch,
        proposedName: String
    ) -> ClusterProposal {
        ClusterProposal(
            clipIds: clipIds,
            ruleTag: ruleTag,
            whyText: "test",
            proposedName: proposedName,
            previewLines: []
        )
    }

    // MARK: - The discrimination, both directions

    /// **The money test for the instrument.** A proposal eaten by the ≥50%
    /// overlap dedup must be *present with a fate that names its eater*; a
    /// proposal that never formed must be *absent*. If both read the same way,
    /// the instrument answers nothing and the next Sparrow Quarry is another
    /// round of theories.
    @Test
    func anEatenProposalCarriesItsEater_whileOneThatNeverFormedIsSimplyAbsent() {
        let a = UUID(), b = UUID(), c = UUID()
        let strong = proposal(clipIds: [a, b, c], proposedName: "Pennsylvania")  // proper noun: tier 2
        let weak = proposal(clipIds: [a, b, c], proposedName: "little town")     // bigram: tier 1
        let neverFormed = proposal(clipIds: [UUID(), UUID()], proposedName: "Nowhere")

        let trace = ClusterProposalTrace()
        let kept = ClipClusterProposer.dedupByOverlap([strong, weak], trace: trace)

        #expect(kept.count == 1)
        #expect(kept.first?.proposedName == "Pennsylvania")

        // Eaten: a fate exists, and it names both the ratio and the claimer.
        guard case let .eatenByOverlap(ratio, claimedBy) =
                trace.fate(ofFingerprint: weak.fingerprint.rawValue) else {
            Issue.record("The eaten proposal must carry an eatenByOverlap fate — without it the trace cannot distinguish 'discarded' from 'never formed', which is the only thing it is for")
            return
        }
        #expect(ratio == 1.0, "All three of its clips were already claimed")
        #expect(
            claimedBy.contains { $0.hasPrefix("Pennsylvania#") },
            "The fate must NAME the proposal that ate it — 'something ate it' is the reading we already had from the screen"
        )

        // Never formed: no fate at all. This is the other half of the
        // discrimination and is the branch that points at the token.
        #expect(
            trace.fate(ofFingerprint: neverFormed.fingerprint.rawValue) == nil,
            "A proposal that never formed must have no fate — a default fate would make absence indistinguishable from suppression"
        )
    }

    /// The token branch: sessions that share a word which is neither a proper
    /// noun nor a bigram form **nothing**, and the trace says *why* rather than
    /// leaving the reader to infer it from an empty proposal list.
    @Test
    func aSharedButUndistinctiveTokenIsNamedAsSuch_ratherThanBeingSilentlyAbsent() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            session(at: base, transcript: "the museum was closed today"),
            session(at: base.addingTimeInterval(-3600), transcript: "walked past the museum again"),
        ]
        let trace = ClusterProposalTrace()

        let proposals = ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: [],
            entityExtractor: StubEntityExtractor(),   // no proper nouns at all
            trace: trace
        )

        #expect(proposals.isEmpty, "Neither proper noun nor bigram — under-suggest discipline says nothing clusters")
        let museum = trace.tokenVerdicts.first { $0.token == "museum" }
        #expect(museum != nil, "A token shared across two sessions must appear in the verdicts even when it loses")
        #expect(museum?.fate == .notDistinctive)
        #expect(museum?.sessionIndices == [0, 1], "The verdict must say WHICH sessions shared it")
        #expect(museum?.isProperNoun == false)
        #expect(museum?.isBigram == false)
    }

    /// The self-test the `head -8` and `synthesizedRows` failures both earn: on
    /// the happy path the trace must be **populated and specific**. A trace
    /// that recorded nothing would satisfy every "absence" assertion above
    /// while reporting nothing at all, so the positive case is asserted too.
    @Test
    func theTraceIsPopulatedOnTheHappyPath_soItCannotPassByMatchingNothing() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            session(at: base, transcript: "Notes from Sparrow Quarry, north face in shadow"),
            session(at: base.addingTimeInterval(-900), transcript: "More from Sparrow Quarry after the climb"),
            session(at: base.addingTimeInterval(-1800), transcript: "Leaving Sparrow Quarry as the light went"),
        ]
        let trace = ClusterProposalTrace()

        let proposals = ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: [],
            entityExtractor: StubEntityExtractor(),
            trace: trace
        )

        #expect(proposals.count == 1, "“sparrow quarry” is a bigram shared by all three sittings")
        #expect(trace.sessionInputs.count == 3, "Every session the proposer was handed must be recorded")
        #expect(trace.formed.count == 1)
        #expect(trace.fate(ofFingerprint: proposals.first?.fingerprint.rawValue ?? "") == .survived)

        // The trace must be able to answer "was this clip ever claimed?" — the
        // question the device raises about a clip that drew loose.
        let anId = sessions[0].clips[0].clipId
        #expect(trace.formedProposalsClaiming(anId).count == 1)

        // And the rendered form must carry the verdicts, not just the counts:
        // the log is what a device pass actually reads.
        let text = trace.lines.joined(separator: "\n")
        #expect(text.contains("FORMED"))
        #expect(text.contains("SURVIVED"))
        #expect(text.contains("sessions=3"))
    }

    /// A user-dismissed cluster is a *third* fate, not a silent absence — so a
    /// device reading "no card" can tell "you said not-together" apart from
    /// "the rules never proposed it".
    @Test
    func aDismissedClusterIsNamedAsDismissed() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            session(at: base, transcript: "Notes from Sparrow Quarry, north face in shadow"),
            session(at: base.addingTimeInterval(-900), transcript: "More from Sparrow Quarry after the climb"),
        ]
        let discovered = ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: [],
            entityExtractor: StubEntityExtractor()
        )
        let fingerprint = discovered.first?.fingerprint

        let trace = ClusterProposalTrace()
        let after = ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: Set([fingerprint].compactMap { $0 }),
            entityExtractor: StubEntityExtractor(),
            trace: trace
        )

        #expect(after.isEmpty)
        #expect(trace.fate(ofFingerprint: fingerprint?.rawValue ?? "") == .dismissedByUser)
    }

    /// The single-session ceiling must announce itself. A withheld list that
    /// renders like an empty one is exactly how a `head -8` became "there are
    /// no callers".
    @Test
    func aWithheldTokenListSaysSo_ratherThanReadingAsEmpty() {
        let trace = ClusterProposalTrace()
        trace.recordInput(sessions: [])
        trace.recordSingleSessionTokens((0..<80).map { "token\($0)" })

        let text = trace.lines.joined(separator: "\n")
        #expect(text.contains("80"), "The true total must appear even when the list does not")
        #expect(text.contains("WITHHELD"))
        #expect(text.contains("NOT absent"))
    }

    /// **The trace's signature must not move when the bench has not.**
    ///
    /// `recordFormed` captured `proposals` straight from `proposeWordMatch`,
    /// which builds its array by mapping `clustersByTokenKey.values` — a
    /// `Dictionary`. So the FORMED block reordered between otherwise-identical
    /// emissions, the signature gate saw a new string each time, and
    /// `[ClusterTrace]` re-emitted on an unchanging bench. **Observed on device
    /// 2026-08-18**, one day after B21 fixed the token-verdict half of exactly
    /// this: the winner and the verdict order were made deterministic, the
    /// proposal array was not.
    ///
    /// Production was never affected — `dedupByOverlap` and the final
    /// `proposals.sort` are both total orders — but an instrument that reports
    /// churn it invented is worse than no instrument, and this is the second
    /// time in two days. Same test shape as B21's, for the same reason: a
    /// `Dictionary`'s order is fixed *within* a process, so "run it twice"
    /// cannot fail. Feeding the same proposals in a different order can.
    @Test
    func theFormedRecordDoesNotDependOnTheOrderProposalsArriveIn() {
        let a = proposal(clipIds: [UUID(), UUID()], proposedName: "Alpha")
        let b = proposal(clipIds: [UUID(), UUID()], proposedName: "Beta")
        let c = proposal(clipIds: [UUID(), UUID()], proposedName: "Gamma")

        let forward = ClusterProposalTrace()
        forward.recordFormed([a, b, c])
        let shuffled = ClusterProposalTrace()
        shuffled.recordFormed([c, a, b])

        #expect(!forward.lines.isEmpty, "self-test: the trace recorded something to compare")
        #expect(
            forward.lines == shuffled.lines,
            "The same proposals in a different order produced a different signature — the emission gate fires on an unchanged bench and reports churn that is not there"
        )
    }
}
