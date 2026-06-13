import Testing
import Foundation
@testable import HiMem

/// Money tests for the "all roll clips have the same time" bug
/// (Tom 2026-06-09). Before the fix, `VoiceClipFragment` carried no
/// per-clip capture time, so `createVoiceFragment` defaulted to `Date()`
/// for every clip in a roll and the Memory Detail UI rendered identical
/// `HH:MM` stamps on every row of a long capture.
///
/// `capturedAtSequence(start:offsets:)` is the pure helper that maps a
/// recording's start wall-clock + the user's Next-tap offsets (seconds
/// since start) to one `capturedAt` per resulting clip. Bug-first rule:
/// these assertions failed to compile against the pre-fix codebase
/// because the helper didn't exist, then went green once added.
struct VoiceCaptureCapturedAtTests {

    @Test func capturedAtSequence_emptyOffsets_returnsSingleClipAtStart() {
        // Single-clip path: master IS the clip, no Next taps fired.
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let result = VoiceCaptureOrchestrator.capturedAtSequence(start: start, offsets: [])
        #expect(result == [start])
    }

    @Test func capturedAtSequence_threeOffsets_yieldsFourClipsStartPlusOffset() {
        // Three Next taps → four clips. Clip 1 starts at the recording
        // start; each subsequent clip starts at the corresponding Next
        // tap offset.
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let offsets: [TimeInterval] = [3.5, 9.2, 15.0]
        let result = VoiceCaptureOrchestrator.capturedAtSequence(start: start, offsets: offsets)
        #expect(result.count == 4)
        #expect(result[0] == start)
        #expect(result[1] == start.addingTimeInterval(3.5))
        #expect(result[2] == start.addingTimeInterval(9.2))
        #expect(result[3] == start.addingTimeInterval(15.0))
    }

    @Test func capturedAtSequence_preservesMonotonicOrder() {
        // Regression guard: even if a hypothetical input arrived
        // out-of-order, the helper passes offsets through unchanged.
        // The sort responsibility lives at the source (NextClipController
        // appends in tap order); the helper trusts its caller.
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let result = VoiceCaptureOrchestrator.capturedAtSequence(
            start: start,
            offsets: [1.0, 2.0, 3.0]
        )
        #expect(result[0] < result[1])
        #expect(result[1] < result[2])
        #expect(result[2] < result[3])
    }

    @Test func capturedAtSequence_largeRollProducesUniqueTimestamps() {
        // The composting case: a 25-min roll with 154 Next taps.
        // Every resulting clip must have a distinct capturedAt — that's
        // the entire point of the fix (the bug was every clip sharing
        // the same wall-clock).
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let offsets: [TimeInterval] = (1...153).map { Double($0) * 10.0 }
        let result = VoiceCaptureOrchestrator.capturedAtSequence(start: start, offsets: offsets)
        #expect(result.count == 154)
        #expect(Set(result).count == 154, "Every clip in a roll must have a unique capturedAt")
    }
}
