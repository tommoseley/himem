import Testing
import Foundation
@testable import HiMem

/// **B21 — `ClipClusterProposer` is documented "idempotent + stateless" and was
/// not.**
///
/// When several qualified tokens describe the *same* set of sessions, one names
/// the cluster. That contest was a fold over `tokenToSessions`, a `Dictionary`,
/// so the winner depended on iteration order — which Swift seeds **per
/// process**. The name is not cosmetic: `signalStrength` reads it, scoring a
/// space as a bigram (tier 1) and no space as a proper noun (tier 2), so the
/// overlap dedup could order differently between runs on identical input.
///
/// **How it was caught, which is the part worth keeping.** It did not surface
/// as a wrong cluster. `[ClusterTrace]` emitted ~16 times in 2 seconds and was
/// read as churn in the bench; the device log showed the `s…` session lines and
/// the `FORMED` lines **identical** across emissions, with only the `TOKEN`
/// line *order* differing. The instrument was reporting instability it had
/// introduced itself — the trace's signature moved because the token verdicts
/// were appended in dictionary order. B23 (a suspected regroup storm) collapsed
/// into this.
///
/// **The red is the property, not the seeding.** Dictionary order is stable
/// within a process, so a test cannot make the same call disagree with itself;
/// asserting "run it twice" would pass on every machine while the defect
/// stands. Feeding the same candidates in different *orders* tests exactly the
/// thing that was wrong, deterministically.
struct ClusterTokenDeterminismTests {

    private func candidate(_ token: String, properNoun: Bool = false) -> ClipClusterProposer.TokenCandidate {
        .init(token: token, isProperNoun: properNoun)
    }

    @Test
    func theWinnerDoesNotDependOnTheOrderCandidatesArriveIn() {
        let a = candidate("harbor lantern")
        let b = candidate("lantern tide")
        let c = candidate("tide turned")

        let forward = ClipClusterProposer.nameForCluster([a, b, c])
        let reversed = ClipClusterProposer.nameForCluster([c, b, a])
        let shuffled = ClipClusterProposer.nameForCluster([b, a, c])

        #expect(
            forward == reversed && reversed == shuffled,
            "The same candidates in a different order named a different cluster — the class doc claims 'same input always produces the same output', and signalStrength reads this name"
        )
    }

    /// The existing preference is preserved: a proper noun still beats a bigram,
    /// because it produces the clearest reason string. Determinism must not be
    /// bought by flattening a rule that was deliberate.
    @Test
    func aProperNounStillBeatsABigramFromEitherDirection() {
        let bigram = candidate("harbor lantern")
        let proper = candidate("Gettysburg", properNoun: true)

        #expect(ClipClusterProposer.nameForCluster([bigram, proper]) == "Gettysburg")
        #expect(ClipClusterProposer.nameForCluster([proper, bigram]) == "Gettysburg")
    }

    @Test
    func twoProperNounsAlsoResolveDeterministically() {
        let x = candidate("Dillsburg", properNoun: true)
        let y = candidate("Gettysburg", properNoun: true)
        #expect(ClipClusterProposer.nameForCluster([x, y]) == ClipClusterProposer.nameForCluster([y, x]))
    }

    @Test
    func noCandidatesNamesNothing() {
        #expect(ClipClusterProposer.nameForCluster([]) == nil)
    }

    /// **The symptom, guarded.** The winner being deterministic is not enough:
    /// the trace's signature is derived from its rendered lines, so the
    /// *verdict order* has to be stable too, or the instrument keeps reporting
    /// churn that is not there. Dictionary order is fixed within a process, so
    /// this cannot fail by re-running — it pins the sort that makes the
    /// property hold across processes.
    @Test
    func tokenVerdictsAreEmittedInAStableSortedOrder() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            ClipGroup(clips: [Self.clip(at: base, "Harbor Lantern and the tide turned by the museum")]),
            ClipGroup(clips: [Self.clip(at: base.addingTimeInterval(-900), "Harbor Lantern again, past the museum")]),
        ]
        let trace = ClusterProposalTrace()
        _ = ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: [],
            entityExtractor: Self.NoEntities(),
            trace: trace
        )

        #expect(!trace.tokenVerdicts.isEmpty, "self-test: the trace recorded verdicts to order")

        // The RENDERED order is what the signature is built from, so that is
        // what must be canonical. The producing loops are deterministic too,
        // but they emit in two passes (notDistinctive, then the naming
        // contest), so their concatenation is deterministic without being
        // sorted — asserting on emission order would pin an implementation
        // detail while leaving the signature exposed.
        let rendered = trace.lines
            .filter { $0.contains("TOKEN “") }
            .map { line -> String in
                let afterQuote = line.components(separatedBy: "TOKEN “")[1]
                return afterQuote.components(separatedBy: "”")[0]
            }
        #expect(!rendered.isEmpty, "self-test: the scanner found TOKEN lines to check")
        #expect(
            rendered == rendered.sorted(),
            "Rendered token verdicts must be in a canonical order — they feed the trace signature, and an unstable order is what made [ClusterTrace] fire ~16 times over an unchanging bench"
        )
    }

    private final class NoEntities: EntityExtractor {
        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(entities: [])
        }
    }

    private static func clip(at time: Date, _ transcript: String) -> InboxClip {
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
    }
}
