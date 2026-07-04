import Testing
import Foundation
@testable import HiMem

/// PR 1 of the "On a roll" implementation (`docs/design/on-a-roll-spec.md`).
/// Tests the pure decision layer (MinClipDebouncer) and the
/// cross-platform coordinator (NextClipController) — the actual audio
/// handoff is platform-specific and lands in PRs 3–5.
@MainActor
@Suite(.serialized)
struct OnARollTests {

    // MARK: - MinClipDebouncer

    @Test func debounce_underTwoSecondsSinceSessionStart_blocks() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let now = start.addingTimeInterval(1.5)
        #expect(MinClipDebouncer.shouldFire(sessionStart: start, lastNextAt: nil, now: now) == false)
    }

    @Test func debounce_atExactlyTwoSeconds_fires() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let now = start.addingTimeInterval(2.0)
        #expect(MinClipDebouncer.shouldFire(sessionStart: start, lastNextAt: nil, now: now) == true)
    }

    @Test func debounce_overTwoSeconds_fires() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let now = start.addingTimeInterval(5.0)
        #expect(MinClipDebouncer.shouldFire(sessionStart: start, lastNextAt: nil, now: now) == true)
    }

    @Test func debounce_lastNextAt_takesPriorityOverSessionStart() {
        // Session started 10s ago, but last Next was 1s ago → block.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let lastNext = start.addingTimeInterval(9.0)
        let now = start.addingTimeInterval(10.0)
        #expect(MinClipDebouncer.shouldFire(sessionStart: start, lastNextAt: lastNext, now: now) == false)
    }

    @Test func debounce_lastNextAt_threeSecondsAgo_fires() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let lastNext = start.addingTimeInterval(5.0)
        let now = start.addingTimeInterval(8.0)
        #expect(MinClipDebouncer.shouldFire(sessionStart: start, lastNextAt: lastNext, now: now) == true)
    }

    // MARK: - NextClipController state machine

    /// Test double that records handoff invocations. Lets us assert
    /// without driving a real audio recorder.
    @MainActor
    final class RecordingHandoffSpy: RecordingHandoff {
        struct Call: Equatable {
            let rollGroupId: UUID
            let newClipIndex: Int
        }
        private(set) var calls: [Call] = []
        func handoffToNewClip(rollGroupId: UUID, newClipIndex: Int) {
            calls.append(Call(rollGroupId: rollGroupId, newClipIndex: newClipIndex))
        }
    }

    @Test func controller_freshSession_startsAtClip1() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        controller.sessionDidStart()
        #expect(controller.currentClipIndex == 1)
        #expect(controller.lastNextAt == nil)
        #expect(controller.rollGroupId != nil)
    }

    @Test func controller_nextTap_belowDebounce_doesNothing() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)

        let fired = controller.handleNextTap(now: start.addingTimeInterval(1.0))

        #expect(fired == false)
        #expect(controller.currentClipIndex == 1)
        #expect(controller.lastNextAt == nil)
        #expect(spy.calls.isEmpty)
    }

    @Test func controller_nextTap_aboveDebounce_invokesHandoff() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)

        let firedAt = start.addingTimeInterval(3.0)
        let fired = controller.handleNextTap(now: firedAt)

        #expect(fired == true)
        #expect(controller.currentClipIndex == 2)
        #expect(controller.lastNextAt == firedAt)
        #expect(spy.calls.count == 1)
        #expect(spy.calls.first?.newClipIndex == 2)
    }

    @Test func controller_consecutiveNextTaps_incrementClipIndex() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)

        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))
        _ = controller.handleNextTap(now: start.addingTimeInterval(7.0))
        _ = controller.handleNextTap(now: start.addingTimeInterval(11.0))

        #expect(controller.currentClipIndex == 4)
        #expect(spy.calls.count == 3)
        #expect(spy.calls.map(\.newClipIndex) == [2, 3, 4])
    }

    @Test func controller_rollGroupId_stableAcrossNextTaps() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        let initialId = try? #require(controller.rollGroupId)

        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))
        _ = controller.handleNextTap(now: start.addingTimeInterval(7.0))

        #expect(controller.rollGroupId == initialId)
        #expect(spy.calls.allSatisfy { $0.rollGroupId == initialId })
    }

    @Test func controller_sessionEnd_clearsState() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))

        controller.sessionDidEnd()

        #expect(controller.currentClipIndex == 1)
        #expect(controller.lastNextAt == nil)
        #expect(controller.rollGroupId == nil)
    }

    @Test func controller_nextTap_outsideSession_ignored() {
        // No sessionDidStart() called → tap is a no-op (defensive).
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)

        let fired = controller.handleNextTap()

        #expect(fired == false)
        #expect(spy.calls.isEmpty)
    }

    @Test func controller_capTriggeredHandoff_fires_evenIfDebounceWouldBlock() {
        // 5-min cap auto-Next: spec says cap is the validation, no
        // debounce check applies.
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)

        // Just 0.5s in — would normally debounce-block.
        controller.handleCapTriggeredHandoff(now: start.addingTimeInterval(0.5))

        #expect(controller.currentClipIndex == 2)
        #expect(spy.calls.count == 1)
    }

    @Test func controller_handoff_carriesCurrentRollGroupId() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        let expectedId = controller.rollGroupId

        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))

        #expect(spy.calls.first?.rollGroupId == expectedId)
    }

    /// Eyebrow visibility flips true on a successful Next tap.
    /// The 1.5s timer is on a Task we don't await here — we just
    /// confirm the flag flips.
    @Test func controller_successfulTap_showsRollingEyebrow() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        #expect(controller.rollingEyebrowVisible == false)

        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))

        #expect(controller.rollingEyebrowVisible == true)
    }

    // MARK: - Inbox grouping precedence (PR 2)

    private func clip(
        captured: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        rollGroupId: UUID? = nil
    ) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: captured,
            duration: 10,
            transcript: "",
            latitude: latitude,
            longitude: longitude,
            source: "watch",
            audioFilename: "x.caf",
            transcriptionAttempted: true,
            rollGroupId: rollGroupId
        )
    }

    @Test func sameSession_sameRollGroupId_groups_regardlessOfTimeOrLocation() {
        let rollId = UUID()
        // Same rollId, very different times, very different locations
        // (~5000m apart over 2 hours) — still one session.
        let a = clip(captured: Date(timeIntervalSinceReferenceDate: 0),
                     latitude: 33.0, longitude: -117.0, rollGroupId: rollId)
        let b = clip(captured: Date(timeIntervalSinceReferenceDate: 7200),
                     latitude: 33.05, longitude: -117.05, rollGroupId: rollId)

        #expect(ClipSessionGrouper.sameSession(a, b) == true)
    }

    @Test func sameSession_differentRollGroupIds_doNotGroup() {
        // Even at the same time and place, two different rolls don't merge.
        let a = clip(captured: Date(timeIntervalSinceReferenceDate: 0),
                     latitude: 33.0, longitude: -117.0, rollGroupId: UUID())
        let b = clip(captured: Date(timeIntervalSinceReferenceDate: 1),
                     latitude: 33.0, longitude: -117.0, rollGroupId: UUID())

        #expect(ClipSessionGrouper.sameSession(a, b) == false)
    }

    @Test func sameSession_bothNilRollGroupIds_withinIdleGap_group() {
        let near = Date(timeIntervalSinceReferenceDate: 0)
        let later = near.addingTimeInterval(60)
        // v3 idle-gap: silence < 10 min → same sitting. Location is
        // not part of the base rule.
        let a = clip(captured: near, latitude: 33.0, longitude: -117.0)
        let b = clip(captured: later, latitude: 33.0, longitude: -117.0)

        #expect(ClipSessionGrouper.sameSession(a, b) == true)
    }

    @Test func sameSession_bothNilRollGroupIds_outsideTimeWindow_doNotGroup() {
        let near = Date(timeIntervalSinceReferenceDate: 0)
        let muchLater = near.addingTimeInterval(60 * 60) // 1 hr
        let a = clip(captured: near, latitude: 33.0, longitude: -117.0)
        let b = clip(captured: muchLater, latitude: 33.0, longitude: -117.0)

        #expect(ClipSessionGrouper.sameSession(a, b) == false)
    }

    @Test func sameSession_mixedNilAndNonNilRollGroupIds_doNotGroup() {
        // One clip has a rollId, the other doesn't. By the
        // rollGroupId invariant (every clip in one Record→Stop cycle
        // shares the id), they CANNOT be from the same recording.
        // Pre-2026-05-27 this fell back to time+location and merged
        // nearby clips — that produced Tom's "5.5 min apart, merged"
        // screenshot. Now mixed-nil always splits.
        let near = Date(timeIntervalSinceReferenceDate: 0)
        let later = near.addingTimeInterval(30)
        let a = clip(captured: near, latitude: 33.0, longitude: -117.0, rollGroupId: UUID())
        let b = clip(captured: later, latitude: 33.0, longitude: -117.0, rollGroupId: nil)

        #expect(ClipSessionGrouper.sameSession(a, b) == false)
    }

    /// Money test for the 2026-05-27 stacking bug. Reproduces Tom's
    /// screenshot exactly: two separate Record→Stop recordings ~5.5
    /// min apart, no location data. Before the fix: merged into one
    /// session card via the 10-min time window + mixed-nil fallback.
    /// After: split into two cards.
    @Test func sameSession_twoSeparateRecordings_doNotGroup_perScreenshotBug() {
        let firstStart = Date(timeIntervalSinceReferenceDate: 0)
        // 5 min 29 s — matches the "+329s" offset shown in the
        // grouped-session card.
        let secondStart = firstStart.addingTimeInterval(329)

        // Both clips carry their own (different) rollGroupIds — the
        // normal case when the watch generates a fresh UUID per
        // start(). Pre-fix this already split (different non-nil
        // ids), but Tom's data shows they were merging anyway, so
        // also covering the mixed-nil regression below.
        let a = clip(captured: firstStart, latitude: nil, longitude: nil, rollGroupId: UUID())
        let b = clip(captured: secondStart, latitude: nil, longitude: nil, rollGroupId: UUID())
        #expect(ClipSessionGrouper.sameSession(a, b) == false)

        // Also verify the mixed-nil regression case: one clip has a
        // rollGroupId, the other doesn't (e.g. one came in via a
        // legacy code path). Before 2026-05-27 this merged via the
        // 10-min window even at 5.5 min apart.
        let c = clip(captured: firstStart, latitude: nil, longitude: nil, rollGroupId: UUID())
        let d = clip(captured: secondStart, latitude: nil, longitude: nil, rollGroupId: nil)
        #expect(ClipSessionGrouper.sameSession(c, d) == false)

        // Both-nil-rollGroupId: under v3 idle-gap (10 min), 5.5 min
        // IS same sitting. This test used to expect a split under the
        // 3-min lock; the v3 lock intentionally trades the occasional
        // over-merge here against the frequent under-merge that hurt
        // the dinner-at-the-CIA dogfood. If two truly-separate
        // recordings without rollGroupIds land 5.5 min apart, they
        // now merge — acceptable because the modern watch always
        // stamps a rollGroupId, so both-nil is a legacy-data path.
        let e = clip(captured: firstStart, latitude: nil, longitude: nil, rollGroupId: nil)
        let f = clip(captured: secondStart, latitude: nil, longitude: nil, rollGroupId: nil)
        #expect(ClipSessionGrouper.sameSession(e, f) == true)

        // But both-nil-rollGroupId at 11 min apart — outside the
        // idle-gap window — still splits, proving the clock still
        // closes sessions.
        let elevenMinLater = firstStart.addingTimeInterval(11 * 60)
        let g = clip(captured: firstStart, latitude: nil, longitude: nil, rollGroupId: nil)
        let h = clip(captured: elevenMinLater, latitude: nil, longitude: nil, rollGroupId: nil)
        #expect(ClipSessionGrouper.sameSession(g, h) == false)
    }

    // MARK: - VoiceClipSplitter offset math (PR 4)

    @Test func splitter_noOffsets_singleRangeCoveringFullFile() {
        let ranges = VoiceClipSplitter.segmentRanges(masterDuration: 60, nextTapOffsets: [])
        #expect(ranges.count == 1)
        #expect(ranges[0].lowerBound == 0)
        #expect(ranges[0].upperBound == 60)
    }

    @Test func splitter_oneOffset_twoRangesWithOverlap() {
        // Default 200ms overlap each side. Clip 1 extends to 25.2,
        // clip 2 starts at 24.8 — both contain the word at the split.
        let ranges = VoiceClipSplitter.segmentRanges(masterDuration: 60, nextTapOffsets: [25])
        #expect(ranges.count == 2)
        #expect(ranges[0] == 0..<25.2)
        #expect(ranges[1] == 24.8..<60)
    }

    @Test func splitter_threeOffsets_overlappingFourRanges() {
        // Each interior boundary creates a 0.2s tail on the previous
        // clip and a 0.2s head on the next. First clip's start is 0;
        // last clip's end is masterDuration.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 240, nextTapOffsets: [60, 120, 180]
        )
        #expect(ranges.count == 4)
        #expect(ranges[0] == 0..<60.2)
        #expect(ranges[1] == 59.8..<120.2)
        #expect(ranges[2] == 119.8..<180.2)
        #expect(ranges[3] == 179.8..<240)
    }

    @Test func splitter_overlap_clampsToMasterDuration() {
        // Split very close to the end of the file: the trailing
        // overlap can't push past `masterDuration`. Without the
        // clamp this would produce a Range with upper > 60, which
        // segfaults the reader. Comparisons use a 1ms tolerance —
        // 59.9 - 0.2 doesn't round-trip to exactly 59.7 in Double.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 60, nextTapOffsets: [59.9]
        )
        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == 0)
        #expect(ranges[0].upperBound == 60)
        #expect(abs(ranges[1].lowerBound - 59.7) < 0.001)
        #expect(ranges[1].upperBound == 60)
    }

    @Test func splitter_overlap_clampsLeadingToZero() {
        // A split at <0.2s would push clip-2's start negative
        // without the `max(0, …)` clamp. Test the boundary directly
        // via the explicit overlap parameter, since the debouncer
        // normally makes <0.2s splits impossible in production.
        // 0.1 + 0.2 ≈ 0.30000000000000004 in Double, so compare the
        // upper bound with tolerance.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 10, nextTapOffsets: [0.1], overlap: 0.2
        )
        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == 0)
        #expect(abs(ranges[0].upperBound - 0.3) < 0.001)
        #expect(ranges[1].lowerBound == 0)
        #expect(ranges[1].upperBound == 10)
    }

    @Test func splitter_zeroOverlap_givesContiguousRanges() {
        // overlap: 0 reproduces the pre-overlap behavior — useful
        // both as a regression test for callers that turn overlap
        // off and as a sanity check on the math.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 240, nextTapOffsets: [60, 120, 180], overlap: 0
        )
        #expect(ranges.count == 4)
        #expect(ranges[0] == 0..<60)
        #expect(ranges[1] == 60..<120)
        #expect(ranges[2] == 120..<180)
        #expect(ranges[3] == 180..<240)
    }

    @Test func splitter_offsetAtEnd_dropsTrailingEmptyRange() {
        // If a Next tap happened exactly at the duration boundary
        // (or beyond, defensively), it gets filtered and one range
        // covers the whole file.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 60, nextTapOffsets: [60]
        )
        #expect(ranges.count == 1)
        #expect(ranges[0] == 0..<60)
    }

    @Test func splitter_outOfOrderOffsets_filtered() {
        // Defensive against clock skew. Strictly-increasing only.
        // Use overlap: 0 here so the assertions stay focused on the
        // sanitize behavior rather than fighting overlap math.
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 100, nextTapOffsets: [30, 20, 50], overlap: 0
        )
        // 20 drops (not > 30), 50 kept.
        #expect(ranges.count == 3)
        #expect(ranges[0] == 0..<30)
        #expect(ranges[1] == 30..<50)
        #expect(ranges[2] == 50..<100)
    }

    @Test func splitter_zeroOrNegativeOffsets_filtered() {
        let ranges = VoiceClipSplitter.segmentRanges(
            masterDuration: 60, nextTapOffsets: [0, -5, 20], overlap: 0
        )
        #expect(ranges.count == 2)
        #expect(ranges[0] == 0..<20)
        #expect(ranges[1] == 20..<60)
    }

    @Test func splitter_sanitize_keepsMonotonicInRange() {
        let sanitized = VoiceClipSplitter.sanitize(
            offsets: [-1, 0, 5, 5, 10, 8, 20, 100], masterDuration: 60
        )
        #expect(sanitized == [5, 10, 20])
    }

    // MARK: - NextClipController nextTapOffsets (PR 4)

    @Test func controller_tracksNextTapOffsets() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        #expect(controller.nextTapOffsets.isEmpty)

        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))
        _ = controller.handleNextTap(now: start.addingTimeInterval(7.5))

        #expect(controller.nextTapOffsets == [3.0, 7.5])
    }

    @Test func controller_offsetsClearOnSessionEnd() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)
        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))

        controller.sessionDidEnd()

        #expect(controller.nextTapOffsets.isEmpty)
    }

    @Test func controller_debouncedTaps_doNotAppendOffset() {
        let spy = RecordingHandoffSpy()
        let controller = NextClipController(handoff: spy)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        controller.sessionDidStart(at: start)

        // First tap too soon → debounced; no offset.
        _ = controller.handleNextTap(now: start.addingTimeInterval(1.0))
        #expect(controller.nextTapOffsets.isEmpty)

        // Second tap clears the threshold → offset appended.
        _ = controller.handleNextTap(now: start.addingTimeInterval(3.0))
        #expect(controller.nextTapOffsets == [3.0])
    }
}
