import Testing
import Foundation
@testable import HiMem

/// P0 money tests — `ClipGroup` change-detection (`Handoff · carry-forward
/// punch list · 2026-07-14`).
///
/// The bug: deleting a clip inside an on-a-roll session left the session
/// still showing every clip, both waveform badges stuck at the old count,
/// and the deleted clip's row still tappable (opening a blank detail that
/// self-dismissed). Root cause: `ClipGroup`'s `==`/`hash` were defined on
/// `id` ONLY, and `id` is the `rollGroupId` — stable no matter how many
/// clips remain. So a 3-clip group and a 2-clip group with the same
/// `rollGroupId` compared **equal**, and SwiftUI (which uses
/// `Equatable`/`Hashable` for change-detection and `navigationDestination`
/// identity) treated the post-delete group as unchanged and skipped the
/// re-render. The header escaped because it reads `InboxManifest.count`
/// directly, bypassing `ClipGroup`.
///
/// The fix decouples identity from equality: `id` stays `rollGroupId`
/// (stable → `ForEach` row identity survives a delete), but `==`/`hash`
/// reflect **membership** so a changed session is seen as changed.
/// Same disease/cure as `EntryDisplayModel` (`DisplayModels.swift`).
struct ClipGroupEqualityTests {

    private func makeClip(rollGroupId: UUID?) -> InboxClip {
        let id = UUID()
        return InboxClip(
            clipId: id,
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(id.uuidString).caf",
            rollGroupId: rollGroupId
        )
    }

    /// The money assertion. Two groups sharing a `rollGroupId` but with
    /// different membership must be **unequal** — different state. Before
    /// the fix, id-only `==` declared them equal, which is what made
    /// SwiftUI skip the re-render.
    @Test func sameRollGroup_differentMembership_areNotEqual() {
        let rg = UUID()
        let c1 = makeClip(rollGroupId: rg)
        let c2 = makeClip(rollGroupId: rg)
        let c3 = makeClip(rollGroupId: rg)

        let three = ClipGroup(clips: [c1, c2, c3])
        let two = ClipGroup(clips: [c2, c3])

        // Identity is deliberately stable — `ForEach` row identity must
        // survive the delete (no glitchy row re-creation).
        #expect(three.id == two.id, "id must remain the stable rollGroupId")
        // …but the groups are different states and must compare unequal.
        #expect(three != two, "different membership must not be equal")
    }

    /// Contract: equal membership ⟹ equal groups ⟹ equal hashes. Locks the
    /// `Hashable` invariant so the change to `==`/`hash` stays consistent.
    @Test func sameMembership_areEqual_withEqualHashes() {
        let c1 = makeClip(rollGroupId: nil)
        let a = ClipGroup(clips: [c1])
        let b = ClipGroup(clips: [c1])

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    /// A single-clip group's identity falls back to the clipId when there's
    /// no rollGroupId — and removing that clip yields a different group.
    @Test func soloClip_identityIsClipId_membershipStillDrivesEquality() {
        let c1 = makeClip(rollGroupId: nil)
        let c2 = makeClip(rollGroupId: nil)
        let group = ClipGroup(clips: [c1])

        #expect(group.id == c1.clipId)
        #expect(group != ClipGroup(clips: [c2]))
    }

    // MARK: - An identity must be a function of its content

    /// **The 2026-08-09 Clips freeze, as an assertion.**
    ///
    /// `id` fell back to `?? UUID()` when `clips` was empty, so reading it
    /// twice gave two different answers. `ForEach` reads identity repeatedly;
    /// an id that changes per read means SwiftUI can never converge on a diff,
    /// and the screen wedged — with a 0.4ms render over a 47-item bench, so it
    /// never looked like cost. A stable sentinel closed it alone.
    ///
    /// This is the money test: it fails on the exact expression that shipped.
    @Test func anEmptyGroupsIdentityIsStableAcrossReads() {
        let empty = ClipGroup(clips: [])
        #expect(empty.id == empty.id,
                """
                `ClipGroup.id` returns a different value on each read for an empty group. \
                SwiftUI's ForEach re-reads identity, so it can never match a row to its \
                previous self and the view diffs forever.
                """)
    }

    /// Two empty groups COLLIDE on one id, deliberately. A collision renders a
    /// visibly wrong list; per-read churn renders an unkillable freeze. The
    /// first is diagnosable, the second is not — so the sentinel is the honest
    /// failure mode, not merely the convenient one.
    @Test func twoEmptyGroupsShareTheSentinelRatherThanInventingIds() {
        #expect(ClipGroup(clips: []).id == ClipGroup(clips: []).id)
        #expect(ClipGroup(clips: []).id == ClipGroup.emptyGroupId)
    }

    /// The sentinel must not collide with a real group's identity — otherwise
    /// it would swap a freeze for a row that impersonates a session.
    @Test func theSentinelCannotBeMistakenForARealGroup() {
        let clip = makeClip(rollGroupId: nil)
        #expect(ClipGroup(clips: [clip]).id != ClipGroup.emptyGroupId)
    }
}
