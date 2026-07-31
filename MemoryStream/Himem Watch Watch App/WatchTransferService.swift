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

    /// Transfer-speed instrumentation (2026-07-14, `[XferPerf]`). Per
    /// clipId: the wall-clock at `transferFile` enqueue + the file's
    /// byte size, so `didFinish` can log elapsed + throughput. Single
    /// device / single clock — avoids watch↔phone skew. Diagnostic
    /// only; confirms whether the ~50× slowness is payload size
    /// (encoding) or bytes/sec (WCSession throttling) before we decide
    /// on watch-side compression vs an iCloud transport.
    private var xferStart: [UUID: (at: Date, bytes: Int)] = [:]

    func start() {
        guard WCSession.isSupported() else {
            NSLog("[HiMem][WC] watch — WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Cold-launch net for the delivered-awaiting-ack suppression (see
        // `shouldEnqueue`). A fresh process starts with an empty set anyway;
        // clearing here states the guarantee explicitly rather than relying
        // on instantiation, so a future shared/re-used instance can't silently
        // strand a clip whose ack never arrived.
        deliveredAwaitingAck.removeAll()
        NSLog("[HiMem][WC] watch — session.activate() called, reachable=\(session.isReachable)")
    }

    /// Queues a transferFile for the given clip. WatchConnectivity persists
    /// the queue across launches; if the iPhone is currently unreachable
    /// the system holds the file and ships it when reachability returns.
    /// clipIds with a transcode currently running — idempotency guard so
    /// the several send triggers (record-end, retryPendingTransfers,
    /// reachability, scenePhase, flushPending) don't re-encode the same
    /// clip concurrently.
    private var transcodingClipIds: Set<UUID> = []

    /// Entry point for every send trigger. Ensures a **transfer-ready
    /// mono/16k/AAC artifact** exists for the clip (4a · `Watch · spec.md`
    /// §2), then hands *that* to `transferFile` — the raw PCM never ships.
    ///
    /// The transcode runs **off-main** (whole-file read + AVAudioConverter)
    /// and is idempotent: a clip whose `.m4a` is already ready+complete is
    /// transferred without re-encoding. It is **never** run in
    /// `WatchRecordingService.stop` — stop doesn't sync-drain the write
    /// queue (a sync drain trips the watchOS watchdog), so we transcode on
    /// the send path, after the file finalizes, and the completeness gate
    /// (`isTransferReadyAndComplete`) rejects a source that hadn't drained.
    func send(clip: WatchPendingClip) {
        guard WCSession.isSupported() else {
            NSLog("[HiMem][WC] watch — cannot send, WCSession not supported")
            return
        }
        let rawURL = WatchPendingManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            NSLog("[HiMem][WC] watch — file missing at \(rawURL.path), skipping send")
            // Money 2026-06-18: recording-end async drain may still be
            // flushing. Backoff retry so the clip ships once the write
            // completes; reachability/scenePhase/cold-launch also cover it.
            scheduleFileMissingRetry(for: clip)
            return
        }

        let aacURL = WatchPendingManifest.transferAudioURL(forAudioFilename: clip.audioFilename)

        // Idempotent fast path: a ready+complete AAC already exists →
        // transfer it now, no re-encode. (Every retry trigger re-enters
        // here.)
        if WatchTransferAudioTranscoder.isTransferReadyAndComplete(aacURL, expectedSeconds: clip.duration) {
            enqueueReadyTransfer(clip: clip, fileURL: aacURL)
            return
        }
        // A transcode for this clip is already running → let it finish and
        // enqueue.
        guard !transcodingClipIds.contains(clip.clipId) else { return }
        transcodingClipIds.insert(clip.clipId)

        // Detached → off-main (the project's `NonisolatedNonsendingByDefault`
        // makes a plain nonisolated async inherit the caller's actor, so
        // `Task.detached` is what actually leaves the main thread). Reports
        // back through a `@MainActor` method — no captured `var`, no
        // `MainActor.run`. `self` (a `@MainActor` class) is Sendable, and
        // the task is short-lived, so the strong capture is not a cycle.
        Task.detached(priority: .utility) { [rawURL, aacURL, clip] in
            let transcodeError: String?
            do {
                try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: rawURL, destination: aacURL)
                transcodeError = nil
            } catch {
                transcodeError = "\(error)"
            }
            await self.transcodeFinished(clip: clip, aacURL: aacURL, error: transcodeError)
        }
    }

    /// `@MainActor` continuation of `send`'s transcode. Enqueues the AAC if
    /// it's ready+complete, else schedules a short retry (source hadn't
    /// finalized). Never ships raw.
    private func transcodeFinished(clip: WatchPendingClip, aacURL: URL, error: String?) {
        transcodingClipIds.remove(clip.clipId)
        if WatchTransferAudioTranscoder.isTransferReadyAndComplete(aacURL, expectedSeconds: clip.duration) {
            NSLog("[HiMem][WC] watch — transcoded clipId=\(clip.clipId) → \(aacURL.lastPathComponent); enqueuing")
            enqueueReadyTransfer(clip: clip, fileURL: aacURL)
        } else {
            NSLog("[HiMem][WC] watch — clipId=\(clip.clipId) not transfer-ready after transcode (err=\(error ?? "nil")); scheduling retry")
            scheduleTranscodeRetry(for: clip)
        }
    }

    /// clipIds whose bytes WCSession has already delivered to the iPhone but
    /// which the iPhone has not yet acked, mapped to the `rollGroupId` they
    /// shipped under (nil when the clip belongs to no roll group).
    ///
    /// The rollGroupId is carried here — rather than looked up in
    /// `WatchPendingManifest` at ack time — so **both** ack paths can maintain
    /// this state from the payload alone. A manifest lookup would only work
    /// while the rows still exist, i.e. it would depend on running before the
    /// coordinator's sink removes them: an ordering coincidence, not an
    /// invariant. Two ack paths where only one maintains the state is the exact
    /// shape of the duplicate-delivery bug this whole gate exists to fix.
    ///
    /// Internal (not private) so the money tests can observe it directly under
    /// `@testable import`. See `shouldEnqueue`.
    var deliveredAwaitingAck: [UUID: UUID?] = [:]

    /// The clipIds WCSession currently has in flight. Pulled out so
    /// `shouldEnqueue` takes plain values and needs no live session.
    private static func outstandingClipIds(in session: WCSession) -> Set<UUID> {
        Set(session.outstandingFileTransfers.compactMap { transfer in
            (transfer.file.metadata?["clipId"] as? String).flatMap(UUID.init)
        })
    }

    /// Whether this clip's bytes should be handed to `transferFile`.
    ///
    /// **The invariant: bytes already delivered are never re-shipped.** A clip
    /// is refused when it is either still in flight (`outstanding` — the
    /// original §8.2 double-delivery belt) or already delivered and merely
    /// waiting for the iPhone's ack (`deliveredAwaitingAck`). The **ack** is
    /// what clears the manifest row; a re-ship never was.
    ///
    /// Both sets matter because they are different states, and conflating them
    /// is the 4×-duplicate-delivery defect (dogfood 2026-07-29):
    /// `outstandingFileTransfers` drops a transfer the moment it completes,
    /// while the manifest row survives until the ack — so between those two
    /// moments the clip looked un-sent and every `flushPendingManifest`
    /// trigger shipped the entire file again.
    ///
    /// Pure and value-driven so the money tests can exercise every combination
    /// without a real `WCSession` — same shape as
    /// `WatchRecordingService.WaveformLevelThrottle.observe`. `nonisolated`
    /// because no actor state is touched.
    nonisolated static func shouldEnqueue(
        clipId: UUID,
        outstanding: Set<UUID>,
        deliveredAwaitingAck: Set<UUID>
    ) -> Bool {
        !outstanding.contains(clipId) && !deliveredAwaitingAck.contains(clipId)
    }

    /// Enqueues the actual `transferFile` for an already-verified
    /// mono/16k/AAC artifact. The `isTransferReady` guard is the **final
    /// gate** — a file that fails the assertion never ships (`Watch ·
    /// spec.md` §2). Pre-announce + de-dup unchanged, now carrying the
    /// compressed size.
    private func enqueueReadyTransfer(clip: WatchPendingClip, fileURL: URL) {
        transcodeRetryCounts[clip.clipId] = nil
        guard WatchTransferAudioTranscoder.isTransferReady(fileURL) else {
            NSLog("[HiMem][WC] watch — REFUSED transfer clipId=\(clip.clipId): file not mono/16k/AAC")
            return
        }
        let session = WCSession.default

        // Belt against the double-delivery race (§ 8.2). Decision extracted
        // to `shouldEnqueue` so it's testable without a real WCSession.
        let outstanding = Self.outstandingClipIds(in: session)
        let delivered = Set(deliveredAwaitingAck.keys)
        guard Self.shouldEnqueue(
            clipId: clip.clipId,
            outstanding: outstanding,
            deliveredAwaitingAck: delivered
        ) else {
            NSLog("[HiMem][WC] watch — enqueue refused; clipId=\(clip.clipId) outstanding=\(outstanding.contains(clip.clipId)) deliveredAwaitingAck=\(delivered.contains(clip.clipId))")
            return
        }

        // Pre-announce so the iPhone renders an IncomingCard before the
        // bytes land. Best-effort sendMessage when reachable, durable
        // transferUserInfo otherwise. fileSizeBytes now = compressed size.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
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
                _ = session.transferUserInfo(announcePayload)
            }
        } else {
            _ = session.transferUserInfo(announcePayload)
            NSLog("[HiMem][WC] watch — pre-announce queued via transferUserInfo (not reachable); delivers on reconnect")
        }

        let metadata = clip.metadata.asWireDict()
        let transfer = session.transferFile(fileURL, metadata: metadata)
        NSLog("[HiMem][WC] watch — transferFile queued for clipId=\(clip.clipId) (compressed \(fileSize) B), reachable=\(session.isReachable), transferring=\(transfer.isTransferring)")

        // [XferPerf] instrumentation — moved here on the 4a rebase: this
        // (enqueueReadyTransfer) is the real transferFile site now, after the
        // transcode. `fileSize` is the COMPRESSED artifact; `didFinish`
        // computes elapsed + throughput against the stamp below. On a healthy
        // 4a build these read ~230 KB / seconds — not ~33 MB / minutes.
        xferStart[clip.clipId] = (Date(), fileSize)
        let kb = Double(fileSize) / 1024.0
        NSLog(String(
            format: "[HiMem][WC][XferPerf] enqueued clipId=%@ bytes=%d (%.0f KB) audio=%.1fs bytesPerAudioSec=%.0f reachable=%@",
            clip.clipId.uuidString, fileSize, kb, clip.duration,
            clip.duration > 0 ? Double(fileSize) / clip.duration : 0,
            session.isReachable ? "true" : "false"
        ))
    }

    /// Short backoff retry for the "transcoded but source hadn't finalized"
    /// case. 0.5s / 2s / 5s covers the write-queue drain window; past that,
    /// the next reachability/scenePhase trigger re-attempts.
    private var transcodeRetryCounts: [UUID: Int] = [:]
    private let transcodeRetryDelays: [UInt64] = [500_000_000, 2_000_000_000, 5_000_000_000]

    private func scheduleTranscodeRetry(for clip: WatchPendingClip) {
        let attempt = transcodeRetryCounts[clip.clipId] ?? 0
        guard attempt < transcodeRetryDelays.count else {
            NSLog("[HiMem][WC] watch — transcode retries exhausted for clipId=\(clip.clipId); next reachability/scenePhase event will cover it")
            return
        }
        let delay = transcodeRetryDelays[attempt]
        transcodeRetryCounts[clip.clipId] = attempt + 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            self?.send(clip: clip)
        }
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
        // THE ESCAPE HATCH for the delivered-awaiting-ack suppression, and the
        // reason that suppression is safe (see `shouldEnqueue`). Activation is
        // when the phone presents its WC identity — including a NEW identity
        // after a reinstall, which is exactly the case where an ack will never
        // arrive for bytes we already delivered. Clearing here means the clip
        // stranded by a reinstall is re-shipped by the very event that
        // stranded it; the suppression only holds while the identity is stable
        // and the bytes are known-landed, which is precisely when re-shipping
        // is pure waste. Without this, fixing the duplicate storm would
        // reintroduce the stuck-clip bug the reachability flush exists to fix.
        Task { @MainActor [weak self] in
            guard let self, !self.deliveredAwaitingAck.isEmpty else { return }
            NSLog("[HiMem][WC] watch — activation cleared \(self.deliveredAwaitingAck.count) delivered-awaiting-ack clip(s); they may re-ship")
            self.deliveredAwaitingAck.removeAll()
        }
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
                Task { @MainActor in
                    // A rollGroup ack confirms every member clip at once
                    // (§8.7), so it releases every member's suppression —
                    // symmetric with the per-clip ack. Membership comes from
                    // the state we recorded at delivery, not from a manifest
                    // lookup, so this does not depend on running before the
                    // coordinator's sink prunes the rows.
                    let released = self.deliveredAwaitingAck.filter { $0.value == id }.keys
                    for clipId in released {
                        self.deliveredAwaitingAck.removeValue(forKey: clipId)
                    }
                    if !released.isEmpty {
                        NSLog("[HiMem][WC] watch — rollGroup ack released \(released.count) delivered-awaiting-ack clip(s)")
                    }
                    self.lastAckedRollGroupId = id
                }
            case "clip":
                NSLog("[HiMem][WC] watch — handleAckPayload accepted clipId=\(id)")
                Task { @MainActor in
                    self.deliveredAwaitingAck.removeValue(forKey: id)
                    self.lastAckedClipId = id
                }
            default:
                NSLog("[HiMem][WC] watch — handleAckPayload unknown kind=\(kind), id=\(id)")
            }
            return
        }
        if let str = payload["confirmedClipId"] as? String,
           let clipId = UUID(uuidString: str) {
            NSLog("[HiMem][WC] watch — handleAckPayload accepted legacy clipId=\(clipId)")
            Task { @MainActor in
                self.deliveredAwaitingAck.removeValue(forKey: clipId)
                self.lastAckedClipId = clipId
            }
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
        // Capture the completion instant + clipId before hopping actors,
        // so the elapsed measurement isn't polluted by scheduling delay.
        let finishedAt = Date()
        let clipId = (fileTransfer.file.metadata?["clipId"] as? String).flatMap(UUID.init)
        let rollGroupId = (fileTransfer.file.metadata?["rollGroupId"] as? String).flatMap(UUID.init)
        if let error {
            NSLog("[HiMem][WC] watch — transferFile FAILED: \(error.localizedDescription)")
        } else {
            NSLog("[HiMem][WC] watch — transferFile delivered to iPhone")
            // The bytes are on the phone. Suppress re-shipping until the ack
            // lands (or activation clears it) — see `shouldEnqueue`. The
            // manifest row deliberately stays until the ack; this only stops
            // us sending the same file again in the meantime.
            if let clipId {
                Task { @MainActor [weak self] in
                    self?.deliveredAwaitingAck[clipId] = rollGroupId
                }
            }
        }
        // [XferPerf] elapsed + throughput for this clip. This is THE
        // number that answers the ~50× question: high bytes but low
        // KB/s ⇒ throttled transport; small elapsed once it starts ⇒
        // the delay was wait-to-begin (P1 territory), not throughput.
        Task { @MainActor [weak self] in
            guard let self, let clipId, let start = self.xferStart.removeValue(forKey: clipId) else { return }
            let elapsed = finishedAt.timeIntervalSince(start.at)
            let kbps = elapsed > 0 ? (Double(start.bytes) / 1024.0) / elapsed : 0
            NSLog(String(
                format: "[HiMem][WC][XferPerf] delivered clipId=%@ bytes=%d elapsed=%.1fs throughput=%.1f KB/s outcome=%@",
                clipId.uuidString, start.bytes, elapsed, kbps,
                error == nil ? "ok" : "failed"
            ))
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
    /// everything in the manifest.
    ///
    /// **This used to claim "`transferFile` de-dupes in-flight transfers, so
    /// this is safe to fire on any reachability change." That guarantee does
    /// not exist, and the comment was the bug** (dogfood 2026-07-29: one 21 s
    /// clip delivered four times). `outstandingFileTransfers` covers only
    /// transfers that have not yet *completed*; it says nothing about a clip
    /// whose bytes already landed and which is merely waiting for the iPhone's
    /// ack. Reachability flaps repeatedly in normal use, so each `true`
    /// re-shipped the whole file.
    ///
    /// What actually makes this safe is the **delivered-awaiting-ack** state
    /// (`shouldEnqueue`) — a state the code previously had no concept of.
    /// Firing on every reachability change is fine *because* that gate exists;
    /// it is not fine on its own.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        NSLog("[HiMem][WC] watch — sessionReachabilityDidChange reachable=\(reachable)")
        guard reachable else { return }
        Task { @MainActor in
            self.flushPendingManifest()
        }
    }
}
