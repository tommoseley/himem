import Foundation
import Combine

/// Per-clipId in-flight state for the sync surface defined in
/// `screens-captured-clips-sessions.jsx` § SYNC / INCOMING
/// (2026-05-29 spec addition).
///
/// **Problem the spec addresses:** the old Captured Clips surface
/// hid the operational truth that clips don't teleport in. They
/// download (audio watch→phone, determinate) and then transcribe
/// (phone reads it, indeterminate). With nothing surfaced about
/// either phase, a 5-minute clip that took 30 s to transcribe looked
/// identical to one that instantly produced "no speech."
///
/// **This service** is the in-flight model `SessionListView` reads
/// from to render `IncomingCard`s alongside ready `SessionCard`s.
/// Each clip in flight has its own `InFlightClip` entry with the
/// metadata required to render before the audio actually lands in
/// `InboxManifest`.
///
/// **Relationship to `InboxManifest`** (post-consolidation, 2026-05-30):
///
/// The manifest is the authoritative source of truth for clip
/// lifecycle status (`.announced` / `.received` / `.transcribing` /
/// `.transcribed` / `.disposed`). The tracker is a thin transient
/// view-model layered on top — it holds the announce-time metadata
/// (announcedAt, fileSizeBytes) the manifest doesn't carry, and the
/// queue-position bookkeeping (which clip is `.downloading` vs
/// `.waiting`). Every public method cross-checks
/// `InboxManifest.shared.status(for:)` so the tracker can never
/// surface an entry the manifest has moved to `.disposed`. Without
/// the cross-check, a user delete mid-transcription would leave a
/// stale `IncomingCard` lingering until the transcribe sweep cleared
/// it; with the check, the next `phase(for:)` returns nil and the
/// stale entry is purged.
///
/// **Phase queue semantics.** Only one clip downloads at a time —
/// iOS's WC layer serializes file transfers. Per-clip phases:
///
///   - `.waiting`     queued behind a clip currently downloading
///   - `.downloading` actively receiving bytes via `transferFile`
///   - `.transcribing` audio is on disk, `SpeechAnalyzer` is running
///   - `.paused`      reachability dropped mid-transfer
///
/// When a downloading clip transitions to transcribing (the file
/// has arrived), the oldest waiting clip is promoted to downloading
/// so there's always at most one downloading clip alongside zero
/// or more waiting and transcribing clips.
@MainActor
final class InboxArrivalTracker: ObservableObject {
    static let shared = InboxArrivalTracker()

    enum Phase: Equatable {
        /// Pre-announced by the watch; queued behind the clip
        /// currently downloading. Promoted to `.downloading` when
        /// that clip transitions to `.transcribing`.
        case waiting
        /// Actively receiving via `transferFile`. iOS doesn't expose
        /// incremental delivery progress on the receiving side, so
        /// the UI shows an indeterminate animation rather than a
        /// byte-accurate bar.
        case downloading
        /// File is on disk in the inbox manifest; `SpeechAnalyzer`
        /// is running against it. Lasts as long as the transcribe
        /// call takes — typically seconds for a short clip, longer
        /// for a 5-minute clip.
        case transcribing
        /// Reachability dropped while this clip was downloading or
        /// waiting. The watch's transferFile queue holds the actual
        /// data; sync resumes when the watch is near again.
        case paused
    }

    /// Per-clipId in-flight entry. Carries the metadata required to
    /// render an `IncomingCard` before the audio file has landed in
    /// the inbox manifest. Captured at pre-announce time on the
    /// iPhone side.
    struct InFlightClip: Identifiable, Equatable {
        let clipId: UUID
        let capturedAt: Date
        let durationSeconds: TimeInterval
        let latitude: Double?
        let longitude: Double?
        let fileSizeBytes: Int64?
        let announcedAt: Date
        var phase: Phase

        var id: UUID { clipId }
    }

    /// In-flight clips by clipId. Published so SwiftUI views observe
    /// transitions. Empty when nothing is in flight.
    @Published private(set) var clipsInFlight: [UUID: InFlightClip] = [:]

