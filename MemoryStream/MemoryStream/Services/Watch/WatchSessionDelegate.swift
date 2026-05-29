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

        // Confirm receipt to the watch IMMEDIATELY, before any of the
        // async manifest/compress/transcribe work runs. The file at
        // `dest` is durably on disk — that's the only precondition for
        // a valid ack. Gating the ack behind the MainActor Task below
        // means a slow downstream step (AAC compression can take
        // ~1-2s on long clips) or an iOS background-suspend hit can
        // leave the watch showing "Hasn't reached your phone in a day"
        // even though the clip arrived. Money: 2026-05-25 — Tom saw
        // this exact symptom right after AAC compression landed. Don't
        // re-introduce the gate.
        self.sendConfirmation(clipId: clipId)
        NSLog("[Himem][WC] confirmation sent for clipId=\(clipId)")

        Task { @MainActor in
            NSLog("[Himem][WC] entering MainActor task for clipId=\(clipId)")

            if InboxManifest.shared.clips.contains(where: { $0.clipId == clipId }) {
                NSLog("[Himem][WC] clipId already in manifest, skipping accept")
                return
            }

            await Self.acceptArrivedClip(
                metadata: clipMetadata,
                masterFilename: filename
            )

            WatchInboxNotificationCoordinator.shared.clipArrived(
                clipId: clipId,
                capturedAt: clipMetadata.capturedAt
            )

            // Kick off transcription for the just-arrived row(s).
            // Without this, clips that land while the user is on the
            // session-first inbox (SessionListView) stay stuck on
            // "Transcribing…" until the next scenePhase=.active
            // transition. Money: 2026-05-25 bug.
            await Self.transcribePendingInboxClips()

            // Re-broadcast acks for ALL inbox clips, not just the one
            // that just arrived. WatchConnectivity acks can be lost
            // (sendMessage when watch unreachable, transferUserInfo
            // queue dropped on app reinstall, etc.) — and the watch
            // currently has no way to know it missed one. Every new
            // arrival is a chance to clean up the watch's stale
            // pending rows. Money: 2026-05-25 — Tom saw watch
            // continuing to show clips that had clearly landed on
            // iPhone, because their acks were lost in transit.
            self.reconcileWatchAcks()
        }
    }

    /// Runs `TranscriptionService.transcribe` against every inbox clip
    /// that hasn't had a transcription attempt yet, then records the
    /// result on the manifest row. Idempotent — already-attempted
    /// clips are skipped, so calling this from multiple seams (the
    /// arrival path in `session(_:didReceive:)` AND the scene-active
    /// backstop in `MemoryStreamApp`) is safe.
    ///
    /// Single source of truth for "make the inbox catch up on
    /// transcription." Lives here rather than on `InboxManifest` so
    /// the manifest doesn't take a hard dependency on
    /// `TranscriptionService`.
    @MainActor
    static func transcribePendingInboxClips() async {
        let pending = InboxManifest.shared.clips.filter {
            $0.transcript.isEmpty && !$0.transcriptionAttempted
        }
        guard !pending.isEmpty else { return }
        NSLog("[Himem][Inbox] transcribing \(pending.count) pending clip(s)")
        if #available(iOS 26.0, *) {
            for clip in pending {
                let url = InboxManifest.audioURL(for: clip.audioFilename)
                let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
                // Only flip `transcriptionAttempted` when the
                // recognizer ran end-to-end (`.transcribed`).
                // Model-not-installed, file-unreadable, and
                // transcriber-failed outcomes leave the clip
                // pending so the next sweep (scene-active, next
                // watch arrival, manual refresh) retries. Before
                // 2026-05-29 this branch marked every clip
                // regardless and silently burned real recordings
                // that raced the cold-launch model-install task.
                if InboxTranscriptionDispatcher.shouldMarkAttempted(for: outcome) {
                    InboxManifest.shared.recordTranscriptionAttempt(
                        clipId: clip.clipId,
                        transcript: InboxTranscriptionDispatcher.transcriptForMark(from: outcome)
                    )
                } else {
                    NSLog("[Himem][Inbox] transcribe deferred clip=\(clip.clipId.uuidString.prefix(8)) outcome=\(outcome)")
                }
            }
        }
    }

    /// Routes a freshly-received watch clip into the inbox. Single-clip
    /// sessions (no `nextTapOffsets`) become one `InboxClip` referencing
    /// the master audio file. Roll sessions (with offsets) are split
    /// via `VoiceClipSplitter` into N per-clip files + N `InboxClip`
    /// rows, all sharing the master's `rollGroupId`. The master file
    /// is removed after a successful split so disk doesn't carry both.
    ///
    /// Each finalized audio file is run through `AudioCompressor` before
    /// being referenced by the manifest. Watch clips arrive as raw
    /// Float32 PCM (~192 KB/sec) because watchOS lacks `AVAssetWriter`;
    /// the phone compresses to AAC (~4 KB/sec, ~48× smaller) so the
    /// on-device storage and CloudKit footprint stay bounded.
    /// Pure idempotency decision for `acceptArrivedClip`. Per
    /// `ClipMetadata.clipId`'s documented contract: "Idempotency key
    /// on the iPhone (a retried transfer with the same id is a
    /// no-op)." Without this check the split path (where fragments
    /// get fresh `UUID()` clipIds rather than reusing
    /// `metadata.clipId`) silently produces a fresh copy of every
    /// fragment on each redelivery — `InboxManifest.acceptClip`'s
    /// dedup is keyed on `clip.clipId` and can't see them as dupes.
    ///
    /// We treat the master as already-processed when ANY clip in the
    /// manifest matches by either:
    ///   - `clip.clipId == metadata.clipId` — single-clip path
    ///     where the InboxClip directly uses the master's clipId.
    ///   - `clip.rollGroupId == (metadata.rollGroupId ?? metadata.clipId)`
    ///     — split-clip path where every fragment carries the
    ///     master's rollGroupId.
    static func isMasterAlreadyProcessed(metadata: ClipMetadata, manifestClips: [InboxClip]) -> Bool {
        let dedupRollGroupId = metadata.rollGroupId ?? metadata.clipId
        return manifestClips.contains { clip in
            clip.clipId == metadata.clipId || clip.rollGroupId == dedupRollGroupId
        }
    }

    @MainActor
    static func acceptArrivedClip(metadata: ClipMetadata, masterFilename: String) async {
        NSLog("[Himem][WC] phone — acceptArrivedClip clipId=\(metadata.clipId) rollGroupId=\(metadata.rollGroupId?.uuidString ?? "nil") offsets=\(metadata.nextTapOffsets.count)")
        let masterURL = InboxManifest.audioURL(for: masterFilename)

        // Idempotency gate — see `isMasterAlreadyProcessed`. Drop the
        // redelivered master file so disk doesn't bloat.
        if Self.isMasterAlreadyProcessed(metadata: metadata, manifestClips: InboxManifest.shared.clips) {
            NSLog("[Himem][WC] phone — duplicate master ignored, clipId=\(metadata.clipId) already processed")
            try? FileManager.default.removeItem(at: masterURL)
            // Still ack so the watch can drop the pending row.
            // `sendConfirmation` is the path the live + durable acks
            // travel; reusing it here keeps the dedup transparent
            // to the watch side.
            WatchSessionDelegate.shared.sendConfirmation(clipId: metadata.clipId)
            return
        }

        let offsets = metadata.nextTapOffsets
        if offsets.isEmpty {
            // Single-clip session — master file IS the clip. Compress
            // before referencing so the row points at the small AAC file.
            await compressIfPossible(at: masterURL, label: "single-clip master")
            let clip = InboxClip(
                clipId: metadata.clipId,
                capturedAt: metadata.capturedAt,
                duration: metadata.duration,
                transcript: metadata.transcript,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                source: metadata.source,
                audioFilename: masterFilename,
                rollGroupId: metadata.rollGroupId
            )
            InboxManifest.shared.acceptClip(clip)
            NSLog("[Himem][WC] manifest now contains \(InboxManifest.shared.count) clip(s)")
            return
        }

        // Roll session — split the master into per-clip InboxClips
        // sharing the master's rollGroupId. Each split clip gets a
        // fresh clipId so manifest-side dedup keys stay unique.
        let rollGroupId = metadata.rollGroupId ?? metadata.clipId
        let outputDir = InboxManifest.audioDirectory
        do {
            let fragments = try await VoiceClipSplitter.split(
                masterURL: masterURL,
                nextTapOffsets: offsets,
                outputDir: outputDir,
                rollGroupId: rollGroupId
            )
            // Compress each fragment in place. The splitter writes PCM
            // outputs (uses the master's `processingFormat`); compressing
            // here turns each into AAC before manifest entry. If a
            // compress fails for one fragment, log and continue — better
            // to ship a big clip than to lose it.
            for fragment in fragments {
                let url = InboxManifest.audioURL(for: fragment.audioFilename)
                await compressIfPossible(at: url, label: "fragment \(fragment.audioFilename)")
            }
            let sessionStart = metadata.capturedAt
            // Per-clip start times: clip 1 = sessionStart;
            // clip i (i>1) = sessionStart + offsets[i-2].
            let starts: [Date] = [sessionStart] + offsets.map { sessionStart.addingTimeInterval($0) }
            for (idx, fragment) in fragments.enumerated() {
                let clip = InboxClip(
                    clipId: UUID(),
                    capturedAt: idx < starts.count ? starts[idx] : sessionStart,
                    duration: fragment.duration,
                    transcript: "",
                    latitude: metadata.latitude,
                    longitude: metadata.longitude,
                    source: metadata.source,
                    audioFilename: fragment.audioFilename,
                    rollGroupId: rollGroupId
                )
                InboxManifest.shared.acceptClip(clip)
            }
            // The master file's contents now live in the N fragments.
            try? FileManager.default.removeItem(at: masterURL)
            NSLog("[Himem][WC] split master into \(fragments.count) clips (rollGroupId=\(rollGroupId))")
        } catch {
            // Split failed — fall back to one inbox row pointing at
            // the master, so we don't lose audio. User sees the
            // unsplit recording; rollGroupId still attached. Still
            // compress so the fallback file isn't bloated either.
            NSLog("[Himem][WC] split failed (\(error.localizedDescription)), surfacing master as one clip")
            await compressIfPossible(at: masterURL, label: "fallback master")
            let clip = InboxClip(
                clipId: metadata.clipId,
                capturedAt: metadata.capturedAt,
                duration: metadata.duration,
                transcript: metadata.transcript,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                source: metadata.source,
                audioFilename: masterFilename,
                rollGroupId: metadata.rollGroupId
            )
            InboxManifest.shared.acceptClip(clip)
        }
    }

    /// Compress `url` in place to AAC. Failure is logged and swallowed
    /// — losing the size win is better than losing the clip.
    private static func compressIfPossible(at url: URL, label: String) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let before = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        do {
            try await AudioCompressor.compressInPlace(at: url)
            let after = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ratio = before > 0 && after > 0 ? Double(before) / Double(after) : 0
            NSLog("[Himem][WC] compressed \(label): \(before)→\(after) bytes (\(String(format: "%.1fx", ratio)))")
        } catch {
            NSLog("[Himem][WC] compress failed for \(label): \(error.localizedDescription) — keeping raw PCM")
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

    func sendConfirmation(clipId: UUID) {
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
