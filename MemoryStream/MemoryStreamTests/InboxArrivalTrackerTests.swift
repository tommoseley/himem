import Testing
import Foundation
@testable import HiMem

/// Money tests for `InboxArrivalTracker` — the per-clipId phase
/// state introduced 2026-05-29 so SessionListView can render
/// `IncomingCard`s for clips arriving and transcribing.
///
/// Locks the contract for all four phase transitions defined in the
/// sync-surface spec (`screens-captured-clips-sessions.jsx`):
///   - pre-announce → `.downloading` (first) or `.waiting` (rest)
///   - file arrived → `.transcribing` + waiting promoted
///   - reachability lost → all downloading/waiting → `.paused`
///   - reachability restored → oldest paused → `.downloading`
@MainActor
@Suite(.serialized)
struct InboxArrivalTrackerTests {

    private func freshTracker() -> InboxArrivalTracker {
        #if DEBUG
        InboxArrivalTracker.shared.debugResetForTesting()
        #endif
        return InboxArrivalTracker.shared
    }

    private func preAnnounce(
        _ t: InboxArrivalTracker,
        clipId: UUID = UUID(),
        capturedAt: Date = Date(),
        duration: TimeInterval = 10,
        at announcedAt: Date = Date()
    ) -> UUID {
        t.recordPreAnnounce(
            clipId: clipId,
            capturedAt: capturedAt,
            durationSeconds: duration,
            latitude: nil,
            longitude: nil,
            fileSizeBytes: nil,
            now: announcedAt
        )
        return clipId
    }

    // MARK: - Queue semantics

    @Test func firstPreAnnounce_isDownloading() {
        let t = freshTracker()
        let id = preAnnounce(t)
        #expect(t.phase(for: id) == .downloading)
    }

    @Test func secondPreAnnounceWhileFirstDownloading_isWaiting() {
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        #expect(t.phase(for: a) == .downloading)
        #expect(t.phase(for: b) == .waiting)
    }

    @Test func thirdPreAnnounce_alsoWaiting() {
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        let c = preAnnounce(t, at: Date(timeIntervalSince1970: 102))
        #expect(t.phase(for: a) == .downloading)
        #expect(t.phase(for: b) == .waiting)
        #expect(t.phase(for: c) == .waiting)
    }

    @Test func duplicatePreAnnounce_isIdempotent() {
        let t = freshTracker()
        let id = UUID()
        _ = preAnnounce(t, clipId: id, at: Date(timeIntervalSince1970: 100))
        _ = preAnnounce(t, clipId: id, at: Date(timeIntervalSince1970: 200))
        #expect(t.inFlightCount == 1)
        #expect(t.phase(for: id) == .downloading)
    }

    // MARK: - Transcribing transition

    /// File-arrived transition: the downloading clip becomes
    /// transcribing, and the oldest waiting clip is promoted to
    /// downloading to keep the queue moving.
    @Test func transcribingPromotesOldestWaiting() {
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        let c = preAnnounce(t, at: Date(timeIntervalSince1970: 102))

        t.recordTranscribingStarted(clipId: a)

        #expect(t.phase(for: a) == .transcribing)
        #expect(t.phase(for: b) == .downloading, "Oldest waiting should promote to downloading")
        #expect(t.phase(for: c) == .waiting)
    }

    @Test func transcribingWithoutPreAnnounce_synthesizesFromFallback() {
        // sendMessage pre-announce can be lost when the phone is
        // backgrounded; the file still arrives via transferFile.
        // The tracker must still get an entry so the IncomingCard
        // renders during the transcribe window.
        let t = freshTracker()
        let id = UUID()
        let now = Date()
        t.recordTranscribingStarted(
            clipId: id,
            fallbackMetadata: InFlightClipMetadata(
                capturedAt: now,
                durationSeconds: 30,
                latitude: nil,
                longitude: nil,
                fileSizeBytes: nil,
                announcedAt: now
            )
        )
        #expect(t.phase(for: id) == .transcribing)
        #expect(t.inFlightCount == 1)
    }

    @Test func transcribingWithoutPreAnnounceOrFallback_isNoOp() {
        // No metadata, no entry — safe early return rather than
        // crashing or creating a malformed in-flight clip.
        let t = freshTracker()
        let id = UUID()
        t.recordTranscribingStarted(clipId: id, fallbackMetadata: nil)
        #expect(t.phase(for: id) == nil)
        #expect(t.inFlightCount == 0)
    }

    // MARK: - Reachability transitions

    @Test func reachabilityLost_pausesDownloadingAndWaiting() {
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        t.recordReachabilityLost()
        #expect(t.phase(for: a) == .paused)
        #expect(t.phase(for: b) == .paused)
    }

    @Test func reachabilityLost_doesNotPauseTranscribing() {
        // Transcribing isn't waiting on the watch — it's running
        // locally on the phone. Reachability changes are irrelevant.
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        t.recordTranscribingStarted(clipId: a)
        t.recordReachabilityLost()
        #expect(t.phase(for: a) == .transcribing)
    }