    private init() {}

    // MARK: - State transitions

    /// Records a watch-side pre-announce. The watch sends this
    /// `sendMessage` immediately before calling `transferFile` so
    /// the iPhone can show the clip in flight even before the file
    /// data lands. Best-effort delivery — if the message fails
    /// (phone unreachable at the moment of the send), the file
    /// arrives later and `recordTranscribingStarted` falls back to
    /// creating a synthetic entry from the manifest.
    ///
    /// The first pre-announce becomes `.downloading`. Subsequent
    /// pre-announces while a clip is downloading queue as
    /// `.waiting`. When the downloading clip later transitions to
    /// `.transcribing`, the oldest waiting clip is promoted to
    /// `.downloading`.
    func recordPreAnnounce(
        clipId: UUID,
        capturedAt: Date,
        durationSeconds: TimeInterval,
        latitude: Double?,
        longitude: Double?,
        fileSizeBytes: Int64?,
        now: Date = Date()
    ) {
        purgeDisposed()
        // Idempotent — duplicate pre-announces (sendMessage +
        // transferUserInfo backup, or a re-send after reachability
        // restoration) shouldn't bump the queue or reset metadata.
        guard clipsInFlight[clipId] == nil else { return }
        // Manifest is authoritative for "have I seen this clipId?"
        // Skip if the manifest already knows about it — either
        // already processed (.received / .transcribed) or already
        // disposed (.disposed tombstone). Prevents resurrecting a
        // clip the user just deleted; redundant with the
        // WatchSessionDelegate pre-announce gates but cheap and
        // closes the gap if anything calls the tracker directly.
        if InboxManifest.shared.status(for: clipId) != nil { return }
        let hasActiveDownload = clipsInFlight.values.contains { entry in
            if case .downloading = entry.phase { return true }
            return false
        }
        let phase: Phase = hasActiveDownload ? .waiting : .downloading
        clipsInFlight[clipId] = InFlightClip(
            clipId: clipId,
            capturedAt: capturedAt,
            durationSeconds: durationSeconds,
            latitude: latitude,
            longitude: longitude,
            fileSizeBytes: fileSizeBytes,
            announcedAt: now,
            phase: phase
        )
    }

    /// Transitions `clipId` to `.transcribing`. If the clip was
    /// pre-announced and is currently `.downloading` or `.waiting`,
    /// its existing metadata is preserved and the phase flips. If
    /// the pre-announce was lost (sendMessage unreliable), `fallback`
    /// supplies the metadata so the UI still gets a renderable
    /// entry from this point onward.
    ///
    /// Promotes the oldest `.waiting` clip to `.downloading` on
    /// every successful transition into `.transcribing`, so the
    /// queue stays serialized at "one downloading, N waiting."
    func recordTranscribingStarted(
        clipId: UUID,
        fallbackMetadata: InFlightClipMetadata? = nil
    ) {
        if var existing = clipsInFlight[clipId] {
            existing.phase = .transcribing
            clipsInFlight[clipId] = existing
        } else if let fb = fallbackMetadata {
            // Pre-announce was lost; synthesize the entry from the
            // manifest's now-arrived InboxClip.
            clipsInFlight[clipId] = InFlightClip(
                clipId: clipId,
                capturedAt: fb.capturedAt,
                durationSeconds: fb.durationSeconds,
                latitude: fb.latitude,
                longitude: fb.longitude,
                fileSizeBytes: fb.fileSizeBytes,
                announcedAt: fb.announcedAt,
                phase: .transcribing
            )
        }
        promoteOldestWaitingIfRoom()
    }

    /// Reachability dropped while a transfer was in flight. All
    /// downloading and waiting clips pause until reachability
    /// returns. Transcribing clips are not affected — they're not
    /// waiting on the watch.
    func recordReachabilityLost(now: Date = Date()) {
        for (id, var entry) in clipsInFlight {
            switch entry.phase {
            case .waiting, .downloading:
                entry.phase = .paused
                clipsInFlight[id] = entry
            case .transcribing, .paused:
                break
            }
        }
    }

