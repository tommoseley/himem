import Foundation
import WatchConnectivity

/// iPhone-side WatchConnectivity bridge. Handles incoming `transferFile`
/// payloads from the watch app, atomically persists each clip's audio +
/// manifest entry, then sends a confirmation message back so the watch
/// removes the clip from its pending list.
///
/// Activated once at app launch from MemoryStreamApp. The delegate keeps
/// the WCSession alive for the lifetime of the process and handles
/// background-delivered files (the system wakes us to receive them even
/// when HiMem isn't foregrounded).
final class WatchSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = WatchSessionDelegate()

    /// Activates the WCSession. No-op if WatchConnectivity isn't supported
    /// (e.g., iPad). Safe to call multiple times — `activate()` is
    /// idempotent.
    func start() {
        guard WCSession.isSupported() else {
            NSLog("[Himem][WC] WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        NSLog("[Himem][WC] iPhone session activate() called — paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled)")
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let stateStr: String = {
            switch state {
            case .notActivated: return "notActivated"
            case .inactive: return "inactive"
            case .activated: return "activated"
            @unknown default: return "unknown"
            }
        }()
        NSLog("[Himem][WC] iPhone session activated — state=\(stateStr) err=\(error?.localizedDescription ?? "nil") paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so transfers from a freshly-paired or re-paired watch
        // continue to land. Apple's recommended pattern.
        WCSession.default.activate()
    }

    // MARK: - File transfer

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        NSLog("[Himem][WC] iPhone received file at \(file.fileURL.path), metadata keys: \(file.metadata?.keys.map { String(describing: $0) } ?? [])")

        // Decode metadata first — without it we don't know what to call the
        // file or what to write to the manifest. Drop the transfer if the
        // metadata is malformed (better to lose one bad clip than corrupt
        // the inbox).
        guard let metadataDict = file.metadata,
              let clipMetadata = ClipMetadata.fromWireDict(metadataDict)
        else {
            NSLog("[Himem][WC] dropping file — metadata missing or malformed")
            return
        }

        let clipId = clipMetadata.clipId
        NSLog("[Himem][WC] decoded clipId=\(clipId), duration=\(clipMetadata.duration)")

        // The system deletes file.fileURL after this delegate method
        // returns. We MUST move the file synchronously here, before the
        // Task hop, otherwise it's gone by the time we try to read it.
        let filename = "\(clipId.uuidString).caf"
        let dest = InboxManifest.audioURL(for: filename)
        let source = file.fileURL

        // If the destination already exists, this is a re-delivery —
        // skip the copy. Otherwise copy from the system staging path.
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
                NSLog("[Himem][WC] copied audio to \(dest.path)")
            } catch {
                NSLog("[Himem][WC] FAILED to copy audio from \(source.path) to \(dest.path): \(error.localizedDescription)")
                return
            }
        } else {
            NSLog("[Himem][WC] audio already at \(dest.path), skipping copy")
        }

        Task { @MainActor in
            NSLog("[Himem][WC] entering MainActor task for clipId=\(clipId)")

            if InboxManifest.shared.clips.contains(where: { $0.clipId == clipId }) {
                NSLog("[Himem][WC] clipId already in manifest, sending dup confirmation")
                self.sendConfirmation(clipId: clipId)
                return
            }

            let clip = InboxClip(
                clipId: clipId,
                capturedAt: clipMetadata.capturedAt,
                duration: clipMetadata.duration,
                transcript: clipMetadata.transcript,
                latitude: clipMetadata.latitude,
                longitude: clipMetadata.longitude,
                source: clipMetadata.source,
                audioFilename: filename
            )
            InboxManifest.shared.acceptClip(clip)
            NSLog("[Himem][WC] manifest now contains \(InboxManifest.shared.count) clip(s)")
            // Drive the inbox notification through the policy
            // coordinator (burst / threshold / stale). It owns
            // foreground suppression, daily cap, quiet hours, snooze /
            // mute state, and per-clip stale scheduling — so we no
            // longer fire a push on every clip arrival.
            WatchInboxNotificationCoordinator.shared.clipArrived(
                clipId: clipId,
                capturedAt: clipMetadata.capturedAt
            )
            self.sendConfirmation(clipId: clipId)
            NSLog("[Himem][WC] confirmation sent for clipId=\(clipId)")

            // Watch ships clips with empty transcripts (on-watch
            // transcription was deferred). Kick off iPhone-side
            // transcription so the inbox row gets its preview text.
            if clipMetadata.transcript.isEmpty {
                Task { await self.transcribeAsync(clipId: clipId, audioURL: dest) }
            }
        }
    }

    /// Run on-device transcription over the saved audio file and update
    /// the inbox manifest. Uses the iOS-26 `TranscriptionService`
    /// (SpeechAnalyzer-backed) — handles long-form audio without the
    /// SFSpeechRecognizer 60-second / multi-final-callback failure modes
    /// the legacy path was prone to. Result is recorded as "attempted"
    /// regardless of outcome so the inbox UI distinguishes pending from
    /// no-speech.
    private func transcribeAsync(clipId: UUID, audioURL: URL) async {
        let result = await TranscriptionService.shared.transcribe(audioURL: audioURL)
        await MainActor.run {
            InboxManifest.shared.recordTranscriptionAttempt(clipId: clipId, transcript: result.text)
            NSLog("[Himem][WC] transcription attempted for clipId=\(clipId), length=\(result.text.count)")
        }
    }

    /// Notifies the watch that a clipId has been received and persisted.
    /// Watch removes the row from its local pending manifest, which
    /// updates `WatchSharedState.pendingCount` and refreshes the
    /// complication.
    ///
    /// Dual-path delivery:
    ///   1. **`sendMessage` (fast)** — when the watch session is currently
    ///      reachable (user looking at watch / app recently active), the
    ///      message lands immediately. This is the common path right
    ///      after a fresh recording: user takes clip, watches the
    ///      transfer, and the pending count clears in real time.
    ///   2. **`transferUserInfo` (durable)** — always queued as backup so
    ///      that if the watch goes to sleep or is out of range, the ack
    ///      still delivers when the watch next activates. The watch's
    ///      `handleAckPayload` is idempotent — re-sets of the same
    ///      `@Published lastAckedClipId` to the same value don't re-fire
    ///      the Combine sink, so receiving via both paths is harmless.
    ///
    /// Previously we used `transferUserInfo` only. Durable, but the
    /// system delays its delivery to "when appropriate" — typically
    /// seconds to minutes when the watch app isn't running — so the
    /// complication's pending count stayed stale visibly long enough to
    /// look like a bug.
    /// Asks the watch to re-attempt every clip in its pending manifest.
    /// Wired to the journal's pull-to-refresh so the user has an
    /// explicit "kick the watch" affordance for the case where the
    /// watch queued clips while out of range. `transferFile` is
    /// already durable and the system retries when reachability
    /// returns, but the user can't see that — this gives them a way
    /// to nudge it, and the watch's `retryPendingTransfers` is a
    /// cheap no-op when nothing's queued.
    ///
    /// Best-effort: requires the watch app to be currently reachable.
    /// If the watch is offline (the very case the user is hedging
    /// against), the message can't be delivered — the system's own
    /// background retry is the fallback. We don't queue this via
    /// `transferUserInfo` because by the time the watch becomes
    /// reachable to receive it, the system has already retried the
    /// pending transfers on its own.
    func requestWatchPendingFlush() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            NSLog("[Himem][WC] iPhone — flush request skipped: session not activated")
            return
        }
        guard session.isReachable else {
            NSLog("[Himem][WC] iPhone — flush request skipped: watch not reachable")
            return
        }
        let payload: [String: Any] = ["command": "flushPending"]
        session.sendMessage(payload, replyHandler: nil) { error in
            NSLog("[Himem][WC] iPhone — flush request failed: \(error.localizedDescription)")
        }
        NSLog("[Himem][WC] iPhone — flush request sent")
    }

    private func sendConfirmation(clipId: UUID) {
        let session = WCSession.default
        let payload: [String: Any] = ["confirmedClipId": clipId.uuidString]

        // Fast path — try `sendMessage` unconditionally. We previously
        // guarded on `session.isReachable`, but the iPhone's view of
        // reachability is stale when the iPhone has been backgrounded
        // and only briefly woken by WC to handle `didReceive(file:)` —
        // `isReachable` reports false even when the watch is actively
        // foreground. `sendMessage` itself succeeds in some of those
        // windows the guard rejects, and when it fails it just calls
        // the errorHandler (no exception, no side effect) — the
        // durable transferUserInfo below covers either way.
        session.sendMessage(payload, replyHandler: nil) { error in
            NSLog("[Himem][WC] iPhone — sendMessage confirmation failed for clipId=\(clipId): \(error.localizedDescription) (transferUserInfo backup will deliver)")
        }
        NSLog("[Himem][WC] iPhone — sendMessage confirmation attempted for clipId=\(clipId)")

        // Durable backup — always queued. System delivers when watch
        // next activates / both apps next become reachable.
        let transfer = session.transferUserInfo(payload)
        NSLog("[Himem][WC] iPhone — transferUserInfo queued for clipId=\(clipId), transferring=\(transfer.isTransferring)")
    }

    /// Re-asserts every clip the iPhone already holds in its inbox to the
    /// watch via the ack pipeline. Called on iPhone scene-active so any
    /// clip whose ack got stuck in the system's transferUserInfo queue
    /// while the iPhone was backgrounded clears on the watch the moment
    /// the user opens the iPhone app.
    ///
    /// `pending.remove(clipId:)` on the watch side is idempotent — clips
    /// already removed are a no-op, so re-sending acks costs only the
    /// per-message bandwidth.
    @MainActor
    func reconcileWatchAcks() {
        let clipIds = InboxManifest.shared.clips.map(\.clipId)
        guard !clipIds.isEmpty else {
            NSLog("[Himem][WC] iPhone — reconcileWatchAcks: inbox empty, nothing to assert")
            return
        }
        NSLog("[Himem][WC] iPhone — reconcileWatchAcks: re-asserting \(clipIds.count) clip(s) to watch")
        for clipId in clipIds {
            sendConfirmation(clipId: clipId)
        }
    }
}
