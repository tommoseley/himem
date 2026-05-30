import Foundation

/// Per-clipId critical section guarding `WatchSessionDelegate
/// .acceptArrivedClip` against the double-delivery race documented in
/// `docs/architecture/Captured Clips · watch-to-phone sync system.md`
/// § 8.2.
///
/// **The race.** `acceptArrivedClip` awaits on `VoiceClipSplitter
/// .split` and `AudioCompressor.compressInPlace` — both `await`
/// points release `@MainActor`. If `session(_:didReceive:)` fires
/// twice for the same master clipId in rapid succession (the watch
/// double-queued `send(clip:)` due to overlapping triggers, or
/// iOS's WC layer redelivered the cached file), both Tasks can
/// enter `acceptArrivedClip` and pass `isMasterAlreadyProcessed`
/// before either writes to the manifest. Each then proceeds to
/// split into N fragments with fresh UUIDs, and the user sees
/// duplicate clips (one set from Task A, one from Task B) — the
/// exact "1 unsplit + 4 split clips, each appearing twice" symptom
/// Tom hit in QA 2026-05-29.
///
/// **The fix.** Track in-flight clipIds in a small `@MainActor` set
/// keyed at the entry point. Second concurrent entry for the same
/// clipId is rejected with a no-op + ack, leaving the file copy
/// for the first to handle. The set is cleared on every exit
/// (success or throw) via `defer`.
///
/// This is per-clipId, not per-rollGroupId, because the race is
/// specifically about the SAME master arriving twice. Different
/// masters with the same rollGroupId are still gated by the
/// `isMasterAlreadyProcessed` predicate, which the critical
/// section sits ahead of.
@MainActor
enum AcceptanceCriticalSection {
    private static var inFlightClipIds: Set<UUID> = []

    /// `true` when the caller successfully entered the critical
    /// section. `false` when another caller is currently inside it
    /// for the same `clipId` — the caller should treat as a no-op
    /// duplicate and skip work.
    static func tryEnter(clipId: UUID) -> Bool {
        if inFlightClipIds.contains(clipId) { return false }
        inFlightClipIds.insert(clipId)
        return true
    }

    /// Releases the critical section. Always called via `defer`
    /// from inside the entered scope so abnormal exits (thrown
    /// errors, cancellations) still clear the entry.
    static func exit(clipId: UUID) {
        inFlightClipIds.remove(clipId)
    }

    /// `true` when the clipId is currently being processed.
    /// Visible for tests + diagnostic logging.
    static func isInFlight(clipId: UUID) -> Bool {
        inFlightClipIds.contains(clipId)
    }

    #if DEBUG
    /// Test seam: clears any leaked entries between tests.
    static func debugResetForTesting() {
        inFlightClipIds = []
    }
    #endif
}
