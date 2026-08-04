import Testing
import Foundation
@testable import HiMem

/// Money tests for `UnifiedBenchGrouper` — the July 11 2026 fix that
/// makes idle-gap sessioning media-agnostic, per
/// `Captured Clips · session-first · spec.md` §Model:
///
/// > A *clip* is one captured fragment — media-agnostic (locked July
/// > 11 2026). Not audio-only. Each clip carries a capture timestamp
/// > and a source glyph; type is per-clip metadata, never a reason
/// > to segregate it. The rule groups by timestamp, not by media
/// > type — a photo and a voice clip two minutes apart are *one
/// > sitting*, so they land in one session card together (a mixed
/// > "3 clips" card, not a voice card plus a stray photo row).
///
/// The bug this retires: pre-July 11, voice clips grouped into
/// `SessionListView` cards while photo/video `MediaReference` rows
/// floated separately above them in an `unplacedDayGroupedStack`.
/// A photo captured 2 minutes after a voice clip appeared above the
/// voice's session card instead of *inside* it. Dogfood, July 11:
/// "a photo at 10:34 floated above the voice-only '2 clips' session
/// it belonged to by time."
@Suite(.serialized)
struct UnifiedBenchGrouperTests {

    /// Voice + photo within the idle window (10min) become one
    /// mixed session — the primary July 11 lock.
    @Test func voice_and_photo_within_window_form_one_session() {
        let base = Date()
        let voice = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        let photo = BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(120), rollGroupId: nil)
        let sessions = UnifiedBenchGrouper.group([voice, photo])
        #expect(sessions.count == 1)
        #expect(sessions[0].items.count == 2)
        #expect(sessions[0].hasVoice)
        #expect(sessions[0].hasMedia)
    }

    /// Voice + photo separated by more than the idle threshold split
    /// into two sessions.
    @Test func voice_and_photo_across_gap_split() {
        let base = Date()
        let voice = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        // 15 minutes > 10-min idle threshold
        let photo = BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(15 * 60), rollGroupId: nil)
        let sessions = UnifiedBenchGrouper.group([voice, photo])
        #expect(sessions.count == 2)
    }

    /// A lone photo (no siblings inside the window) forms its own
    /// single-item session — same shape as a single-clip voice
    /// session. Preserves the "no regression for N=1" invariant
    /// from spec § Model.
    @Test func lone_photo_forms_singleton_session() {
        let photo = BenchClipItem(id: UUID(), kind: .image, capturedAt: Date(), rollGroupId: nil)
        let sessions = UnifiedBenchGrouper.group([photo])
        #expect(sessions.count == 1)
        #expect(sessions[0].items.count == 1)
        #expect(sessions[0].hasMedia)
        #expect(!sessions[0].hasVoice)
    }

    /// Three-clip mixed sitting: voice → photo → voice, all within
    /// the window. Matches the `ScrMixedSession` reference frame in
    /// `screens-clips-page.jsx`.
    @Test func three_way_mixed_sitting_stays_one_session() {
        let base = Date()
        let items = [
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(128), rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(180), rollGroupId: nil),
        ]
        let sessions = UnifiedBenchGrouper.group(items)
        #expect(sessions.count == 1)
        #expect(sessions[0].items.count == 3)
        #expect(sessions[0].hasVoice)
        #expect(sessions[0].hasMedia)
    }

    /// Sessions are returned newest-first (matches
    /// `ClipSessionGrouper.group` ordering — the bench list is
    /// reverse-chronological).
    @Test func sessions_are_newest_first() {
        let base = Date()
        let older = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(-3600), rollGroupId: nil)
        let newer = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        let sessions = UnifiedBenchGrouper.group([older, newer])
        #expect(sessions.count == 2)
        #expect(sessions[0].capturedAt > sessions[1].capturedAt)
    }

    /// Items inside a session are sorted oldest-first — the reader
    /// wants to see the sitting unfold in chronological order.
    /// Different from the session ordering (newest-first at the top
    /// level).
    @Test func items_within_session_are_oldest_first() {
        let base = Date()
        let items = [
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(180), rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(60), rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil),
        ]
        let sessions = UnifiedBenchGrouper.group(items)
        #expect(sessions.count == 1)
        let session = sessions[0]
        let times = session.items.map(\.capturedAt)
        #expect(times == times.sorted())
    }

    /// rollGroupId still binds a declared roll together across gaps
    /// wider than the idle threshold — parity with the voice-only
    /// grouper's rollGroupId short-circuit.
    @Test func shared_rollGroupId_binds_across_gap() {
        let base = Date()
        let rollId = UUID()
        let clip1 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: rollId)
        // 30-min gap, way past idle threshold — but same roll
        let clip2 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(30 * 60), rollGroupId: rollId)
        let sessions = UnifiedBenchGrouper.group([clip1, clip2])
        #expect(sessions.count == 1)
        #expect(sessions[0].items.count == 2)
    }

    /// Different rollGroupIds don't force a split when the clips are
    /// otherwise idle-adjacent — matches the voice-only grouper.
    /// Two wrist-raises 4 min apart are one sitting even though each
    /// carries its own auto-generated rollGroupId.
    @Test func different_rollGroupIds_do_not_force_split_when_idle_adjacent() {
        let base = Date()
        let clip1 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: UUID())
        let clip2 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(4 * 60), rollGroupId: UUID())
        let sessions = UnifiedBenchGrouper.group([clip1, clip2])
        #expect(sessions.count == 1)
    }

    /// Empty input → empty result.
    @Test func empty_input_returns_empty() {
        #expect(UnifiedBenchGrouper.group([]).isEmpty)
    }

    // MARK: - Removed from session (C2 step 2b-i, 2026-08-03)
    //
    // `ClipSessionGrouper` has carried `soloClipIds` since the July 12 2026
    // "Clip triage" lock; this grouper replaces it on the bench, so without
    // these the rebuild would retire the triage in silence. The semantics
    // are deliberately identical to `ClipSessionGrouperSoloTests` — a solo
    // item becomes its own single-item session, and the items around it
    // still session together ACROSS it, so pulling a stray out of the
    // middle of a sitting does not split the survivors.
    //
    // Mutation-verified: deleting the `soloIds.contains` branch collapses
    // `solo_item_splits_out_while_survivors_stay_together` to one session.

    /// Baseline — the default path is untouched. Guards against "solo
    /// support" quietly changing grouping for every caller that has none.
    @Test func no_solo_ids_groups_exactly_as_before() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        let items = [
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(120), rollGroupId: nil),
            BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(240), rollGroupId: nil),
        ]
        #expect(UnifiedBenchGrouper.group(items) == UnifiedBenchGrouper.group(items, soloIds: []))
        #expect(UnifiedBenchGrouper.group(items).count == 1)
    }

    /// The money case, and it is MIXED-KIND on purpose: the item pulled out
    /// is the photo, so the parameter cannot be satisfied by a voice-only
    /// code path (the exact blind spot the whole rebuild exists to close).
    @Test func solo_item_splits_out_while_survivors_stay_together() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        let voiceA = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        let photo  = BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(120), rollGroupId: nil)
        let voiceB = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(240), rollGroupId: nil)

        #expect(UnifiedBenchGrouper.group([voiceA, photo, voiceB]).count == 1)

        let sessions = UnifiedBenchGrouper.group([voiceA, photo, voiceB], soloIds: [photo.id])
        #expect(sessions.count == 2)
        let survivors = sessions.first { $0.items.count > 1 }
        let solo = sessions.first { $0.items.count == 1 }
        #expect(survivors?.items.map(\.id) == [voiceA.id, voiceB.id],
                "the survivors did not session together across the removed item")
        #expect(solo?.items.first?.id == photo.id)
    }

    /// A solo lands at its own time position, not at the end of the list —
    /// the bench stays reverse-chronological.
    @Test func a_solo_session_keeps_its_place_in_the_bench_order() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        let old   = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        let mid   = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(120), rollGroupId: nil)
        let newer = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(240), rollGroupId: nil)
        let sessions = UnifiedBenchGrouper.group([old, mid, newer], soloIds: [mid.id])
        #expect(sessions.count == 2)
        // Sessions are newest-first: the survivors reach t+240, the solo t+120.
        #expect(sessions[0].items.contains(where: { $0.id == newer.id }))
        #expect(sessions[1].items.map(\.id) == [mid.id])
    }

    /// Marking one item solo must not reshape a DIFFERENT sitting — that
    /// would be surprising, and it is the shape a naive "regroup everything
    /// around the solo" implementation produces.
    @Test func a_solo_does_not_reshape_another_sitting() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        let a1 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: nil)
        let a2 = BenchClipItem(id: UUID(), kind: .image, capturedAt: base.addingTimeInterval(60), rollGroupId: nil)
        let b1 = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(30 * 60), rollGroupId: nil)
        let b2 = BenchClipItem(id: UUID(), kind: .note,  capturedAt: base.addingTimeInterval(30 * 60 + 60), rollGroupId: nil)
        #expect(UnifiedBenchGrouper.group([a1, a2, b1, b2]).count == 2)

        let sessions = UnifiedBenchGrouper.group([a1, a2, b1, b2], soloIds: [a2.id])
        #expect(sessions.count == 3)
        // The far sitting is untouched: still one session of exactly b1 + b2.
        #expect(sessions.contains { $0.items.map(\.id) == [b1.id, b2.id] })
    }

    /// A solo beats a declared roll. `rollGroupId` binds a roll across any
    /// gap, so if the solo branch ran after the roll short-circuit the user
    /// could not pull one clip out of a roll at all — and "Removed from
    /// session" is exactly the escape hatch for a roll she over-declared.
    @Test func a_solo_overrides_a_shared_rollGroupId() {
        let base = Date(timeIntervalSince1970: 1_785_000_000)
        let roll = UUID()
        let a = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base, rollGroupId: roll)
        let b = BenchClipItem(id: UUID(), kind: .voice, capturedAt: base.addingTimeInterval(60), rollGroupId: roll)
        #expect(UnifiedBenchGrouper.group([a, b]).count == 1)
        let sessions = UnifiedBenchGrouper.group([a, b], soloIds: [b.id])
        #expect(sessions.count == 2, "a declared roll swallowed the removed item")
    }
}