    /// Reachability returned. All paused clips resume — the oldest
    /// becomes `.downloading`, the rest go back to `.waiting`.
    func recordReachabilityRestored() {
        let paused = clipsInFlight.values
            .filter { if case .paused = $0.phase { return true } else { return false } }
            .sorted { $0.announcedAt < $1.announcedAt }
        guard !paused.isEmpty else { return }
        for (index, clip) in paused.enumerated() {
            var updated = clip
            updated.phase = (index == 0) ? .downloading : .waiting
            clipsInFlight[clip.clipId] = updated
        }
    }

    /// Removes the clip from in-flight tracking after the
    /// transcription attempt has landed. Promotes a waiting clip
    /// if there's room.
    func clear(clipId: UUID) {
        guard clipsInFlight.removeValue(forKey: clipId) != nil else { return }
        promoteOldestWaitingIfRoom()
    }

    // MARK: - Convenience queries

    /// `true` when any clip is currently in-flight. Drives the
    /// `SyncStrip` global banner's visibility.
    var hasAnyInFlight: Bool {
        purgeDisposed()
        return !clipsInFlight.isEmpty
    }

    /// Total in-flight count for header subtitle math.
    var inFlightCount: Int {
        purgeDisposed()
        return clipsInFlight.count
    }

    /// Look up a clip's phase. Returns nil for clipIds not in flight
    /// or for clipIds the manifest has moved to `.disposed`.
    func phase(for clipId: UUID) -> Phase? {
        purgeDisposed()
        return clipsInFlight[clipId]?.phase
    }

    /// In-flight clips, ordered newest-captured first (matches the
    /// SessionCard list ordering so IncomingCards at the top of the
    /// list read like a continuation of the same time-sorted feed).
    func sortedNewestFirst() -> [InFlightClip] {
        purgeDisposed()
        return clipsInFlight.values.sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: - Private

    /// Drops entries the manifest has moved to `.disposed`. Cheap
    /// (O(N) where N is the small in-flight count) and keeps the
    /// tracker honest against user deletes that happen
    /// mid-transcription. Without this, a stale entry would sit in
    /// `clipsInFlight` until the transcribe sweep ran its `clear`,
    /// which never fires for a clip the user has already removed.
    private func purgeDisposed() {
        let manifest = InboxManifest.shared
        let disposed = clipsInFlight.keys.filter {
            manifest.status(for: $0) == .disposed
        }
        for id in disposed {
            clipsInFlight.removeValue(forKey: id)
        }
        if !disposed.isEmpty {
            // Disposal can leave the queue without a downloading
            // entry — re-elect.
            promoteOldestWaitingIfRoom()
        }
    }

    /// Promotes the oldest `.waiting` clip to `.downloading` IFF
    /// there's no currently-downloading clip. Idempotent.
    private func promoteOldestWaitingIfRoom() {
        let hasActive = clipsInFlight.values.contains { entry in
            if case .downloading = entry.phase { return true }
            return false
        }
        guard !hasActive else { return }
        let nextWaiting = clipsInFlight.values
            .filter { if case .waiting = $0.phase { return true } else { return false } }
            .sorted { $0.announcedAt < $1.announcedAt }
            .first
        guard let next = nextWaiting else { return }
        clipsInFlight[next.clipId]?.phase = .downloading
    }

    #if DEBUG
    /// Test seam: clears all tracked phases so unit tests don't
    /// leak singleton state.
    func debugResetForTesting() {
        clipsInFlight = [:]
    }
    #endif
}

/// Carrier for `recordTranscribingStarted`'s fallback when the
/// pre-announce was lost. Lets `WatchSessionDelegate` supply the
/// metadata it has from `acceptArrivedClip` (where the file
/// actually arrived) without coupling the tracker to `InboxClip`.
struct InFlightClipMetadata: Equatable {
    let capturedAt: Date
    let durationSeconds: TimeInterval
    let latitude: Double?
    let longitude: Double?
    let fileSizeBytes: Int64?
    let announcedAt: Date
}
