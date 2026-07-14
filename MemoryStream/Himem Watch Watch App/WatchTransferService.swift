import Foundation
import Combine
import WatchConnectivity

/// Watch-side WatchConnectivity bridge. Initiates `transferFile` for each
/// pending clip, listens for ack messages from the iPhone confirming
/// receipt, and exposes the most-recently-acked clipId so the coordinator
/// can prune the manifest.
@MainActor
final class WatchTransferService: NSObject, ObservableObject, WCSessionDelegate {
    @Published var lastAckedClipId: UUID?
    /// Published when the iPhone acks a whole roll group at once —
    /// covers split-session siblings and master rows the watch never
    /// cleared because the original arrival ack got lost. Coordinator
    /// fans out to every pending row whose `rollGroupId` matches.
    /// Closes § 8.7 of the system reference doc.
    @Published var lastAckedRollGroupId: UUID?

    func start() {
        guard WCSession.isSupported() else {
            NSLog("[HiMem][WC] watch — WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        NSLog("[HiMem][WC] watch — session.activate() called, reachable=\(session.isReachable)")
    }

    /// Queues a transferFile for the given clip. WatchConnectivity persists
    /// the queue across launches; if the iPhone is currently unreachable
    /// the system holds the file and ships it when reachability returns.
    func send(clip: WatchPendingClip) {
        guard WCSession.isSupported() else {
            NSLog("[HiMem][WC] watch — cannot send, WCSession not supported")
            return
        }
        let session = WCSession.default
        let url = WatchPendingManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[HiMem][WC] watch — file missing at \(url.path), skipping send")
            // Money 2026-06-18: if the file isn't on disk yet
            // (recording-end async drain still flushing, or a
            // sessionReachabilityDidChange fired immediately
            // post-stop), the original code returned silently and
            // the only retry path was the next app cold launch.
            // Schedule a backoff retry so the clip ships once the
            // write completes. Bounded to 1s + 5s + 15s; if all
            // three fail the next legitimate retry triggers
            // (reachability flip, scenePhase=.active, cold launch)
            // still cover it.
            scheduleFileMissingRetry(for: clip)
            return
        }

        // Watch-side belt against the double-delivery race documented
        // in `docs/architecture/Captured Clips · watch-to-phone sync
        // system.md` § 8.2. If iOS is already queueing a transferFile
        // for this clipId (e.g., recording-end + retryPendingTransfers
        // + sessionReachabilityDidChange all firing in one window),
        // re-queueing would double-deliver. The phone-side
        // `AcceptanceCriticalSection` catches the race regardless, but
        // it's cheaper to not generate the duplicate transfer in the
        // first place.
        let alreadyQueued = session.outstandingFileTransfers.contains { transfer in
            guard let metaClipIdStr = transfer.file.metadata?["clipId"] as? String,
                  let metaClipId = UUID(uuidString: metaClipIdStr) else { return false }
            return metaClipId == clip.clipId
        }
        if alreadyQueued {
            NSLog("[HiMem][WC] watch — send(clip:) refused; clipId=\(clip.clipId) already in outstandingFileTransfers")
            return
        }

        // Pre-announce via `sendMessage` immediately before the
        // `transferFile` call so the iPhone can render an
        // IncomingCard in the sync surface BEFORE the actual file
        // data arrives. Best-effort delivery — `sendMessage` only
        // fires when both apps are reachable; if it fails the file
        // still arrives later via `transferFile` and the iPhone
        // synthesizes the in-flight entry from the manifest on
        // arrival. Spec: `screens-captured-clips-sessions.jsx`
        // § SYNC / INCOMING (2026-05-29).
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let announcePayload: [String: Any] = [
            "preAnnounce": true,
            "clipId": clip.clipId.uuidString,
            "capturedAt": clip.capturedAt.timeIntervalSince1970,
            "duration": clip.duration,
            "fileSizeBytes": fileSize,
            "latitude": clip.latitude as Any,
            "longitude": clip.longitude as Any
        ]
        if session.isReachable {
            session.sendMessage(announcePayload, replyHandler: nil) { [announcePayload] error in
                NSLog("[HiMem][WC] watch — pre-announce sendMessage failed for clipId=\(clip.clipId): \(error.localizedDescription) — falling back to transferUserInfo")
                // sendMessage requires reachable + activated on both
                // ends. If iOS rejects (e.g., WCErrorCodeNotReachable
                // when the link flapped mid-call), fall back to the
                // durable user-info queue so the iPhone still gets
                // the IncomingCard signal once reachability returns.
                _ = session.transferUserInfo(announcePayload)
            }
        } else {
            // Money 2026-06-18: when not reachable, queue the
            // pre-announce as a durable transferUserInfo so the
            // iPhone renders "Transcribing…" / IncomingCard as soon
            // as the link comes back. Without this fallback the
            // transferFile still delivers (durable) but the user
            // sees no UI between recording-end and the eventual
            // arrival — sometimes minutes for a BT wedge.
            _ = session.transferUserInfo(announcePayload)
            NSLog("[HiMem][WC] watch — pre-announce queued via transferUserInfo (not reachable); delivers on reconnect")
        }

        let metadata = clip.metadata.asWireDict()
        let transfer = session.transferFile(url, metadata: metadata)
        NSLog("[HiMem][WC] watch — transferFile queued for clipId=\(clip.clipId), reachable=\(session.isReachable), transferring=\(transfer.isTransferring)")
    }

    /// Per-clip in-flight retry counters for the "file not yet on
    /// disk" race in `send(clip:)`. Capped so a clip whose audio
    /// genuinely never finishes (recording aborted between manifest
    /// append and file write) doesn't loop forever.
    private var fileMissingRetryCounts: [UUID: Int] = [:]
    private let fileMissingRetryDelays: [UInt64] = [
        1_000_000_000,   // 1s
        5_000_000_000,   // 5s
        15_000_000_000   // 15s
    ]

    /// Schedules a delayed re-attempt at `send(clip:)` for a clip
    /// whose audio file wasn't on disk at the original call site.
    /// Idempotent across multiple triggers: if a retry is already
    /// scheduled at index N, a new call at the same index will be
    /// suppressed by the retry-count map. Different clipIds are
    /// independent.
    private func scheduleFileMissingRetry(for clip: WatchPendingClip) {
        let attempt = fileMissingRetryCounts[clip.clipId] ?? 0
        guard attempt < fileMissingRetryDelays.count else {
            NSLog("[HiMem][WC] watch — file-missing retries exhausted for clipId=\(clip.clipId); next reachability/scenePhase event will cover it")
            return
        }
        let delay = fileMissingRetryDelays[attempt]
        fileMissingRetryCounts[clip.clipId] = attempt + 1
        NSLog("[HiMem][WC] watch — scheduling file-missing retry #\(attempt + 1) for clipId=\(clip.clipId) in \(delay / 1_000_000_000)s")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            // Re-check existence; if still missing, send() will
            // schedule the next backoff (or give up at the cap).
            self.send(clip: clip)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let stateStr: String = {
            switch state {
            case .notActivated: return "notActivated"
            case .inactive: return "inactive"
            case .activated: return "activated"
            @unknown default: return "unknown"
            }
        }()
        NSLog("[HiMem][WC] watch — activated state=\(stateStr) err=\(error?.localizedDescription ?? "nil") reachable=\(session.isReachable)")
    }

    /// Pure parsing for an ack payload from the iPhone. Extracted from the
    /// delegate methods so the unit tests can drive it without a real
    /// WCSession.
    ///
    /// Accepts two wire formats:
    ///   * `{ "confirmed": "<uuid>", "kind": "clip" | "rollGroup" }`
    ///     — current shape. Routes to `lastAckedClipId` or
    ///     `lastAckedRollGroupId`.
    ///   * `{ "confirmedClipId": "<uuid>" }` — legacy shape. Routes to
    ///     `lastAckedClipId`. Kept so any acks queued by iOS's
    ///     transferUserInfo store before the format change still
    ///     deliver during the rollout window; once that queue drains
    ///     the legacy branch goes cold.
    nonisolated func handleAckPayload(_ payload: [String: Any]) {
        if let value = payload["confirmed"] as? String,
           let id = UUID(uuidString: value),
           let kind = payload["kind"] as? String {
            switch kind {
            case "rollGroup":
                NSLog("[HiMem][WC] watch — handleAckPayload accepted rollGroupId=\(id)")
                Task { @MainActor in self.lastAckedRollGroupId = id }
            case "clip":
                NSLog("[HiMem][WC] watch — handleAckPayload accepted clipId=\(id)")
                Task { @MainActor in self.lastAckedClipId = id }
            default:
                NSLog("[HiMem][WC] watch — handleAckPayload unknown kind=\(kind), id=\(id)")
            }
            return
        }
        if let str = payload["confirmedClipId"] as? String,
           let clipId = UUID(uuidString: str) {
            NSLog("[HiMem][WC] watch — handleAckPayload accepted legacy clipId=\(clipId)")
            Task { @MainActor in self.lastAckedClipId = clipId }
            return
        }
        NSLog("[HiMem][WC] watch — handleAckPayload IGNORED, keys=\(Array(payload.keys))")
    }

    /// Ack via `sendMessage` — used when both apps are reachable. Kept for
    /// the fast-path case (e.g., user actively interacting with both).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        NSLog("[HiMem][WC] watch — didReceiveMessage keys=\(Array(message.keys))")
        routeIncoming(message)
    }

