import Testing
import Foundation
@testable import HiMem

/// **B23 — the proposer must not re-run when its inputs have not changed.**
///
/// The device evidence is eleven regroups inside 0.24 s, all at an identical
/// bench state (`sessions=1 · lens=15` on every one), each carrying a full
/// NLTagger pass. Ten of the eleven are redundant work against a 400 ms
/// cold-launch budget.
///
/// **These are reproductions, not contract tests.** `BenchProposalMemo` was
/// written with non-memoizing semantics first — it stored the inputs and
/// recomputed anyway — so `identicalInputsComputeOnce` fails as an
/// **assertion** (`2 == 1`) rather than as a compile error. A test that does
/// not compile has proven nothing (Bug-First step 3, *Identify the Red*), and
/// this project has mistaken a compile failure for a red before.
///
/// The invalidation tests matter more than the hit test. A memo that never
/// invalidates is not a fast bench, it is a **stale** one — and the specific
/// staleness that would bite here is a clip gaining its transcript after
/// arrival, which is routine on this surface.
struct BenchProposalMemoTests {

    private func clip(
        _ id: UUID = UUID(),
        at seconds: TimeInterval,
        _ transcript: String,
        lat: Double? = nil,
        lon: Double? = nil
    ) -> InboxClip {
        InboxClip(
            clipId: id,
            capturedAt: Date(timeIntervalSinceReferenceDate: seconds),
            duration: 2,
            transcript: transcript,
            latitude: lat,
            longitude: lon,
            source: "watch",
            audioFilename: "\(id).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
    }

    private func sessions(_ transcripts: [String]) -> [ClipGroup] {
        transcripts.enumerated().map { index, text in
            ClipGroup(clips: [clip(at: Double(index) * 900, text)])
        }
    }

    /// A counting stand-in for `ClipClusterProposer.propose`. The real proposer
    /// is exercised by its own suites; what is under test here is **how often
    /// the expensive call is made**, which is a property of the memo.
    private final class ComputeCounter {
        private(set) var calls = 0
        func compute(_: [ClipGroup], _: Set<ClusterFingerprint>) -> [ClusterProposal] {
            calls += 1
            return []
        }
    }

    // MARK: - The reproduction

    /// **THE MONEY TEST.** Two composes over an unchanged bench run the
    /// proposer once.
    ///
    /// Red before the memo: `calls == 2`.
    @Test
    func identicalInputsComputeOnce() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let bench = sessions(["Harbor Lantern before the tide", "Second pass by Harbor Lantern"])

        _ = memo.proposals(sessions: bench, dismissed: [], compute: counter.compute)
        _ = memo.proposals(sessions: bench, dismissed: [], compute: counter.compute)

        #expect(counter.calls == 1, "the proposer re-ran for a bench that had not changed — got \(counter.calls) calls")
        #expect(memo.lastCallWasHit, "the second call reused a cached answer but did not report itself as a hit")
    }

    /// The launch burst, at its measured size: eleven composes, one pass.
    @Test
    func theLaunchBurstRunsTheProposerOnce() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let bench = sessions(["Thistle Beacon from the lower path", "Halfway up to Thistle Beacon"])

        for _ in 0..<11 {
            _ = memo.proposals(sessions: bench, dismissed: [], compute: counter.compute)
        }

