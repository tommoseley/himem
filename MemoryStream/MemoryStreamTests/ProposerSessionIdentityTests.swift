import Testing
import Foundation
@testable import HiMem

/// **The proposer identifies sessions POSITIONALLY, never by `ClipGroup.id`.**
///
/// True by construction today — `proposeWordMatch` builds
/// `sessionIndices: Set<Int>` and maps back with `sessions[$0]`, and the file
/// contains no read of `.id` at all — and, until this suite, completely
/// untested. *True by construction and untested* is exactly the gap that lets a
/// later edit reintroduce B25 one layer over.
///
/// **Why this property and not a filter.** C2 step 4 slice C's device pass saw
/// `[ClusterTrace] s9 · clips=0` — a media-only sitting reaching the proposer,
/// which projects to an empty `ClipGroup` whose id is the fixed
/// `emptyGroupId` sentinel. The tempting response was to filter zero-clip
/// sessions out before grouping. That was withdrawn (Tom, 2026-08-19): a
/// media-only sitting is a real bench state, and filtering it would hide the
/// very shape B25 lived in while changing behaviour on suspicion — the B22
/// pattern. The thing actually worth protecting is the invariant that makes the
/// sentinel harmless here, so it is pinned instead of worked around.
///
/// **`ClipGroup.id` collides in two ways, and both are exercised below:**
///  * every voiceless session shares `emptyGroupId` (B25's shape), and
///  * two sessions whose first clips share a `rollGroupId` share that id —
///    which is ordinary, not pathological: a split roll does it.
///
/// If identity ever became the id, the second case silently MERGES two real
/// sittings and a cluster quietly loses a clip. That is the failure this suite
/// exists to make loud.
///
/// Uses `StubEntityExtractor` because NLTagger is unreliable on the iOS 26
/// simulator (memory: `feedback_nltagger_simulator`).
@Suite(.serialized)
struct ProposerSessionIdentityTests {

    private func clip(
        at time: Date,
        transcript: String,
        rollGroupId: UUID? = nil
    ) -> InboxClip {
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
            rollGroupId: rollGroupId
        )
    }

    private final class StubEntityExtractor: EntityExtractor {
        var entitiesForText: [String: [LocalEntityExtractor.LocalEntity]] = [:]
        var defaultEntities: [LocalEntityExtractor.LocalEntity] = []
        func extractEntities(from text: String) -> LocalEntityExtractor.LocalResult {
            LocalEntityExtractor.LocalResult(
                entities: entitiesForText[text] ?? defaultEntities
            )
        }
    }

    private func entity(_ value: String) -> LocalEntityExtractor.LocalEntity {
        LocalEntityExtractor.LocalEntity(
            type: .project,
            value: value,
            confidence: 0.9,
            range: "".startIndex..<"".startIndex
        )
    }

    /// **Two sittings that share a `ClipGroup.id` must stay two sittings.**
    ///
    /// The money test for the property. Three sessions share "Harbor Lantern";
    /// the first two share a `rollGroupId`, so `ClipGroup.id` — which reads
    /// `clips.first?.rollGroupId` — is the SAME value for both. Keying identity
    /// off that id would fold them into one and the proposal would carry two
    /// clips instead of three: a clip silently missing from a cluster the user
    /// is being asked to accept.
    @Test
    func twoSessionsSharingAClipGroupIdAreStillTwoSessions() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let roll = UUID()
        let t1 = "Walking past Harbor Lantern before the tide turned"
        let t2 = "Second pass by Harbor Lantern, quieter now"
        let t3 = "Last look at Harbor Lantern on the way back"

        // The first two take the same rollGroupId — an ordinary split roll.
        let s1 = ClipGroup(clips: [clip(at: base, transcript: t1, rollGroupId: roll)])
        let s2 = ClipGroup(clips: [clip(at: base.addingTimeInterval(1800), transcript: t2, rollGroupId: roll)])
        let s3 = ClipGroup(clips: [clip(at: base.addingTimeInterval(3600), transcript: t3)])

        // **Precondition — the collision is real.** Without this the test could
        // pass by the ids simply differing, proving nothing about identity.
        #expect(s1.id == s2.id, "fixture must actually collide, or this suite guards nothing")
        #expect(s1.id != s3.id)

        let stub = StubEntityExtractor()
        for t in [t1, t2, t3] { stub.entitiesForText[t] = [entity("Harbor Lantern")] }

        let proposals = ClipClusterProposer.proposeWordMatch(sessions: [s1, s2, s3], entityExtractor: stub)

        #expect(proposals.count == 1)
        #expect(
            proposals.first?.clipIds.count == 3,
            "all three sittings must reach the proposal — two of them share a ClipGroup.id, and identity by that id would merge them and drop a clip from a cluster the user is asked to accept"
        )
        // Named individually, so a count that happens to be 3 for another
        // reason cannot pass this.
        let claimed = Set(proposals.first?.clipIds ?? [])
        for session in [s1, s2, s3] {
            #expect(claimed.contains(session.clips[0].clipId))
        }
    }

    /// **A zero-clip session reaching the proposer is inert** — the exact
    /// device observation (`s9 · clips=0`) that prompted this suite.
    ///
    /// Two of them, so they share `emptyGroupId` with each other as well as
    /// carrying it at all: if identity were the id, a pair of media-only
    /// sittings would be one "session" and could displace or merge the real
    /// ones around them.
    @Test
    func voicelessSessionsShareTheSentinelIdAndChangeNothing() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = "Notes from Sparrow Quarry, north face in shadow"
        let t2 = "More from Sparrow Quarry after the climb"

        let s1 = ClipGroup(clips: [clip(at: base, transcript: t1)])
        let s2 = ClipGroup(clips: [clip(at: base.addingTimeInterval(1800), transcript: t2)])
        let empty1 = ClipGroup(clips: [])
        let empty2 = ClipGroup(clips: [])

        // The B25 shape, stated: every voiceless session is the same id.
        #expect(empty1.id == ClipGroup.emptyGroupId)
        #expect(empty1.id == empty2.id, "this collision is the sentinel's known cost — it must stay harmless HERE")

        let stub = StubEntityExtractor()
        stub.entitiesForText[t1] = [entity("Sparrow Quarry")]
        stub.entitiesForText[t2] = [entity("Sparrow Quarry")]

        let withEmpties = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, empty1, s2, empty2],
            entityExtractor: stub
        )
        let without = ClipClusterProposer.proposeWordMatch(
            sessions: [s1, s2],
            entityExtractor: stub
        )

        #expect(withEmpties.count == 1)
        #expect(
            withEmpties.first?.clipIds == without.first?.clipIds,
            "interleaving two sentinel-id sessions must not change which clips are claimed"
        )
        #expect(withEmpties.first?.proposedName == without.first?.proposedName,
                "nor which token names the cluster")
    }
}