    /// Routes an inbound phone payload: a `flushPending` command
    /// re-drives the pending manifest; anything else is an ack.
    /// Shared by the `sendMessage` and `transferUserInfo` delivery
    /// paths so a **durable** flush (the P1 durable-wake kick, which
    /// arrives via `transferUserInfo` to reach a backgrounded watch)
    /// is honored, not silently dropped into `handleAckPayload` and
    /// logged as IGNORED.
    nonisolated func routeIncoming(_ payload: [String: Any]) {
        if payload["command"] as? String == "flushPending" {
            Task { @MainActor in self.flushPendingManifest() }
            return
        }
        handleAckPayload(payload)
    }

    /// Pure classifier for the routing decision above — extracted so the
    /// durable-path fix is unit-checkable. `true` iff the payload is a
    /// flush command (re-drive), `false` iff it should be treated as an
    /// ack.
    nonisolated static func isFlushCommand(_ payload: [String: Any]) -> Bool {
        payload["command"] as? String == "flushPending"
    }

    /// Re-attempts `transferFile` for every clip in the manifest. Wired
    /// to the iPhone's pull-to-refresh via the `"flushPending"` command.
    /// `transferFile` is durable across launches and the system retries
    /// on its own, but the user has no signal that the system is
    /// retrying; this gives them a manual trigger. De-dupes via the
    /// system — pinging a clip that's already in flight is a no-op.
    @MainActor
    func flushPendingManifest() {
        let clips = WatchPendingManifest.shared.clips
        NSLog("[HiMem][WC] watch — flushPendingManifest (phone-requested), \(clips.count) clip(s)")
        for clip in clips {
            send(clip: clip)
        }
    }

