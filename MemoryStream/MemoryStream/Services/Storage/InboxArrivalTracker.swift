import Foundation
import Combine

/// Per-clipId phase tracker for the sync surface defined in
/// `screens-captured-clips-sessions.jsx` (2026-05-29 spec addition).
///
/// **Problem the spec addresses:** the old Captured Clips surface
/// hid the operational truth that clips don't teleport in. They
/// download (audio watch→phone, determinate) and then transcribe
/// (phone reads it, indeterminate). The wait the user feels is
/// mostly transcribe. With nothing surfaced about either phase,
/// a 5-minute clip that took 30 s to transcribe looked identical
/// to one that instantly produced "no speech detected" — and the
/// user lost trust in the system because failure was indistinguishable
/// from success-in-progress.
///
/// **This service** is the in-flight state model the SessionListView
/// reads from to render `IncomingCard`s alongside ready `SessionCard`s.
/// Published per-clipId phase changes drive the SwiftUI updates.
///
/// **Phase 1 (this commit):** wires `.transcribing` — surfaces between
/// `acceptArrivedClip` (file is on disk) and `recordTranscriptionAttempt`
/// (transcript has landed). This is the phase that was completely
/// invisible before, so it's the highest-leverage place to start.
///
/// **Future phases** (need WC-layer signaling work not in this commit):
///   - `.waiting` — clip is queued behind another in the OS transfer
///     queue. Requires watch sendMessage pre-announce before
///     `transferFile`.
///   - `.downloading` — incremental progress on an in-flight transfer.
///     Requires reading `WCSession.outstandingFileTransfers` and
///     polling each transfer's `progress: Progress`.
///   - `.paused` — `sessionReachabilityDidChange` flipped to false
///     while a transfer was in flight. Watch-side has the analogous
///     state in `WatchPendingManifest.isSyncStuck`.
@MainActor
final class InboxArrivalTracker: ObservableObject {
    static let shared = InboxArrivalTracker()

    /// Phase a clip is in BEFORE it becomes a ready `InboxClip`.
    /// Once the transcription attempt is recorded, the clip is
    /// removed from the tracker and becomes a regular row on the
    /// manifest — at that point the SessionListView renders it
    /// as a `SessionCard` instead of an `IncomingCard`.
    enum Phase: Equatable {
        /// File received, transcription in progress.
        case transcribing
        // Future cases (not wired yet):
        // case waiting
        // case downloading(bytesReceived: Int64, totalBytes: Int64)
        // case paused(bytesReceivedSoFar: Int64)
    }

    /// Per-clipId phase. SwiftUI views observe via `@ObservedObject`
    /// and the SessionListView renders an IncomingCard for each entry.
    @Published private(set) var phasesByClipId: [UUID: Phase] = [:]

    private init() {}

    /// Records that a clip has entered the transcribing phase.
    /// Called from `WatchSessionDelegate.session(_:didReceive:)` after
    /// the file copy completes and `acceptArrivedClip` has added the
    /// clip to the manifest with an empty transcript.
    func recordTranscribingStarted(clipId: UUID) {
        phasesByClipId[clipId] = .transcribing
    }

    /// Removes the clip from in-flight tracking. Called after
    /// `recordTranscriptionAttempt` lands — at that point the
    /// manifest has the transcript (or the legitimate empty result),
    /// and the SessionListView renders the row as a normal session.
    func clear(clipId: UUID) {
        phasesByClipId.removeValue(forKey: clipId)
    }

    /// `true` when any clip is currently in-flight. Drives the
    /// `SyncStrip` global banner's visibility once that view is wired.
    var hasAnyInFlight: Bool { !phasesByClipId.isEmpty }

    /// Count of in-flight clips by their phase. Drives the
    /// "N total · K ready · J syncing" header subtitle.
    var inFlightCount: Int { phasesByClipId.count }

    /// Look up a specific clipId's phase. Returns nil when the clip
    /// isn't in-flight (either hasn't arrived yet or has already
    /// resolved to a ready manifest row).
    func phase(for clipId: UUID) -> Phase? {
        phasesByClipId[clipId]
    }

    #if DEBUG
    /// Test seam: clears all tracked phases so unit tests don't
    /// leak singleton state.
    func debugResetForTesting() {
        phasesByClipId = [:]
    }
    #endif
}