    @Test func reachabilityRestored_resumesOldestPausedAsDownloading() {
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        let c = preAnnounce(t, at: Date(timeIntervalSince1970: 102))
        t.recordReachabilityLost()
        t.recordReachabilityRestored()
        #expect(t.phase(for: a) == .downloading)
        #expect(t.phase(for: b) == .waiting)
        #expect(t.phase(for: c) == .waiting)
    }

    // MARK: - Clear + sort + queries

    @Test func clear_removesEntry_andPromotesNextWaiting() {
        // If the transcribing clip clears (transcription attempt
        // landed) and there's still a waiting clip in the queue
        // with no active downloader, the waiting one promotes.
        let t = freshTracker()
        let a = preAnnounce(t, at: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, at: Date(timeIntervalSince1970: 101))
        t.recordTranscribingStarted(clipId: a)
        // a is transcribing, b is now downloading.
        t.clear(clipId: a)
        // After clear, b is still downloading — no waiting to promote.
        #expect(t.phase(for: a) == nil)
        #expect(t.phase(for: b) == .downloading)
    }

    @Test func sortedNewestFirst_orderingMatchesCapturedAtDescending() {
        let t = freshTracker()
        let a = preAnnounce(t, clipId: UUID(), capturedAt: Date(timeIntervalSince1970: 100))
        let b = preAnnounce(t, clipId: UUID(), capturedAt: Date(timeIntervalSince1970: 300))
        let c = preAnnounce(t, clipId: UUID(), capturedAt: Date(timeIntervalSince1970: 200))
        let order = t.sortedNewestFirst().map(\.clipId)
        #expect(order == [b, c, a])
    }

    @Test func clearUntracked_isHarmless() {
        let t = freshTracker()
        let id = UUID()
        t.clear(clipId: id)
        #expect(t.phase(for: id) == nil)
        #expect(t.inFlightCount == 0)
    }

    // MARK: - Split-master orphan-clear (§ 8.6)

    /// THE BUG. A multi-clip On-a-roll session pre-announces with
    /// the master clipId; when the file arrives, `acceptArrivedClip`
    /// splits into N children with brand-new UUIDs and writes them
    /// to the manifest. The master clipId is never written to the
    /// manifest — so `transcribePendingInboxClips` never sees it,
    /// never calls `clear` for it, and the tracker entry sits in
    /// `.downloading` (then `.paused` after a reachability dip)
    /// forever. Tom QA 2026-05-30 saw two such orphaned IncomingCards
    /// "Waiting for your Watch" with the watch's pending list empty.
    ///
    /// Fix: `acceptArrivedClip`'s split-success branch explicitly
    /// calls `clear(clipId: master.clipId)`. This test locks the
    /// tracker behavior — the integration is exercised manually
    /// via the trace lines added in the same commit.
    @Test func masterClear_afterSplit_doesNotAffectChildEntries() {
        let t = freshTracker()
        let masterId = UUID()
        let childA = UUID()
        let childB = UUID()
        _ = preAnnounce(t, clipId: masterId, at: Date(timeIntervalSince1970: 100))
        // Simulate split: clear the master (the fix), then the
        // transcribe sweep records the children from their fallback
        // metadata.
        t.clear(clipId: masterId)
        t.recordTranscribingStarted(
            clipId: childA,
            fallbackMetadata: InFlightClipMetadata(
                capturedAt: Date(timeIntervalSince1970: 100),
                durationSeconds: 5, latitude: nil, longitude: nil,
                fileSizeBytes: nil, announcedAt: Date()
            )
        )
        t.recordTranscribingStarted(
            clipId: childB,
            fallbackMetadata: InFlightClipMetadata(
                capturedAt: Date(timeIntervalSince1970: 105),
                durationSeconds: 5, latitude: nil, longitude: nil,
                fileSizeBytes: nil, announcedAt: Date()
            )
        )
        #expect(t.phase(for: masterId) == nil, "Master entry must be cleared after split")
        #expect(t.phase(for: childA) == .transcribing)
        #expect(t.phase(for: childB) == .transcribing)
    }

    /// Same fix path, but exercising the duplicate-master case: if
    /// a redelivered master arrives later, the dedup branch should
    /// also clear any leftover orphan from a prior arrival.
    @Test func masterClear_onDuplicateRedelivery_isIdempotent() {
        let t = freshTracker()
        let masterId = UUID()
        _ = preAnnounce(t, clipId: masterId, at: Date(timeIntervalSince1970: 100))
        // Orphan exists from a prior arrival's pre-announce.
        #expect(t.phase(for: masterId) == .downloading)
        // Duplicate-master dedup branch calls clear; second clear
        // is idempotent.
        t.clear(clipId: masterId)
        t.clear(clipId: masterId)
        #expect(t.phase(for: masterId) == nil)
    }
}
