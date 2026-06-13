import Testing
@testable import HiMem

/// Boundary tests for `TranscriptModeThreshold`. These exist because the
/// "> 1 clip" visibility rule and the "> 6 clips" / "> 1,500 words"
/// default-mode cutoffs are contracts with the design spec — getting
/// the equality wrong would silently flip whether the toggle appears
/// or which mode opens by default on average-length memories.
///
/// Spec: `docs/design/Memory Detail · long-memory navigation.md`
/// (Tom 2026-06-09).
struct TranscriptModeThresholdTests {

    // MARK: - headerShown (toggle visibility — clip-count only)

    @Test func headerShown_singleClip_isFalse() {
        // 1 clip → nothing to index, no toggle.
        #expect(TranscriptModeThreshold.headerShown(clipCount: 1) == false)
    }

    @Test func headerShown_twoClips_isTrue() {
        // 2 clips → toggle appears even though the memory is short by
        // word count. The spec's earlier "earned past 1,500 words"
        // rule was dropped as needless magic.
        #expect(TranscriptModeThreshold.headerShown(clipCount: 2) == true)
    }

    @Test func headerShown_zeroClips_isFalse() {
        // Defensive: a notes-only memory with no voice/note items
        // shouldn't crash or paint a header for nothing.
        #expect(TranscriptModeThreshold.headerShown(clipCount: 0) == false)
    }

    // MARK: - opensCompact (default-mode decision)

    @Test func opensCompact_belowBothThresholds_isFalse() {
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 3, wordCount: 200) == false)
    }

    @Test func opensCompact_exactlyAtClipFloor_isFalse() {
        // Exactly 6 clips: strict inequality says still Full.
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 6, wordCount: 0) == false)
    }

    @Test func opensCompact_oneAboveClipFloor_isTrue() {
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 7, wordCount: 0) == true)
    }

    @Test func opensCompact_exactlyAtWordFloor_isFalse() {
        // Exactly 1,500 words on few clips: strict inequality says
        // still Full.
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 1, wordCount: 1_500) == false)
    }

    @Test func opensCompact_oneAboveWordFloor_isTrue() {
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 1, wordCount: 1_501) == true)
    }

    @Test func opensCompact_clipFloorPassedButWordsZero_isTrue() {
        // OR semantics: a short-per-clip but high-count recording
        // still opens Compact.
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 50, wordCount: 0) == true)
    }

    @Test func opensCompact_wordFloorPassedButOneClip_isTrue() {
        // 25-min single-clip dictation opens Compact even with a
        // single clip (single-clip means no toggle though — header
        // visibility is independent of default mode).
        #expect(TranscriptModeThreshold.opensCompact(clipCount: 1, wordCount: 4_900) == true)
    }

    // MARK: - defaultMode

    @Test func defaultMode_shortMemory_isFull() {
        #expect(TranscriptModeThreshold.defaultMode(clipCount: 3, wordCount: 200) == .full)
    }

    @Test func defaultMode_longByClips_isCompact() {
        #expect(TranscriptModeThreshold.defaultMode(clipCount: 14, wordCount: 3_581) == .compact)
    }

    @Test func defaultMode_longByWordsOnly_isCompact() {
        // The composting transcript was a single roll of 154 clips
        // ≈ 3,650 words. Even a hypothetical single-clip 5,000-word
        // recording must open in Compact — long content is the right
        // scan default no matter how the clips were chunked.
        #expect(TranscriptModeThreshold.defaultMode(clipCount: 1, wordCount: 5_000) == .compact)
    }
}