    /// Ack via `transferUserInfo` — the background-reliable delivery path.
    /// This is the one that fires in the typical "phone locked in pocket /
    /// golf cart" scenario where reachability is false but the iPhone has
    /// queued an ack for the next time the watch app activates.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        NSLog("[HiMem][WC] watch — didReceiveUserInfo keys=\(Array(userInfo.keys))")
        // P1 (2026-07-14): route through the shared handler so a durable
        // `flushPending` (the phone's durable-wake kick) re-drives the
        // queue instead of being misread as a malformed ack.
        routeIncoming(userInfo)
    }

    /// Diagnostic — fires when a queued transferFile finishes (success or
    /// failure). The watch keeps the row in the pending manifest until the
    /// iPhone explicitly acks, regardless of transferFile completion, so
    /// this is purely observational.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            NSLog("[HiMem][WC] watch — transferFile FAILED: \(error.localizedDescription)")
        } else {
            NSLog("[HiMem][WC] watch — transferFile delivered to iPhone")
        }
    }

    /// Auto-recovery for phone-side reinstalls. When the iPhone is
    /// reinstalled, the watch's already-queued `transferFile` entries
    /// are addressed to the previous install's WC identity — iOS can't
    /// deliver them. The watch's `retryPendingTransfers` only runs on
    /// cold-launch of the watch app, so a reinstalled phone leaves
    /// pending clips silently stuck until the user force-quits the
    /// watch app.
    ///
    /// Hook the reachability transition (false → true) and re-queue
    /// everything in the manifest. `transferFile` de-dupes in-flight
    /// transfers, so this is safe to fire on any reachability change.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        NSLog("[HiMem][WC] watch — sessionReachabilityDidChange reachable=\(reachable)")
        guard reachable else { return }
        Task { @MainActor in
            self.flushPendingManifest()
        }
    }
}
