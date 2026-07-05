import Foundation
import AVFoundation
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
            NSLog("[HiMem][WC] WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        NSLog("[HiMem][WC] iPhone session activate() called — paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled)")
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
        NSLog("[HiMem][WC] iPhone session activated — state=\(stateStr) err=\(error?.localizedDescription ?? "nil") paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so transfers from a freshly-paired or re-paired watch
        // continue to land. Apple's recommended pattern.
        WCSession.default.activate()
    }

    /// Pauses / resumes in-flight clips based on session reachability.
    /// Spec § SYNC / INCOMING screen 3 ("Stalled · Watch out of
    /// range"): when reachability drops while any clip is downloading
    /// or waiting, transition them to `.paused`. When it returns,
    /// resume the oldest as `.downloading`.
    ///
    /// `isReachable` is a proxy — iOS doesn't expose Bluetooth
    /// proximity directly. False here can also mean the watch app
    /// is backgrounded; for the user-facing case (Captured Clips
    /// open, transfer stalled mid-flight) the signal is correct.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        NSLog("[HiMem][WC] iPhone — sessionReachabilityDidChange reachable=\(reachable)")
        Task { @MainActor in
            if reachable {
                InboxArrivalTracker.shared.recordReachabilityRestored()
            } else {
                InboxArrivalTracker.shared.recordReachabilityLost()
            }
        }
    }

    /// Completion observer for outbound `transferUserInfo` transfers
    /// (iPhone-side acks back to the watch, and any other user-info
    /// payloads we may add). Before this method existed the
    /// transfers were fire-and-forget — a permanently-failed ack
    /// (e.g., watch app uninstalled, queue corrupted) would never
    /// surface anywhere. Now persistent failures are at least loud
    /// in the device log so we can diagnose stuck-queue scenarios.
    /// We do NOT auto-retry from this method: WC's own retry
    /// behavior is durable across reconnects, and re-queueing on
    /// error risks duplicate delivery once the original eventually
    /// lands.
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let kind = (userInfoTransfer.userInfo["kind"] as? String) ?? "unknown"
        let confirmedId = (userInfoTransfer.userInfo["confirmed"] as? String) ?? "n/a"
        if let error {
            NSLog("[HiMem][WC] iPhone — transferUserInfo FAILED kind=\(kind) confirmed=\(confirmedId): \(error.localizedDescription)")
        } else {
            NSLog("[HiMem][WC] iPhone — transferUserInfo delivered kind=\(kind) confirmed=\(confirmedId)")
        }
    }

    /// Completion observer for outbound `transferFile` (iPhone-side
    /// — not used today, all file transfers originate on the watch).
    /// Stub here so when we add iPhone→watch file paths in future
    /// (e.g., recovery/restore) the failure mode is visible from
    /// day one rather than silent.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            NSLog("[HiMem][WC] iPhone — transferFile FAILED url=\(fileTransfer.file.fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Message (pre-announce path)

    /// Receives `sendMessage` payloads from the watch. The only
    /// expected payload today is the pre-announce that's sent
    /// immediately before each `transferFile` — see
    /// `WatchTransferService.send(clip:)` and the parsing/wiring
    /// in `WatchPreAnnounceParser`.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        routePreAnnounceIfPossible(payload: message, transport: "sendMessage")
    }

    /// Durable backstop for the pre-announce. When the watch is
    /// unreachable at the moment of `send(clip:)`, it queues the
    /// announce via `transferUserInfo` instead of `sendMessage`. iOS
    /// holds the user-info entry and delivers it the next time the
    /// pair is reachable, so the iPhone gets the IncomingCard signal
    /// even if reachability was wedged at recording-end. Money
    /// 2026-06-18: matches the BT-wedge symptom Tom saw — paired
    /// watch reports unreachable, clip arrives via transferFile
    /// (durable) but no pre-announce ever lands, so the user sees
    /// no "Transcribing…" UI between recording-end and arrival.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        routePreAnnounceIfPossible(payload: userInfo, transport: "transferUserInfo")
    }

    private func routePreAnnounceIfPossible(payload: [String: Any], transport: String) {
        guard let parsed = WatchPreAnnounceParser.parse(payload) else {
            NSLog("[HiMem][WC] iPhone — \(transport) ignored, keys=\(Array(payload.keys))")
            return
        }
        NSLog("[HiMem][WC] iPhone — pre-announce (\(transport)) received for clipId=\(parsed.clipId) duration=\(parsed.durationSeconds)s")
        Task { @MainActor in
            // Gate against the late pre-announce race: if the
            // delivery was delayed by a hop through the WC layer
            // while transferFile delivered + processed quickly, the
            // clip is already in the manifest by the time we get
            // here. Adding an InFlightClip entry now would orphan it
            // (the transcribe sweep already ran). Same for clips the
            // user already disposed of — pre-announce shouldn't
            // resurrect.
            if InboxManifest.shared.clips.contains(where: { $0.clipId == parsed.clipId }) {
                NSLog("[HiMem][WC] iPhone — pre-announce ignored; clipId=\(parsed.clipId) already in manifest")
                return
            }
            if InboxManifest.shared.status(for: parsed.clipId) == .disposed {
                NSLog("[HiMem][WC] iPhone — pre-announce ignored; clipId=\(parsed.clipId) already disposed (manifest tombstone)")
                return
            }
            InboxArrivalTracker.shared.recordPreAnnounce(
                clipId: parsed.clipId,
                capturedAt: parsed.capturedAt,
                durationSeconds: parsed.durationSeconds,
                latitude: parsed.latitude,
                longitude: parsed.longitude,
                fileSizeBytes: parsed.fileSizeBytes
            )
        }
    }

    // MARK: - File transfer

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        NSLog("[HiMem][WC] iPhone received file at \(file.fileURL.path), metadata keys: \(file.metadata?.keys.map { String(describing: $0) } ?? [])")

        // Decode metadata first — without it we don't know what to call the
        // file or what to write to the manifest. Drop the transfer if the
        // metadata is malformed (better to lose one bad clip than corrupt
        // the inbox).
        guard let metadataDict = file.metadata,
              let clipMetadata = ClipMetadata.fromWireDict(metadataDict)
        else {
            NSLog("[HiMem][WC] dropping file — metadata missing or malformed")
            return
        }

        let clipId = clipMetadata.clipId
        NSLog("[HiMem][WC] decoded clipId=\(clipId), duration=\(clipMetadata.duration)")

        // B5 dedup: if this clipId is a tombstone in the manifest
        // (status == .disposed), iOS is ghost-redelivering it from
        // its system WC queue hours/days after the user already made
        // their decision. Send the ack so the watch can clear any
        // lingering pending row, but DON'T copy the file or add to
        // the inbox — that'd re-file a clip the user explicitly
        // disposed of. Cross-actor read: `status(for:)` is
        // @MainActor but this delegate is nonisolated; we dispatch
        // synchronously so the dedup decision is made before the
        // early return below.
        let isDisposed = DispatchQueue.main.sync {
            InboxManifest.shared.status(for: clipId) == .disposed
        }
        if isDisposed {
            NSLog("[HiMem][WC] dropping clipId=\(clipId) — manifest tombstone (B5 dedup); sending ack")
            self.sendConfirmation(clipId: clipId)
            return
        }

        // The system deletes file.fileURL after this delegate method
        // returns. We MUST move the file synchronously here, before the
        // Task hop, otherwise it's gone by the time we try to read it.
        let filename = "\(clipId.uuidString).caf"
        let dest = InboxManifest.audioURL(for: filename)
        let source = file.fileURL

        // If the destination already exists, this is a re-delivery —
        // skip the copy. Otherwise copy from the system staging path
        // via `UbiquityStore.copyIntoStore` so the write is
        // NSFileCoordinator-wrapped — without coordination, iCloud's
        // file-presenter can read mid-copy and ship truncated audio
        // bytes to other devices. The system deletes file.fileURL
        // after this delegate method returns, so the copy must
        // remain synchronous (which `copyIntoStore` is).
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try UbiquityStore.shared.copyIntoStore(sourceURL: source, destinationURL: dest)
                NSLog("[HiMem][WC] copied audio to \(dest.path)")
            } catch {
                NSLog("[HiMem][WC] FAILED to copy audio from \(source.path) to \(dest.path): \(error.localizedDescription)")
                return
            }
        } else {
            NSLog("[HiMem][WC] audio already at \(dest.path), skipping copy")
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
        NSLog("[HiMem][WC] confirmation sent for clipId=\(clipId)")

        Task { @MainActor in
            NSLog("[HiMem][WC] entering MainActor task for clipId=\(clipId)")

            if InboxManifest.shared.clips.contains(where: { $0.clipId == clipId }) {
                NSLog("[HiMem][WC] clipId already in manifest, skipping accept")
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
            await Self.transcribePendingInboxClips(trigger: "arrival")

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
    static func transcribePendingInboxClips(trigger: String = "scene-active") async {
        let allClips = InboxManifest.shared.clips
        let pending = allClips.filter {
            $0.transcript.isEmpty && !$0.transcriptionAttempted
        }
        let pendingIds = pending.map { $0.clipId.uuidString.prefix(8) }.joined(separator: ",")
        NSLog("[HiMem][InboxDx] sweep trigger=\(trigger) total=\(allClips.count) pending=\(pending.count) ids=[\(pendingIds)]")
        guard !pending.isEmpty else { return }
        NSLog("[HiMem][Inbox] transcribing \(pending.count) pending clip(s)")
        if #available(iOS 26.0, *) {
            for clip in pending {
                let url = InboxManifest.audioURL(for: clip.audioFilename)
                logPreflight(clip: clip, url: url)
                // Surface the "transcribing" phase to the UI so the
                // user sees a real signal between "audio landed" and
                // "transcript ready" — addresses the spec's
                // operational-truth requirement (sync screens 1+2
                // in `screens-captured-clips-sessions.jsx`).
                // Fallback metadata covers the case where the
                // watch's pre-announce sendMessage was lost (phone
                // backgrounded at the moment of the send); the
                // tracker creates the IncomingCard entry from the
                // manifest's now-arrived clip instead.
                InboxArrivalTracker.shared.recordTranscribingStarted(
                    clipId: clip.clipId,
                    fallbackMetadata: InFlightClipMetadata(
                        capturedAt: clip.capturedAt,
                        durationSeconds: clip.duration,
                        latitude: clip.latitude,
                        longitude: clip.longitude,
                        fileSizeBytes: nil,
                        announcedAt: Date()
                    )
                )
                let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
                NSLog("[HiMem][InboxDx] outcome clip=\(clip.clipId.uuidString.prefix(8)) kind=\(outcomeLabel(outcome))")
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
                    NSLog("[HiMem][Inbox] transcribe deferred clip=\(clip.clipId.uuidString.prefix(8)) outcome=\(outcome)")
                }
                // Whether the attempt landed (marked) or was deferred
                // for retry, the transcribing phase is over — the
                // tracker drops it. A deferred clip stays pending and
                // the next sweep will re-enter `recordTranscribing-
                // Started` before its retry.
                InboxArrivalTracker.shared.clear(clipId: clip.clipId)
            }
        }
        // Money 2026-06-17: if any clip remained pending after this
        // sweep (typically `.modelNotInstalled` while Apple's
        // on-device speech model is still downloading), schedule a
        // retry in 30s. Without this, the only sweep triggers are
        // (a) the next watch arrival and (b) `scenePhase=.active` —
        // so a user sitting on Captured Clips while the model
        // installs sees "Transcribing…" indefinitely until they
        // background+foreground. The retry self-cancels once the
        // pending queue drains.
        scheduleRetryIfStillPending()
    }

    /// In-flight retry timer for `transcribePendingInboxClips`.
    /// Cancelled and re-armed on every sweep; clears itself when the
    /// pending queue is empty.
    @MainActor private static var retryTask: Task<Void, Never>?

    /// Test hook: true iff a retry sleep is currently armed. Used by
    /// `ColdLaunchTranscriptionRaceTests` to assert that
    /// `scheduleRetryIfStillPending` correctly self-cancels after the
    /// pending queue drains.
    @MainActor
    static var hasPendingRetry: Bool { retryTask != nil }

    /// Test hook: cancels any in-flight retry timer and clears the
    /// reference. Tests call this in setup/teardown so prior runs
    /// don't leak state into the next test.
    @MainActor
    static func cancelPendingRetryForTesting() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// Schedules a 30s retry of `transcribePendingInboxClips` iff at
    /// least one clip is still pending after the just-completed
    /// sweep. Idempotent — re-arming cancels any prior pending retry
    /// so we never stack multiple sleeping tasks. Stops when the
    /// queue drains.
    @MainActor
    private static func scheduleRetryIfStillPending() {
        let stillPendingCount = InboxManifest.shared.clips.filter {
            $0.transcript.isEmpty && !$0.transcriptionAttempted
        }.count
        retryTask?.cancel()
        guard stillPendingCount > 0 else {
            NSLog("[HiMem][InboxDx] retry not scheduled — queue drained")
            retryTask = nil
            return
        }
        NSLog("[HiMem][InboxDx] retry armed in 30s (stillPending=\(stillPendingCount))")
        retryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else {
                NSLog("[HiMem][InboxDx] retry cancelled before wake")
                return
            }
            NSLog("[HiMem][InboxDx] retry timer fired — re-entering sweep")
            await transcribePendingInboxClips(trigger: "retry")
        }
    }

    /// Pre-flight diagnostic: file existence, byte size, and the
    /// iCloud ubiquity download state for the clip's audio. If the
    /// file is in ubiquity but not yet downloaded locally,
    /// `AVAudioFile` open will fail with `.fileUnreadable` and the
    /// retry will keep looping — visible here.
    @MainActor
    private static func logPreflight(clip: InboxClip, url: URL) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        let size: Int64 = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
        var downloadStatus = "n/a"
        var isUbiquitous = false
        if let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]) {
            isUbiquitous = values.isUbiquitousItem ?? false
            if let status = values.ubiquitousItemDownloadingStatus {
                downloadStatus = status.rawValue
            }
        }
        NSLog("[HiMem][InboxDx] preflight clip=\(clip.clipId.uuidString.prefix(8)) file=\(url.lastPathComponent) exists=\(exists) bytes=\(size) ubiquitous=\(isUbiquitous) dlStatus=\(downloadStatus)")
    }

    /// Stringifies an Outcome for log readability.
    @available(iOS 26.0, *)
    @MainActor
    private static func outcomeLabel(_ outcome: TranscriptionService.Outcome) -> String {
        switch outcome {
        case .transcribed(let r):
            return "transcribed(textLen=\(r.text.count) cov=\(Int(r.coverageSeconds))s)"
        case .modelNotInstalled:
            return "modelNotInstalled"
        case .fileUnreadable(let e):
            return "fileUnreadable(\(e.localizedDescription))"
        case .transcriberFailed(let e):
            return "transcriberFailed(\(e.localizedDescription))"
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
    ///
    /// Pure idempotency decision for `acceptArrivedClip`. Replaces
    /// the prior three-layer dedup (manifest-membership +
    /// rollGroupId-match + `InboxProcessedClipIds.contains`) with a
    /// single predicate over the consolidated status field.
    ///
    /// Drop the arriving master when:
    ///   - The manifest already has a meaningful status for the
    ///     clipId — anything other than `.announced` means we
    ///     accepted, split, or disposed of it before. `.announced`
    ///     is the pre-announce placeholder, which is the row this
    ///     arrival is meant to fulfill.
    ///   - OR the rollGroupId is already in use by any clip in the
    ///     manifest. After Step A's deterministic split UUIDs
    ///     re-running the split would just rewrite the same files;
    ///     skipping is purely an efficiency win.
    static func shouldDropArrivedMaster(
        manifestStatusForClipId: InboxClip.Status?,
        rollGroupIdAlreadyInUse: Bool
    ) -> Bool {
        if let status = manifestStatusForClipId, status != .announced {
            return true
        }
        return rollGroupIdAlreadyInUse
    }

    @MainActor
    static func acceptArrivedClip(metadata: ClipMetadata, masterFilename: String) async {
        NSLog("[HiMem][WC] phone — acceptArrivedClip clipId=\(metadata.clipId) rollGroupId=\(metadata.rollGroupId?.uuidString ?? "nil") offsets=\(metadata.nextTapOffsets.count)")
        let masterURL = InboxManifest.audioURL(for: masterFilename)

        // Per-clipId critical section against the double-delivery
        // race documented in § 8.2 of the system reference doc. The
        // `await`s on VoiceClipSplitter.split and AudioCompressor
        // .compressInPlace release @MainActor between the dedup
        // check below and the manifest write; without this gate two
        // concurrent Tasks for the same master can both pass dedup
        // and each spawn N children. See
        // `AcceptanceCriticalSection` for the full story.
        guard AcceptanceCriticalSection.tryEnter(clipId: metadata.clipId) else {
            NSLog("[HiMem][WC] phone — acceptArrivedClip race avoided clipId=\(metadata.clipId) (already in flight); dropping redelivered master")
            try? FileManager.default.removeItem(at: masterURL)
            WatchSessionDelegate.shared.sendConfirmation(clipId: metadata.clipId)
            return
        }
        defer { AcceptanceCriticalSection.exit(clipId: metadata.clipId) }

        // Single consolidated dedup gate — see
        // `shouldDropArrivedMaster`. Drop the redelivered master
        // file so disk doesn't bloat.
        let manifest = InboxManifest.shared
        let dedupRollGroupId = metadata.rollGroupId ?? metadata.clipId
        let shouldDrop = Self.shouldDropArrivedMaster(
            manifestStatusForClipId: manifest.status(for: metadata.clipId),
            rollGroupIdAlreadyInUse: manifest.isRollGroupKnown(dedupRollGroupId)
        )
        if shouldDrop {
            NSLog("[HiMem][WC] phone — duplicate master ignored, clipId=\(metadata.clipId) already processed")
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
            NSLog("[HiMem][WC] manifest now contains \(InboxManifest.shared.count) clip(s)")
            return
        }

        // Roll session — split the master into per-clip InboxClips
        // sharing the master's rollGroupId. Each child clipId is
        // derived deterministically from (master.clipId, offsetIndex)
        // so a redelivered master produces the same children and
        // `InboxManifest.acceptClip`'s clipId-keyed dedup drops the
        // dupes by construction. See `VoiceClipSplitter
        // .deterministicChildClipId` and § 8.6 / § 8.2 of the system
        // reference doc.
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
                    clipId: VoiceClipSplitter.deterministicChildClipId(
                        master: metadata.clipId,
                        offsetIndex: idx
                    ),
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
            NSLog("[HiMem][WC] split master into \(fragments.count) clips (rollGroupId=\(rollGroupId))")
            // Clear the master clipId from the arrival tracker.
            // The pre-announce was keyed on master.clipId, but the
            // manifest now holds N children with fresh UUIDs.
            // Without this clear, the master entry stays in
            // .downloading (or .paused after a reachability drop)
            // forever — no file is coming for it, because the
            // master was already consumed by the split. § 8.6 of
            // the system reference doc.
            InboxArrivalTracker.shared.clear(clipId: metadata.clipId)
        } catch {
            // Split failed — fall back to one inbox row pointing at
            // the master, so we don't lose audio. User sees the
            // unsplit recording; rollGroupId still attached. Still
            // compress so the fallback file isn't bloated either.
            NSLog("[HiMem][WC] split failed (\(error.localizedDescription)), surfacing master as one clip")
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
    /// Logs the RMS energy of each channel in the file at `url`.
    /// Nonisolated + purely file-reading so it's safe to call from
    /// the acceptance path. Reads up to the first 5 seconds so a
    /// long file doesn't stall the arrival log. Speech will read
    /// ~0.01–0.1 RMS; silence reads near 0.
    private static func probeChannelEnergy(at url: URL, label: String) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let sampleCap = AVAudioFrameCount(format.sampleRate * 5)  // ~5s
        let readFrames = min(sampleCap, AVAudioFrameCount(file.length))
        guard readFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readFrames) else {
            return
        }
        do {
            try file.read(into: buffer, frameCount: readFrames)
        } catch {
            NSLog("[HiMem][ChanProbe] \(label) read failed: \(error.localizedDescription)")
            return
        }
        guard let channelPointers = buffer.floatChannelData else {
            NSLog("[HiMem][ChanProbe] \(label) floatChannelData nil")
            return
        }
        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var out: [String] = []
        for ch in 0..<channelCount {
            let data: UnsafeMutablePointer<Float> = channelPointers[ch]
            var sumSquares: Float = 0
            var peak: Float = 0
            for i in 0..<frameCount {
                let v: Float = data[i]
                sumSquares += v * v
                let absv: Float = abs(v)
                if absv > peak { peak = absv }
            }
            let rms: Float = sqrt(sumSquares / Float(max(frameCount, 1)))
            out.append("ch\(ch) rms=\(String(format: "%.4f", rms)) peak=\(String(format: "%.4f", peak))")
        }
        NSLog("[HiMem][ChanProbe] \(label) \(out.joined(separator: ", "))")
    }

    private static func compressIfPossible(at url: URL, label: String) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let before = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        // Snapshot the source format for diagnostics. Compressor
        // failures previously logged only the error text; the
        // format is what tells us WHY (e.g. multi-channel input
        // that AVAssetReader can't track-load per Troika reviewer
        // 3, July 5).
        let sourceFmt: String
        if let file = try? AVAudioFile(forReading: url) {
            let f = file.fileFormat
            sourceFmt = "\(f.channelCount)ch \(Int(f.sampleRate))Hz \(f.commonFormat.rawValue)"
        } else {
            sourceFmt = "unreadable"
        }
        // Per-channel RMS probe — turns "which channel has the mic
        // signal" from a guess into a measurement. Troika reviewer
        // 3 (July 5): with Voice Processing on, channel 0 is the
        // downlink reference (silence when nothing plays); the mic
        // is on a later channel. This log tells us which is which.
        // Keep for one TF round; strip if the pipeline stabilizes.
        probeChannelEnergy(at: url, label: label)
        do {
            try await AudioCompressor.compressInPlace(at: url)
            let after = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ratio = before > 0 && after > 0 ? Double(before) / Double(after) : 0
            NSLog("[HiMem][WC] compressed \(label): \(before)→\(after) bytes (\(String(format: "%.1fx", ratio))) sourceFmt=\(sourceFmt)")
        } catch {
            // Prominent tag so a busy console still surfaces this.
            // Compression failure leaves raw PCM on disk, which is
            // playable and transcribable (with the transcode fix)
            // but 15-30× larger over iCloud than intended.
            NSLog("[HiMem][WC][Compress][FAIL] \(label): \(error.localizedDescription) sourceFmt=\(sourceFmt) beforeBytes=\(before) — keeping raw PCM")
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
            NSLog("[HiMem][WC] iPhone — flush request skipped: session not activated")
            return
        }
        guard session.isReachable else {
            NSLog("[HiMem][WC] iPhone — flush request skipped: watch not reachable")
            return
        }
        let payload: [String: Any] = ["command": "flushPending"]
        session.sendMessage(payload, replyHandler: nil) { error in
            NSLog("[HiMem][WC] iPhone — flush request failed: \(error.localizedDescription)")
        }
        NSLog("[HiMem][WC] iPhone — flush request sent")
    }

    /// Pure construction of the ack wire payload. Extracted so unit
    /// tests can lock the format without standing up a `WCSession`.
    /// Exactly one of `clipId` / `rollGroupId` must be non-nil;
    /// passing neither traps in debug.
    ///
    /// Wire format: `{ "confirmed": "<uuid>", "kind": "clip" | "rollGroup" }`.
    /// Replaces the prior `{ "confirmedClipId": "<uuid>" }` shape.
    /// Watch-side `handleAckPayload` still accepts the legacy shape so
    /// any acks already in iOS's transferUserInfo queue from before
    /// this change continue to deliver during the rollout window.
    static func confirmationPayload(clipId: UUID?, rollGroupId: UUID?) -> [String: Any] {
        precondition(
            (clipId == nil) != (rollGroupId == nil),
            "confirmationPayload requires exactly one of clipId, rollGroupId"
        )
        if let rollGroupId {
            return ["confirmed": rollGroupId.uuidString, "kind": "rollGroup"]
        }
        return ["confirmed": clipId!.uuidString, "kind": "clip"]
    }

    /// Single-clip ack — preserved as a sugar overload so existing
    /// arrival-path call sites don't need rewording.
    func sendConfirmation(clipId: UUID) {
        sendConfirmation(clipId: clipId, rollGroupId: nil)
    }

    /// RollGroup ack — closes the split-clip re-ack gap (§ 8.7).
    func sendConfirmation(rollGroupId: UUID) {
        sendConfirmation(clipId: nil, rollGroupId: rollGroupId)
    }

    private func sendConfirmation(clipId: UUID?, rollGroupId: UUID?) {
        let session = WCSession.default
        let payload = Self.confirmationPayload(clipId: clipId, rollGroupId: rollGroupId)
        let label = clipId.map { "clipId=\($0)" } ?? "rollGroupId=\(rollGroupId!)"

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
            NSLog("[HiMem][WC] iPhone — sendMessage confirmation failed for \(label): \(error.localizedDescription) (transferUserInfo backup will deliver)")
        }
        NSLog("[HiMem][WC] iPhone — sendMessage confirmation attempted for \(label)")

        // Durable backup — always queued. System delivers when watch
        // next activates / both apps next become reachable.
        let transfer = session.transferUserInfo(payload)
        NSLog("[HiMem][WC] iPhone — transferUserInfo queued for \(label), transferring=\(transfer.isTransferring)")
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
            NSLog("[HiMem][WC] iPhone — reconcileWatchAcks: inbox empty, nothing to assert")
            return
        }
        NSLog("[HiMem][WC] iPhone — reconcileWatchAcks: re-asserting \(clipIds.count) clip(s) to watch")
        for clipId in clipIds {
            sendConfirmation(clipId: clipId)
        }
    }
}
