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

    func start() {
        guard WCSession.isSupported() else {
            NSLog("[Himem][WC] watch — WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        NSLog("[Himem][WC] watch — session.activate() called, reachable=\(session.isReachable)")
    }

    /// Queues a transferFile for the given clip. WatchConnectivity persists
    /// the queue across launches; if the iPhone is currently unreachable
    /// the system holds the file and ships it when reachability returns.
    func send(clip: WatchPendingClip) {
        guard WCSession.isSupported() else {
            NSLog("[Himem][WC] watch — cannot send, WCSession not supported")
            return
        }
        let session = WCSession.default
        let url = WatchPendingManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[Himem][WC] watch — file missing at \(url.path), skipping send")
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
            session.sendMessage(announcePayload, replyHandler: nil) { error in
                NSLog("[Himem][WC] watch — pre-announce sendMessage failed for clipId=\(clip.clipId): \(error.localizedDescription) (transferFile will still deliver)")
            }
        } else {
            NSLog("[Himem][WC] watch — pre-announce skipped, not reachable; file delivery is durable")
        }

        let metadata = clip.metadata.asWireDict()
        let transfer = session.transferFile(url, metadata: metadata)
        NSLog("[Himem][WC] watch — transferFile queued for clipId=\(clip.clipId), reachable=\(session.isReachable), transferring=\(transfer.isTransferring)")
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
        NSLog("[Himem][WC] watch — activated state=\(stateStr) err=\(error?.localizedDescription ?? "nil") reachable=\(session.isReachable)")
    }

    /// Pure parsing for an ack payload from the iPhone. Extracted from the
    /// delegate methods so the unit tests can drive it without a real
    /// WCSession. Sets `lastAckedClipId` on the main actor when the payload
    /// contains a valid `confirmedClipId`; no-op otherwise.
    nonisolated func handleAckPayload(_ payload: [String: Any]) {
        guard let str = payload["confirmedClipId"] as? String,
              let clipId = UUID(uuidString: str) else {
            NSLog("[Himem][WC] watch — handleAckPayload IGNORED, keys=\(Array(payload.keys))")
            return
        }
        NSLog("[Himem][WC] watch — handleAckPayload accepted clipId=\(clipId)")
        Task { @MainActor in
            self.lastAckedClipId = clipId
        }
    }

    /// Ack via `sendMessage` — used when both apps are reachable. Kept for
    /// the fast-path case (e.g., user actively interacting with both).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        NSLog("[Himem][WC] watch — didReceiveMessage keys=\(Array(message.keys))")
        if message["command"] as? String == "flushPending" {
            Task { @MainActor in self.flushPendingManifest() }
            return
        }
        handleAckPayload(message)
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
        NSLog("[Himem][WC] watch — flushPendingManifest (phone-requested), \(clips.count) clip(s)")
        for clip in clips {
            send(clip: clip)
        }
    }

    /// Ack via `transferUserInfo` — the background-reliable delivery path.
    /// This is the one that fires in the typical "phone locked in pocket /
    /// golf cart" scenario where reachability is false but the iPhone has
    /// queued an ack for the next time the watch app activates.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        NSLog("[Himem][WC] watch — didReceiveUserInfo keys=\(Array(userInfo.keys))")
        handleAckPayload(userInfo)
    }

    /// Diagnostic — fires when a queued transferFile finishes (success or
    /// failure). The watch keeps the row in the pending manifest until the
    /// iPhone explicitly acks, regardless of transferFile completion, so
    /// this is purely observational.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            NSLog("[Himem][WC] watch — transferFile FAILED: \(error.localizedDescription)")
        } else {
            NSLog("[Himem][WC] watch — transferFile delivered to iPhone")
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
        NSLog("[Himem][WC] watch — sessionReachabilityDidChange reachable=\(reachable)")
        guard reachable else { return }
        Task { @MainActor in
            self.flushPendingManifest()
        }
    }
}