        #expect(counter.calls == 1, "eleven identical composes ran the proposer \(counter.calls) times")
    }

    /// A cached answer must be the same answer, not merely a cheap one.
    @Test
    func aHitReturnsTheSameProposalsAsTheMiss() {
        var memo = BenchProposalMemo()
        let bench = sessions(["Sparrow Quarry north face", "Leaving Sparrow Quarry"])
        let made = [
            ClusterProposal(
                clipIds: bench.flatMap { $0.clips.map(\.clipId) },
                ruleTag: .wordMatch,
                whyText: "why",
                proposedName: "Sparrow Quarry",
                previewLines: []
            )
        ]

        let first = memo.proposals(sessions: bench, dismissed: [], compute: { _, _ in made })
        let second = memo.proposals(sessions: bench, dismissed: [], compute: { _, _ in
            Issue.record("the memo recomputed when it should have reused")
            return []
        })

        #expect(first == second, "a memo hit returned different proposals from the miss that filled it")
        #expect(second == made)
    }

    // MARK: - Invalidation — the half that keeps this from being a stale bench

    /// **The trap this design exists to avoid.** A clip gaining its transcript
    /// after arrival is routine here, and an id-keyed signature would not see
    /// it — the bench would keep proposing from words the clip no longer has.
    ///
    /// It is caught because `InboxClip`'s `Equatable` is synthesized and
    /// `ClipGroup.==` compares full clip content. If either of those changes to
    /// an id-only comparison, this test is what fails.
    @Test
    func alateTranscriptInvalidatesTheMemo() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let id = UUID()

        let before = [ClipGroup(clips: [clip(id, at: 0, "")])]
        let after = [ClipGroup(clips: [clip(id, at: 0, "Harbor Lantern before the tide turned")])]

        _ = memo.proposals(sessions: before, dismissed: [], compute: counter.compute)
        _ = memo.proposals(sessions: after, dismissed: [], compute: counter.compute)

        #expect(counter.calls == 2, "the clip gained a transcript and the memo kept the old proposals")
        #expect(!memo.lastCallWasHit)
    }

    /// A coordinate arriving late is the `proposeTimePlace` half of the same
    /// trap — `propose` reads lat/lon, so the signature must too.
    @Test
    func aLateCoordinateInvalidatesTheMemo() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let id = UUID()

        let before = [ClipGroup(clips: [clip(id, at: 0, "same words")])]
        let after = [ClipGroup(clips: [clip(id, at: 0, "same words", lat: 40.0, lon: -75.0)])]

        _ = memo.proposals(sessions: before, dismissed: [], compute: counter.compute)
        _ = memo.proposals(sessions: after, dismissed: [], compute: counter.compute)

        #expect(counter.calls == 2, "a clip gained coordinates and the memo kept the old proposals")
    }

    /// Membership changing — a clip deleted from a sitting — must invalidate.
    @Test
    func changedMembershipInvalidatesTheMemo() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let three = sessions(["one", "two", "three"])
        let two = Array(three.prefix(2))

        _ = memo.proposals(sessions: three, dismissed: [], compute: counter.compute)
        _ = memo.proposals(sessions: two, dismissed: [], compute: counter.compute)

        #expect(counter.calls == 2, "a session left the bench and the memo kept the old proposals")
    }

    /// *Not together* is the other input `propose` reads. Dismissing a cluster
    /// must produce a fresh pass, or the proposal the user just rejected keeps
    /// being drawn — F44's posture, defeated by a cache.
    @Test
    func aDismissalInvalidatesTheMemo() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let bench = sessions(["Sparrow Quarry north face", "Leaving Sparrow Quarry"])

        _ = memo.proposals(sessions: bench, dismissed: [], compute: counter.compute)
        _ = memo.proposals(
            sessions: bench,
            dismissed: [ClusterFingerprint(rawValue: "abc")],
            compute: counter.compute
        )

        #expect(counter.calls == 2, "a cluster was dismissed and the memo kept proposing it")
    }

    /// Order matters to the proposer (its dedup is greedy in strength order and
    /// its identity is positional — `ea5d41a`), so a reordered bench is a
    /// different input even with identical membership.
    @Test
    func reorderedSessionsInvalidateTheMemo() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()
        let bench = sessions(["one", "two"])

        _ = memo.proposals(sessions: bench, dismissed: [], compute: counter.compute)
        _ = memo.proposals(sessions: bench.reversed(), dismissed: [], compute: counter.compute)

        #expect(counter.calls == 2, "the bench reordered and the memo reused proposals built from the old order")
    }

    /// The first call can never be a hit — a memo that reports one has an
    /// uninitialised-state bug.
    @Test
    func theFirstCallIsAlwaysAMiss() {
        var memo = BenchProposalMemo()
        let counter = ComputeCounter()

        _ = memo.proposals(sessions: sessions(["only"]), dismissed: [], compute: counter.compute)

        #expect(counter.calls == 1)
        #expect(!memo.lastCallWasHit, "the very first call reported itself as a cache hit")
    }
}

