import Testing
import Foundation
@testable import HiMem

/// Money tests for `InboxArrivalTracker` — the per-clipId phase
/// state introduced 2026-05-29 so SessionListView can render
/// `IncomingCard`s for clips that are still arriving/transcribing.
///
/// Invariants locked here:
///   1. Recording a phase makes `phase(for:)` return it.
///   2. Clearing removes the entry and `hasAnyInFlight` reflects it.
///   3. Multiple clipIds coexist independently.
///   4. The `@Published phasesByClipId` dictionary observed by
///      SwiftUI views actually fires on mutation.
@MainActor
@Suite(.serialized)
struct InboxArrivalTrackerTests {

    private func freshTracker() -> InboxArrivalTracker {
        #if DEBUG
        InboxArrivalTracker.shared.debugResetForTesting()
        #endif
        return InboxArrivalTracker.shared
    }

    @Test func recordTranscribingStarted_makesPhaseQueryable() {
        let t = freshTracker()
        let id = UUID()
        t.recordTranscribingStarted(clipId: id)
        #expect(t.phase(for: id) == .transcribing)
        #expect(t.hasAnyInFlight)
        #expect(t.inFlightCount == 1)
    }

    @Test func clear_removesFromTracking() {
        let t = freshTracker()
        let id = UUID()
        t.recordTranscribingStarted(clipId: id)
        t.clear(clipId: id)
        #expect(t.phase(for: id) == nil)
        #expect(t.hasAnyInFlight == false)
        #expect(t.inFlightCount == 0)
    }

    @Test func multipleClips_trackedIndependently() {
        let t = freshTracker()
        let a = UUID()
        let b = UUID()
        t.recordTranscribingStarted(clipId: a)
        t.recordTranscribingStarted(clipId: b)
        #expect(t.inFlightCount == 2)
        t.clear(clipId: a)
        #expect(t.phase(for: a) == nil)
        #expect(t.phase(for: b) == .transcribing)
        #expect(t.inFlightCount == 1)
    }

    /// SwiftUI views observe the `@Published phasesByClipId`
    /// dictionary; if mutations don't fire `objectWillChange`, the
    /// views won't update. Lock that the publisher emits on both
    /// record and clear.
    @Test func phasesByClipId_publishesOnMutation() async {
        let t = freshTracker()
        let id = UUID()
        // Sanity baseline.
        #expect(t.phasesByClipId.isEmpty)
        t.recordTranscribingStarted(clipId: id)
        #expect(t.phasesByClipId[id] == .transcribing)
        t.clear(clipId: id)
        #expect(t.phasesByClipId[id] == nil)
    }

    /// `clear` for an id that was never recorded is a no-op (no
    /// crash, no spurious published change). Important because the
    /// arrival path always clears after a transcribe attempt, even
    /// if a code path skipped the `recordTranscribingStarted` call
    /// (e.g., the dedup early-return).
    @Test func clearUntracked_isHarmless() {
        let t = freshTracker()
        let id = UUID()
        t.clear(clipId: id)
        #expect(t.phase(for: id) == nil)
        #expect(t.inFlightCount == 0)
    }
}
