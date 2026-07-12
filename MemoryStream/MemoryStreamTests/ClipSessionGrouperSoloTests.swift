import Testing
import Foundation
@testable import HiMem

/// Money tests for `Clip model · spec.md` § "Clip triage" July 12 2026
/// — the operational *Remove from session* fate action.
///
/// > A clip the user has Removed from a session **survives as a
/// > loose clip on the bench, un-grouped from the cluster it was
/// > pulled out of**. […] Removal is a structural edit; it survives
/// > across app launches.
///
/// The grouper (`ClipSessionGrouper.group`) implements the "un-grouped
/// from the cluster" half by pulling `soloClipIds` out of the idle-gap
/// walk and emitting each as its own single-clip group. Its default-
/// empty parameter preserves the pre-July-12 behaviour for every
/// existing callsite.
///
/// **What the pre-change grouper did:** three clips within the 10-min
/// idle window formed one three-clip group, always. There was no way
/// to eject the middle clip without deleting it. The dogfood pain the
/// user reported: "I have three clips from one sitting, one of them
/// is unrelated — I want to keep both the sitting and the stray, but
/// separate them." Delete-and-lose-transcript was the only option.
///
/// **What this test locks:** with the middle clip's id in
/// `soloClipIds`, the newer and older clips still session together
/// across the removed one (the idle-gap boundary is unchanged for
/// the survivors), and the solo clip becomes its own newest-second-
/// oldest-third card at its own time position on the bench.
@Suite(.serialized)
struct ClipSessionGrouperSoloTests {

    // MARK: - Fixture

    private func clip(at captured: Date) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: captured,
            duration: 10,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "x.caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
    }

    // MARK: - Baseline (default-empty solo set) — no regression

    @Test func three_clips_within_window_still_form_one_group_by_default() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let a = clip(at: base)                             // oldest
        let b = clip(at: base.addingTimeInterval(120))     // middle
        let c = clip(at: base.addingTimeInterval(240))     // newest
        let groups = ClipSessionGrouper.group([a, b, c])
        #expect(groups.count == 1)
        #expect(groups[0].clips.count == 3)
    }

    // MARK: - Money test — solo middle clip splits into two groups

    @Test func middle_clip_marked_solo_splits_into_two_groups() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let a = clip(at: base)                             // oldest
        let b = clip(at: base.addingTimeInterval(120))     // middle
        let c = clip(at: base.addingTimeInterval(240))     // newest
        let groups = ClipSessionGrouper.group(
            [a, b, c],
            soloClipIds: [b.clipId]
        )
        // Expected outcome:
        //   - one regular group containing a + c (idle window still
        //     ≤ 10 min between them: 240s apart, well under 600s),
        //   - one solo group containing only b.
        // The middle-clip Remove pulls b out but leaves the sitting
        // it was in intact around it.
        #expect(groups.count == 2)
        let regular = groups.first { $0.clips.count > 1 }
        let solo = groups.first { $0.clips.count == 1 }
        #expect(regular != nil)
        #expect(solo != nil)
        #expect(regular?.clips.contains(where: { $0.clipId == a.clipId }) == true)
        #expect(regular?.clips.contains(where: { $0.clipId == c.clipId }) == true)
        #expect(solo?.clips.first?.clipId == b.clipId)
    }

    // MARK: - Ordering — bench stays reverse-chronological

    @Test func groups_after_solo_split_stay_newest_first() {
        // Solo at t=120 sits between clip at t=0 and clip at t=240.
        // The regular group's newest clip is c (t=240); the solo's is
        // b (t=120). Bench should list the c-containing group first.
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let a = clip(at: base)
        let b = clip(at: base.addingTimeInterval(120))
        let c = clip(at: base.addingTimeInterval(240))
        let groups = ClipSessionGrouper.group(
            [a, b, c],
            soloClipIds: [b.clipId]
        )
        #expect(groups.count == 2)
        // Group 0 is newest-first (contains c at t=240).
        #expect(groups[0].clips.contains(where: { $0.clipId == c.clipId }))
        // Group 1 is the solo (t=120).
        #expect(groups[1].clips.first?.clipId == b.clipId)
    }

    // MARK: - Solo across an idle boundary — still lands as its own group

    @Test func solo_across_idle_gap_stays_its_own_group() {
        // Two natural sittings (30 min apart) split without any solo
        // hint. Marking one clip solo shouldn't change the OTHER
        // sitting's shape — that would be surprising to the user.
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let a1 = clip(at: base)
        let a2 = clip(at: base.addingTimeInterval(60))
        let b1 = clip(at: base.addingTimeInterval(30 * 60))       // new sitting
        let b2 = clip(at: base.addingTimeInterval(30 * 60 + 60))
        // Baseline: 2 groups of 2.
        #expect(ClipSessionGrouper.group([a1, a2, b1, b2]).count == 2)
        // Mark a2 solo — sitting 1 becomes 2 groups; sitting 2 stays 1.
        let groups = ClipSessionGrouper.group(
            [a1, a2, b1, b2],
            soloClipIds: [a2.clipId]
        )
        #expect(groups.count == 3)
    }
}