/// **B23 · the caller guard — does the bench actually consult the memo?**
///
/// `BenchProposalMemoTests` proves the memo is correct. It proves nothing about
/// whether `composeDrawnBench` routes through it, and CLAUDE.md § *Guard the
/// Caller, Not Just the Owner* exists because this project shipped that exact
/// gap three times in one pass — most sharply T2.6, where deleting the
/// `isTransferReady` guard left all six of its tests green.
///
/// The call site is a `private func` on a SwiftUI `View` that reads
/// `@State`, an `@ObservedObject` manifest and a Core Data context. There is no
/// behavioural seam a test can reach without standing up the whole surface, so
/// a **mechanical source assertion** is the honest instrument here — anchored
/// on the real file, self-tested against a known offending shape, and throwing
/// if the walk reaches no source so it can never pass by matching nothing.
struct BenchProposalCallerGuardTests {

    /// The bench must reach the proposer **through** the memo.
    ///
    /// Red if someone adds a second, direct `ClipClusterProposer.propose(` call
    /// to the composition — which is how a memo becomes a complete, tested,
    /// never-consulted value (the `UnifiedBenchGrouper` / `MediaBlobOrphanSweep`
    /// shape this codebase has paid for twice).
    @Test func theBenchReachesTheProposerThroughTheMemo() throws {
        let source = try Self.sessionListSource()

        #expect(
            source.contains("proposalMemo.proposals("),
            "`composeDrawnBench` no longer consults `BenchProposalMemo`. B23's redundant NLTagger passes are back, and every memo test still passes."
        )

        let directCalls = Self.proposeCallSites(in: source)
        #expect(
            directCalls.count == 1,
            """
            Expected exactly one `ClipClusterProposer.propose(` call in SessionListView \
            — the one inside the memo's `compute` closure — but found \(directCalls.count) \
            at lines \(directCalls).

            A second call site bypasses the memo. Route it through \
            `proposalMemo.proposals(sessions:dismissed:compute:)`.
            """
        )
    }

    /// **Guards the guard.** A matcher that recognises nothing reports a clean
    /// codebase forever — the `loudPeakThenSilence` failure, and the set-aside
    /// scanner that passed its own mutation by splitting source on `"/// "`.
    @Test func theScannerSeesCallsAndIgnoresProse() {
        let withTwo = """
        let a = ClipClusterProposer.propose(sessions: x, dismissed: y, trace: t)
        let b = ClipClusterProposer.propose(sessions: p, dismissed: q, trace: nil)
        """
        #expect(Self.proposeCallSites(in: withTwo).count == 2, "the scanner must see two real call sites")

        #expect(
            Self.proposeCallSites(in: "/// `ClipClusterProposer.propose(` is memoized — see B23").isEmpty,
            "a doc comment naming the call is not a call site"
        )
        #expect(
            Self.proposeCallSites(in: "        // let x = ClipClusterProposer.propose(sessions: s)").isEmpty,
            "a commented-out call is not a call site"
        )
        #expect(
            Self.proposeCallSites(in: "let p = proposalMemo.proposals(sessions: s, dismissed: d)").isEmpty,
            "the memo call is not itself a direct proposer call"
        )
    }

    // MARK: - Scanner

    /// Line numbers of genuine `ClipClusterProposer.propose(` call sites,
    /// ignoring comments. Scoped to *this* question deliberately — a broader
    /// "find every proposer call" scan would flag the proposer's own suites.
    static func proposeCallSites(in source: String) -> [Int] {
        source.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return nil }
            return line.contains("ClipClusterProposer.propose(") ? index + 1 : nil
        }
    }

    /// **Throws rather than returning empty if the anchor moves.** A walk that
    /// silently reaches no source is a guard reporting success by failing to
    /// look.
    static func sessionListSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // …/MemoryStreamTests
            .deletingLastPathComponent()   // …/MemoryStream (project dir)
            .appendingPathComponent("MemoryStream/Views/Inbox/SessionListView.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8), !source.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return source
    }

    enum Failure: Error { case sourceNotFound(String) }
}
