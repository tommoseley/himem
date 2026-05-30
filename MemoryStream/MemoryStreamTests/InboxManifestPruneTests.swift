import Testing
import Foundation
@testable import HiMem

/// Money tests for `InboxManifest.pruned(_:olderThan:now:)`.
///
/// Why this exists: after `InboxProcessedClipIds` goes away in Step D,
/// the manifest itself remembers disposed clips (as `.disposed` rows
/// with a `disposedAt` timestamp). Without aging, the manifest grows
/// unboundedly — every clip Tom ever recorded would stay as a
/// tombstone. The prune pass drops `.disposed` rows older than the
/// threshold (default 90 days) on every load, capping the manifest at
/// "active + recently-disposed."
///
/// Active statuses (`.announced` / `.received` / `.transcribing` /
/// `.transcribed`) are NEVER pruned regardless of age — those represent
/// real audio + UI rows the user could be interacting with.
struct InboxManifestPruneTests {

    /// A `.disposed` row whose `disposedAt` is past the threshold
    /// drops out. Threshold semantics: STRICTLY older than (days * 86400) seconds.
    @Test func disposedOlderThanThreshold_dropped() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let ancient = now.addingTimeInterval(-91 * 86400)
        let recent = now.addingTimeInterval(-30 * 86400)

        let oldRow = makeClip(status: .disposed, disposedAt: ancient)
        let recentRow = makeClip(status: .disposed, disposedAt: recent)

        let pruned = InboxManifest.pruned([oldRow, recentRow], olderThan: 90, now: now)
        let remaining = Set(pruned.map(\.clipId))
        #expect(remaining == [recentRow.clipId])
    }

    @Test func disposedWithinThreshold_retained() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let recent = now.addingTimeInterval(-30 * 86400)
        let row = makeClip(status: .disposed, disposedAt: recent)
        let pruned = InboxManifest.pruned([row], olderThan: 90, now: now)
        #expect(pruned.count == 1)
    }

    /// Active statuses are never pruned, even if `disposedAt` is set
    /// (which would be a bug, but the prune pass should still be safe
    /// against it).
    @Test func activeStatus_neverPruned_regardlessOfAge() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let ancient = now.addingTimeInterval(-365 * 86400)
        let active: [InboxClip.Status] = [.announced, .received, .transcribing, .transcribed]
        for status in active {
            let row = makeClip(status: status, disposedAt: ancient)
            let pruned = InboxManifest.pruned([row], olderThan: 90, now: now)
            #expect(pruned.count == 1, "status \(status) was pruned but shouldn't be")
        }
    }

    /// A `.disposed` row with no `disposedAt` (older tombstone created
    /// without the field) is retained — we can't prove it's older than
    /// the threshold without the timestamp, so we keep it.
    @Test func disposedWithoutDisposedAt_retained() {
        let now = Date()
        let row = makeClip(status: .disposed, disposedAt: nil)
        let pruned = InboxManifest.pruned([row], olderThan: 90, now: now)
        #expect(pruned.count == 1)
    }

    private func makeClip(status: InboxClip.Status, disposedAt: Date?) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test.caf",
            transcriptionAttempted: false,
            rollGroupId: nil,
            status: status,
            disposedAt: disposedAt
        )
    }
}
