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
}
