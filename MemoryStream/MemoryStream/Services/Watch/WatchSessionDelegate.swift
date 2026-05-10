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
            NotificationService.shared.notifyInboxArrival()
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
    /// Watch removes the row from its local pending manifest. If the watch
    /// is unreachable right now, we drop the message — but the clip is
    /// already in our inbox; on the next watch reachability the watch will
    /// retransfer, hit our idempotency check, and we'll send the
    /// confirmation again.
    ///
    /// Uses `transferUserInfo` (not `sendMessage`) because the latter
    /// requires `isReachable == true` — meaning both apps actively running.
    /// In normal flow the iPhone is locked / backgrounded after the watch
    /// records, so reachability is false and `sendMessage` would silently
    /// no-op. `transferUserInfo` queues the payload and delivers it the
    /// next time the watch app activates, which is what we want.
    private func sendConfirmation(clipId: UUID) {
        let transfer = WCSession.default.transferUserInfo(["confirmedClipId": clipId.uuidString])
        NSLog("[Himem][WC] iPhone — transferUserInfo queued for clipId=\(clipId), transferring=\(transfer.isTransferring)")
    }
}
