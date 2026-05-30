import Testing
import Foundation
@testable import HiMem

/// Money tests for the per-clipId critical section guarding
/// `acceptArrivedClip` against the double-delivery race documented
/// in § 8.2 of the system reference doc.
///
/// THE BUG: `acceptArrivedClip` awaits on VoiceClipSplitter.split
/// and AudioCompressor.compressInPlace — both release @MainActor.
/// Two concurrent Tasks for the same master clipId can both pass
/// `isMasterAlreadyProcessed` (manifest still empty at check time)
/// before either writes to the manifest. Each then splits into N
/// child fragments with fresh UUIDs. User sees duplicate clips.
/// Tom hit this in QA 2026-05-29 (one unsplit + four split clips,
/// each appearing twice).
///
/// THE FIX: a small @MainActor set of currently-processing clipIds.
/// Second concurrent entry for the same clipId is rejected with a
/// no-op + ack. Set entries clear on every exit (success or throw)
/// via `defer` in `acceptArrivedClip`. These tests lock the
/// contract: enter/exit semantics, re-entry safety, multi-clip
/// independence.
@MainActor
@Suite(.serialized)
struct AcceptanceCriticalSectionTests {

    private func freshSection() {
        #if DEBUG
        AcceptanceCriticalSection.debugResetForTesting()
        #endif
    }

    @Test func tryEnter_succeedsOnEmptySet() {
        freshSection()
        let id = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id))
    }

    /// THE BUG-FIX MONEY ASSERTION. A second tryEnter for the same
    /// clipId, while the first is still inside, must fail — that's
    /// what blocks the duplicate `acceptArrivedClip` race.
    @Test func tryEnter_failsOnConcurrentReentryForSameClipId() {
        freshSection()
        let id = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == false,
                "Second concurrent tryEnter for the same clipId must reject")
    }

    @Test func exit_allowsReentry() {
        freshSection()
        let id = UUID()
        _ = AcceptanceCriticalSection.tryEnter(clipId: id)
        AcceptanceCriticalSection.exit(clipId: id)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id) == false)
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true,
                "Re-entry after exit must succeed (next delivery of same clip)")
    }

    @Test func differentClipIds_doNotBlock() {
        freshSection()
        let a = UUID()
        let b = UUID()
        #expect(AcceptanceCriticalSection.tryEnter(clipId: a) == true)
        // Concurrent processing of a different clip must proceed —
        // the section is per-clipId, not a global mutex. Multi-clip
        // sync bursts (the common case) must parallelize.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: b) == true)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: a))
        #expect(AcceptanceCriticalSection.isInFlight(clipId: b))
    }

    @Test func exitUntrackedClipId_isHarmless() {
        // Defensive: if a code path called exit without a matching
        // tryEnter (it shouldn't, but defer-only exit paths can be
        // tricky), the call must be a no-op rather than throwing or
        // corrupting state.
        freshSection()
        let id = UUID()
        AcceptanceCriticalSection.exit(clipId: id)
        #expect(AcceptanceCriticalSection.isInFlight(clipId: id) == false)
    }

    /// Simulates the realistic race: Task A calls tryEnter and
    /// (hypothetically) starts an await; Task B calls tryEnter for
    /// the same clipId before Task A's defer fires. Task B must be
    /// rejected. After Task A's defer, Task C arriving fresh for the
    /// same clipId (e.g., a much later re-delivery) succeeds. This
    /// is the exact lifecycle the fix locks.
    @Test func realisticConcurrentLifecycle() {
        freshSection()
        let id = UUID()
        // Task A entry.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        // Task B arrives mid-processing.
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == false)
        // Task A finishes — defer fires.
        AcceptanceCriticalSection.exit(clipId: id)
        // Task C arrives much later (e.g., iOS re-delivers from queue).
        #expect(AcceptanceCriticalSection.tryEnter(clipId: id) == true)
        AcceptanceCriticalSection.exit(clipId: id)
    }
}
