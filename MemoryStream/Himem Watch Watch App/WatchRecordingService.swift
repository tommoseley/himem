import Foundation
import Combine
import AVFoundation
import CoreLocation
import WatchKit

/// Records audio on the watch. Uses `AVAudioEngine` + an input-node
/// tap so the live waveform reads instantaneous peak amplitude
/// straight out of the PCM buffers — `AVAudioRecorder`'s
/// `peakPower(forChannel:)` was producing held / decaying values
/// that smeared transients into smooth gradients across the
/// waveform's history (peak-hold ballistics for VU-meter style
/// display). The tap gives us a true per-buffer peak, which
/// matches what the user just said.
///
/// Spec'd behaviors:
///
/// - 5-minute hard cap with auto-stop
/// - Wrist-off → auto stop & save (never discards) — handled by
///   WKExtension's deactivate path; this service exposes `stop(save:)`
///   for the deactivate observer to call.
/// - Single shot — recording one clip at a time; calling `start()` while
///   active is a no-op.
@MainActor
final class WatchRecordingService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var transcript: String = ""
    /// Normalised mic input level in 0...1, sampled from
    /// `AVAudioRecorder.averagePower(forChannel:)` and mapped to a
    /// perceptually-flat range so the recording disc breathes with real
    /// loudness. Quiet room ≈ 0; conversational speech ≈ 0.4–0.7;
    /// shouting ≈ ~1.0. Driven by the same `tick` loop as `elapsed`.
    @Published private(set) var audioLevel: CGFloat = 0

    /// Maximum `audioLevel` reached during the current recording. Reset
    /// to 0 on every `start()`. The cancel path uses this to decide
    /// whether the recording captured any real audio — if the peak never
    /// crossed the speech-floor threshold, the clip is effectively
    /// silence and can be discarded without the "Discard?" confirm.
    @Published private(set) var peakAudioLevel: CGFloat = 0

    /// Hard cap — the spec's 5-minute auto-stop.
    static let maxDuration: TimeInterval = 5 * 60

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var startedAt: Date?
    private var timer: Timer?
    private var currentClipId: UUID?
    private var currentAudioURL: URL?
    private var currentLocation: CLLocation?
    /// Keeps the watch app alive (and the audio engine running) when
    /// the screen blanks mid-recording. Without this, watchOS's
    /// ~15-second idle timer can suspend the app and kill
    /// `AVAudioEngine`, producing a truncated `.caf` whose tail just
    /// ends mid-syllable. Allocated in `start()`, invalidated in
    /// `stop(save:)` and `cleanupAfterError()`. Reason `.mindfulness`
    /// — the closest fit watchOS offers for a reflective voice-
    /// journal session.
    private var extendedSession: WKExtendedRuntimeSession?
    private var extendedSessionDelegate: ExtendedRuntimeSessionDelegate?
    /// Serial background queue for AVAudioFile writes. Apple's
    /// guidance is explicit: don't do file I/O on the audio tap
    /// thread. Watch flash write latency drifts up under sustained
    /// load (housekeeping, compaction); a single ~50 ms write spike
    /// on the audio thread back-pressures the engine, tap callbacks
    /// fire less often, level publishes slow, and the visual
    /// waveform appears to slow down after ~10 s — Tom QA
    /// 2026-05-30. The queue is `.userInteractive` because we need
    /// writes to keep up with the realtime tap rate; falling behind
    /// here would balloon memory holding queued buffers.
    private let fileWriteQueue = DispatchQueue(
        label: "com.himem.watch.recording.fileWrite",
        qos: .userInteractive
    )
    /// Audio-level throttle clock — `nonisolated(unsafe)` so the
    /// audio tap thread can read/write without crossing actor
    /// boundaries on every buffer. Guarded by `levelLock`.
    private nonisolated(unsafe) var lastLevelPublishedAt: CFTimeInterval = 0
    /// Running peak amplitude over all audio buffers received since
    /// the last `lastLevelPublishedAt` reset. Without this, the
    /// 100 ms throttle was sampling a single ~10 ms buffer per
    /// window — if that buffer fell between syllables the level
    /// published as near-silence even though the surrounding 90 ms
    /// had real speech. Tom QA 2026-05-29: waveform stayed flat
    /// during normal speaking. Guarded by `levelLock` like the
    /// throttle clock.
    private nonisolated(unsafe) var runningPeakSinceLastPublish: Float = 0
    private let levelLock = NSLock()
    /// On-a-roll session id. Stamped at `start()`; every clip in the
    /// session — the initial clip plus each clip created via a
    /// `handoffToNewClip()` call from `NextClipController` — carries
    /// this same id. Cleared on `stop(save:)`.
    private(set) var currentRollGroupId: UUID?

    // No speech-to-text on the watch — deliberate, not a temporary SDK gap.
    //
    // `Speech.framework` (`SFSpeechRecognizer`, `SpeechAnalyzer`,
    // `SpeechTranscriber`) is genuinely absent from the watchOS SDK as of
    // watchOS 26 — `import Speech` fails at compile time. What Reminders /
    // Messages show as "live dictation" is `presentTextInputController`'s
    // system-managed dictation sheet: the OS owns the recording, the OS
    // does the recognition (its own private path, not one exposed to
    // third-party apps), and the API hands us back only the FINAL string
    // when the sheet dismisses. There is no streaming-recognizer API we
    // could feed our own AVAudioEngine buffers into. Wrong shape for
    // HiMem's capture UI regardless — we own the recording and the waveform.
    //
    // Even if Apple exposed a streaming recognizer on watchOS tomorrow, we
    // would still ship empty transcripts here: the iPhone's `SpeechTranscriber`
    // is faster, has larger models, and transcribes on arrival. Doubling
    // that work on the watch burns battery + thermals during capture, and
    // the memories-are-perishable principle (docs/design/CLAUDE.md
    // "Memory perishability") argues against showing the user their words
    // on a 42mm screen mid-thought — the watch's job is to catch, not to
    // show its work.
    //
    // Clips therefore ship with empty transcripts; the iPhone fills them
    // in via `TranscriptionService.transcribe(audioURL:)` after
    // `WCSession.transferFile` delivery.
    private let locationProvider = WatchLocationProvider()

    /// Throwaway audio-session warmup. Run once at app launch from
    /// `WatchAppCoordinator.init`. Per Apple DTS guidance the HAL +
    /// route-negotiation state caches at the process level after a
    /// setActive cycle, so paying the ~10s `.allowBluetoothHFP`
    /// route-scan cost here (off the record critical path, while the
    /// user is still landing on the home screen) leaves the first
    /// real record hitting a warm HAL.
    ///
    /// `.mixWithOthers` keeps the user's music from being interrupted
    /// during the warmup. `.duckOthers` is omitted for the same
    /// reason — we don't need ducking to spin up the route. The
    /// actual record path sets the full options on its own
    /// setCategory call.
    nonisolated static func warmAudioSession() async {
        let warmStart = Date()
        do {
            let session = AVAudioSession.sharedInstance()
            // `.default` mirrors the record path (capture-gain P0, 2026-07-15)
            // so warm and record configure the same mode — no reconfigure.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true, options: [])
            try session.setActive(false, options: [])
            NSLog("[HiMem][REC] warmAudioSession completed in \(Int(Date().timeIntervalSince(warmStart) * 1000))ms")
        } catch {
            NSLog("[HiMem][REC] warmAudioSession failed: \(error.localizedDescription)")
        }
    }

    /// Begins a recording. Requests permissions if needed. All AV
    /// bring-up (audio session, engine, tap install, prepare, start)
    /// runs synchronously on the critical path. First-record cold
    /// start adds latency here (HAL warmup + I/O ring buffer
    /// allocation); subsequent records reuse the warm HAL and are
    /// near-instant. The dominant cold cost — `.allowBluetooth` HFP
    /// route scan — is paid at app launch via `warmAudioSession()`,
    /// so this setActive should hit a warm HAL.
    ///
    /// NSLog timings stay in place so we can see the cold-start cost
    /// in the device log on the next first-record.
    ///
    /// `.allowBluetoothHFP` (renamed from `.allowBluetooth` in iOS 17)
    /// enables AirPods + paired Bluetooth headsets as the input
    /// device. Without it the watch silently uses its built-in mic
    /// even when the user expects their AirPods.
    func start() async {
        guard !isRecording else { return }
        let startBegin = Date()

        let granted = await ensurePermissions()
        guard granted else { return }

        // Kick off a one-shot location fetch so we can attach coordinates
        // to the resulting clip if the user has Location enabled. The
        // recording proceeds in parallel; if the fix lands before stop,
        // we use it; otherwise the clip ships without location.
        Task { [weak self] in
            self?.currentLocation = await self?.locationProvider.requestOneShot()
        }

        let clipId = UUID()
        let filename = "\(clipId.uuidString).caf"
        let url = WatchPendingManifest.audioURL(for: filename)
        currentClipId = clipId
        currentAudioURL = url

        do {
            let sessionStart = Date()
            let session = AVAudioSession.sharedInstance()
            // `.allowBluetoothHFP` enables AirPods-as-mic. It also
            // triggers HFP route negotiation on `setActive(true)` —
            // that's the 10s cold-start cost Apple DTS confirms. We
            // pay it once per app launch via `warmAudioSession()`
            // called from `WatchAppCoordinator.init`, then this
            // setActive hits a warm HAL.
            // Capture-gain P0 (2026-07-15): `.default`, not `.measurement`.
            // `.measurement` mode minimizes system input processing — which
            // includes input GAIN — leaving the watch mic un-gained at
            // ~-40 dBFS (loud-clip dogfood: in_peak pinned ~0.01 regardless of
            // how loud the user spoke). The phone tolerates `.measurement`
            // because its mic is hotter; the watch mic isn't. `.default` lets
            // the system apply normal input gain. Independent of the July-5
            // VPIO/clean-channel fix (that's `setVoiceProcessingEnabled` below,
            // a different knob) — this does not touch it.
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[HiMem][REC] start: AVAudioSession active in \(Int(Date().timeIntervalSince(sessionStart) * 1000))ms")

            // AVAudioEngine + tap. The input node's native format drives
            // both the file we write and the buffers we peek at for the
            // live waveform. Using the input format directly (vs forcing
            // a settings dictionary) avoids the hidden conversion that
            // drove the metering smoothing on the AVAudioRecorder path.
            //
            // The tap closure captures `file` directly (rather than going
            // through `self?.audioFile?`) — the audio thread can fire
            // callbacks the moment `engine.start()` returns, and reaching
            // back into `self.audioFile` would either race the main-actor
            // assignment that follows or, when following a prior
            // recording's cleanup that left `self.audioFile = nil`, drop
            // writes silently. Direct capture keeps the reference alive
            // in the closure for the lifetime of the tap.
            let engineStart = Date()
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            // Disable Voice-Processing I/O — the ROOT CAUSE of the
            // July 5 "clear audio, no transcript" saga (Troika
            // reviewer 3, cited to Apple forum thread 710151).
            // With VPIO on, the input node emits a 3-channel
            // 48 kHz Float32 stream: channel 0 is the downlink
            // reference for echo cancellation (silence when
            // nothing is playing), channels 1+ carry raw + processed
            // mic. The receiver sees 3-ch audio with silence on
            // channel 0, and every downstream "extract channel 0"
            // heuristic ends up transcribing silence.
            //
            // Voice processing is inappropriate for a journal
            // recorder anyway — it aggressively suppresses room
            // ambience which is part of what memories capture.
            // Disable it and the tap format collapses back to
            // mono, killing the whole channel-map problem.
            do {
                try inputNode.setVoiceProcessingEnabled(false)
                NSLog("[HiMem][REC] voice processing disabled")
            } catch {
                NSLog("[HiMem][REC] setVoiceProcessingEnabled(false) failed: \(error.localizedDescription)")
            }
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            NSLog("[HiMem][REC] input node format: \(recordingFormat)")

            // Match the phone-side pattern (SpeechService.swift:298,
            // :322-330): open the file with the engine's hardware
            // format and write raw buffers verbatim. Format-shape
            // conversion for the recognizer happens on the phone
            // side inside `TranscriptionService.transcodeToRecognizerFormat`
            // (which handles multi-channel via `channelMap = [0]`).
            //
            // Previous inline-AVAudioConverter approach (reverted
            // July 5) produced silence on all new recordings — the
            // converter's internal sample-rate filter needs
            // continuity across callbacks, and the per-callback
            // `noDataNow` pattern starved it.
            //
            // Fixed the OTHER real bug from the earlier version:
            // copy ALL channels of the buffer, not just channel 0
            // into an otherwise-uninitialized multi-channel buffer.
            // The old fake-mono-copy left channels 1+ as freshly-
            // allocated undefined memory, which is what SpeechAnalyzer
            // ended up rejecting.
            let file = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, file] buffer, _ in
                self?.publishAudioLevelIfDue(from: buffer)
                // Copy ALL channels — AVAudioPCMBuffer's storage is
                // reused after the callback returns, so retaining
                // the buffer across the async boundary would race
                // the next callback.
                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
                    return
                }
                copy.frameLength = buffer.frameLength
                let channelCount = Int(buffer.format.channelCount)
                let frameBytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
                for ch in 0..<channelCount {
                    if let src = buffer.floatChannelData?[ch],
                       let dst = copy.floatChannelData?[ch] {
                        memcpy(dst, src, frameBytes)
                    }
                }
                self?.fileWriteQueue.async {
                    try? file.write(from: copy)
                }
            }

            // Assign before start so any subsequent main-actor work
            // (or the tap's `self.publishAudioLevelIfDue`) sees the
            // engine + file as live.
            self.audioEngine = engine
            self.audioFile = file

            engine.prepare()
            try engine.start()
            NSLog("[HiMem][REC] start: engine prepared+started in \(Int(Date().timeIntervalSince(engineStart) * 1000))ms")

            startedAt = Date()
            // Money 2026-06-18: hold the watch app alive across
            // screen-off so the AVAudioEngine isn't suspended mid-
            // recording. Without this, a stationary watch + idle
            // screen at ~15s kills the engine and truncates the
            // `.caf`. Best-effort: if the session fails to start
            // we proceed without it — the most likely outcome is
            // the same as today (silent truncation), not worse.
            startExtendedSessionIfPossible()
            elapsed = 0
            transcript = ""
            audioLevel = 0
            peakAudioLevel = 0
            // Reset the running peak so leftovers from a prior
            // session can't leak into the first published level of
            // this one.
            levelLock.lock()
            runningPeakSinceLastPublish = 0
            lastLevelPublishedAt = 0
            levelLock.unlock()
            currentRollGroupId = UUID()
            isRecording = true
            WatchSharedState.isRecording = true
            Task { await WidgetTimelineRefresher.refresh() }

            // Haptic confirms the mic is hot — the user feels the start
            // through the wrist even if they aren't looking at the watch.
            // `.click` is the briefest / quietest watchOS haptic; the
            // louder `.start` was perceived as intrusive.
            WKInterfaceDevice.current().play(.click)

            startTimer()
            NSLog("[HiMem][REC] start: total \(Int(Date().timeIntervalSince(startBegin) * 1000))ms")
        } catch {
            cleanupAfterError()
        }
    }

    /// Stops the recording. `save: true` builds a `WatchPendingClip` and
    /// hands it to the manifest; `save: false` discards both audio file
    /// and transcript. Sync — clips always ship with an empty transcript;
    /// the iPhone runs `SpeechTranscriber` on arrival. See the header
    /// comment above `locationProvider` for the full rationale (both the
    /// SDK gap and the product reasons that would keep this off even if
    /// the SDK gap closed).
    @discardableResult
    func stop(save: Bool, nextTapOffsets: [TimeInterval] = []) -> WatchPendingClip? {
        guard isRecording, let clipId = currentClipId, let audioURL = currentAudioURL else {
            return nil
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        // Closing the AVAudioFile is handled by ARC. Our reference
        // drops here, but every pending closure in `fileWriteQueue`
        // captured `file` strongly — the AVAudioFile stays alive
        // until the last write completes, then dealloc-time header
        // finalize runs at that moment. We deliberately do NOT
        // sync-drain the queue here: under sustained watch flash
        // pressure (housekeeping spikes), the queue can have a
        // multi-second backlog at stop time, and a sync drain on
        // the main thread triggers the iOS watchdog (Tom QA
        // 2026-05-30 crash at libsystem_kernel.dylib`mach_msg2_trap
        // on the main thread). The trade-off is a small window
        // where `currentAudioURL` exists but is still being
        // appended-to — but `send(clip:)` only fires later through
        // the manifest sweep / reachability triggers, by which
        // point the queue has drained and the header is finalized.
        audioFile = nil
        stopTimer()
        invalidateExtendedSession()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        WatchSharedState.isRecording = false
        Task { await WidgetTimelineRefresher.refresh() }

        let duration = elapsed
        let captured = startedAt ?? Date()

        startedAt = nil
        currentClipId = nil
        currentAudioURL = nil
        let location = currentLocation
        currentLocation = nil

        if !save {
            try? FileManager.default.removeItem(at: audioURL)
            elapsed = 0
            transcript = ""
            audioLevel = 0
            peakAudioLevel = 0
            // Brief haptic mirrors the start tap. Earlier we used
            // `.failure` to differentiate save vs discard, but the
            // pattern was too long / too loud — Tom wants the minimal
            // tactile signal only.
            WKInterfaceDevice.current().play(.click)
            return nil
        }

        let rollId = currentRollGroupId
        currentRollGroupId = nil
        NSLog("[HiMem][WC] watch — stop(save:true) clipId=\(clipId) rollGroupId=\(rollId?.uuidString ?? "nil") duration=\(duration)")
        let clip = WatchPendingClip(
            clipId: clipId,
            capturedAt: captured,
            duration: duration,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            audioFilename: audioURL.lastPathComponent,
            rollGroupId: rollId,
            nextTapOffsets: nextTapOffsets
        )
        WatchPendingManifest.shared.append(clip)
        elapsed = 0
        transcript = ""
        audioLevel = 0
        peakAudioLevel = 0
        // Brief save-stop tap — same minimal pattern as the start.
        WKInterfaceDevice.current().play(.click)
        return clip
    }

    // No per-Next-tap file rotation. The watch records ONE master
    // audio file for the whole Record → Stop session; the iPhone
    // splits the master into per-clip files on receive using the
    // `nextTapOffsets` list that ships in `ClipMetadata`. Same
    // splitter (`VoiceClipSplitter`) runs against both phone-direct
    // masters and watch-arrived masters — one code path. The
    // `RecordingHandoff.handoffToNewClip(rollGroupId:newClipIndex:)`
    // conformance below is therefore a no-op: it stamps the
    // `currentRollGroupId` and that's it. `NextClipController`'s
    // `nextTapOffsets` array carries the cut points.

    // MARK: - Permissions

    /// Async mic-permission check. Public so callers can pre-fetch
    /// permission *before* presenting the fresh-start breath —
    /// without this, the system prompt can pop during the one-second
    /// ochre ring sweep on first launch, which interrupts the
    /// gather-yourself rhythm. (May 27 2026: the 3-2-1 countdown
    /// was retired in favor of a single one-second breath.)
    func ensureMicPermission() async -> Bool {
        await ensurePermissions()
    }

    private func ensurePermissions() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Timer + hard cap

    private func startTimer() {
        stopTimer()
        // 100ms cadence — fast enough that the meter ring feels live but
        // slow enough that updating `@Published audioLevel` doesn't churn
        // SwiftUI. The elapsed-time label only needs 500ms-ish granularity
        // but we tick at 100ms so the level animation stays smooth.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let started = startedAt else { return }
        elapsed = Date().timeIntervalSince(started)
        // Audio level is published from the engine's input tap on
        // each buffer (throttled to 10 Hz). The tick loop only owns
        // elapsed time + the hard-cap check now.
        if elapsed >= Self.maxDuration {
            // Hard cap — auto-save and exit recording.
            stop(save: true)
        }
    }

    // MARK: - Live audio level (tap-driven)

    /// Computes peak amplitude over the current tap buffer and, if
    /// at least 100ms has elapsed since the last publish, hops to
    /// MainActor and updates `audioLevel` + `peakAudioLevel`. The
    /// throttle clock is guarded by `levelLock` since this fires on
    /// the audio thread and we want to avoid every buffer racing
    /// the main queue.
    private nonisolated func publishAudioLevelIfDue(from buffer: AVAudioPCMBuffer) {
        // Compute peak for THIS buffer first — every buffer counts
        // toward the running max, not just the one that happens to
        // sit on the 100 ms throttle boundary. Cheap (~40 frames @
        // 16 kHz of float scan per ~5 ms buffer).
        var bufferPeak: Float = 0
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            for i in 0..<frameLength {
                let s = abs(channelData[i])
                if s > bufferPeak { bufferPeak = s }
            }
        }
        // `CACurrentMediaTime` is iOS/macOS only; `systemUptime` is the
        // monotonic equivalent available on watchOS.
        let now = ProcessInfo.processInfo.systemUptime
        // Merge buffer peak into the running window peak; if the
        // throttle is due, snapshot + reset for the next window.
        let peakToPublish = WaveformLevelThrottle.observe(
            bufferPeak: bufferPeak,
            now: now,
            lastPublishedAt: &lastLevelPublishedAt,
            runningPeak: &runningPeakSinceLastPublish,
            lock: levelLock
        )
        guard let peak = peakToPublish else { return }
        let normalized = Self.normalisedLevel(forPeakAmplitude: peak)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioLevel = normalized
            if normalized > self.peakAudioLevel {
                self.peakAudioLevel = normalized
            }
        }
    }

    /// Throttle helper exposed for unit testing — the bug fix is
    /// load-bearing here and the function above is hard to drive
    /// from tests because it takes a live `AVAudioPCMBuffer`.
    enum WaveformLevelThrottle {
        /// Standard 100 ms publish cadence — once per waveform bar
        /// at the watch's 10 Hz visual refresh. Public constant so
        /// tests can drive boundary cases deterministically.
        static let intervalSeconds: TimeInterval = 0.1

        /// Tracks the loudest peak seen across all buffers in the
        /// current 100 ms window. Returns the snapshot when the
        /// window closes (and resets the running peak), or `nil`
        /// otherwise. Pure besides the inout state — the lock makes
        /// the running-peak read-modify-write safe under the audio
        /// thread + main-thread access pattern.
        static func observe(
            bufferPeak: Float,
            now: TimeInterval,
            lastPublishedAt: inout CFTimeInterval,
            runningPeak: inout Float,
            lock: NSLock
        ) -> Float? {
            lock.lock()
            if bufferPeak > runningPeak { runningPeak = bufferPeak }
            let due = (now - lastPublishedAt) >= intervalSeconds
            var snapshot: Float? = nil
            if due {
                snapshot = runningPeak
                runningPeak = 0
                lastPublishedAt = now
            }
            lock.unlock()
            return snapshot
        }
    }

    /// Maps 0…1 linear peak amplitude to a 0…1 perceptual band for
    /// the live waveform. Peak dB range -50 → -18 matches the phone
    /// (`SpeechService.normalisedLevel`) so the same speaking volume
    /// renders at the same bar height on both surfaces. The prior
    /// ceiling of -10 dB required near-microphone speaking to fill
    /// the band — Tom QA 2026-05-29 reported the waveform looked
    /// too small at normal volume, math confirmed it (a -25 dB peak
    /// landed at 62% on the watch vs 78% on the phone).
    ///
    /// Below -50 dB is the room-noise floor and zeroed so the
    /// waveform doesn't twitch in a quiet room. A tighter floor
    /// (-45) was tried earlier and made things worse — it zeroed
    /// real speech captured at wrist distance.
    ///
    /// `internal` (was `private`) so `WatchRecordingLevelCurveTests`
    /// can lock the calibration against future regressions.
    /// `nonisolated` so the audio-thread path can call it without an
    /// actor hop.
    nonisolated static func normalisedLevel(forPeakAmplitude peak: Float) -> CGFloat {
        guard peak > 0 else { return 0 }
        let db = 20 * log10f(peak)
        let minDb: Float = -50
        let maxDb: Float = -18
        if db < minDb { return 0 }
        if db > maxDb { return 1 }
        return CGFloat((db - minDb) / (maxDb - minDb))
    }

    private func cleanupAfterError() {
        stopTimer()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        // Same ARC-based cleanup as `stop(save:)` — no sync drain;
        // closures retain the AVAudioFile until they complete and
        // releasing our reference is safe (see `stop` for the
        // watchdog-crash rationale).
        audioFile = nil
        startedAt = nil
        currentClipId = nil
        if let audioURL = currentAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        currentAudioURL = nil
        currentRollGroupId = nil
        invalidateExtendedSession()
        isRecording = false
        // Mirror `stop(save:)`: if `start()` set the shared-state
        // flag before throwing, the complication shows "REC" forever
        // until next process launch. Clear it + refresh the widget
        // timeline on the error path too.
        WatchSharedState.isRecording = false
        Task { await WidgetTimelineRefresher.refresh() }
        elapsed = 0
        transcript = ""
        audioLevel = 0
        peakAudioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Extended runtime session (screen-off survival)

    private func startExtendedSessionIfPossible() {
        let session = WKExtendedRuntimeSession()
        let delegate = ExtendedRuntimeSessionDelegate(
            onExpire: { [weak self] in
                NSLog("[HiMem][REC] extended runtime session expiring — stopping recording")
                // Save the partial recording rather than discard;
                // an expired session at the system's 1-hour ceiling
                // is "as much as watchOS will give us," not user
                // intent to abandon. HiMem's 5-min cap means we'd
                // hit the cap first anyway, but the safety net is
                // here in case the cap moves later.
                Task { @MainActor [weak self] in
                    _ = self?.stop(save: true)
                }
            },
            onError: { error in
                NSLog("[HiMem][REC] extended runtime session error: \(error.localizedDescription)")
            }
        )
        extendedSessionDelegate = delegate
        session.delegate = delegate
        session.start()
        extendedSession = session
        NSLog("[HiMem][REC] extended runtime session started")
    }

    private func invalidateExtendedSession() {
        guard let session = extendedSession else { return }
        session.invalidate()
        extendedSession = nil
        extendedSessionDelegate = nil
        NSLog("[HiMem][REC] extended runtime session invalidated")
    }
}

/// Thin delegate adapter for `WKExtendedRuntimeSession`. Held by
/// `WatchRecordingService` for the lifetime of the session; closures
/// route the lifecycle events back to the service without making
/// the service itself conform (keeps the service @MainActor without
/// the protocol's NSObject requirements bleeding everywhere).
private final class ExtendedRuntimeSessionDelegate: NSObject, WKExtendedRuntimeSessionDelegate {
    private let onExpire: () -> Void
    private let onError: (Error) -> Void

    init(onExpire: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.onExpire = onExpire
        self.onError = onError
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        onExpire()
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if let error {
            onError(error)
        }
    }
}

extension WatchRecordingService: RecordingHandoff {
    /// No-op on watch: the master audio file keeps recording across
    /// every Next tap. The iPhone's `VoiceClipSplitter` slices the
    /// master at receive time using `nextTapOffsets` from
    /// `NextClipController`, which ships in `ClipMetadata`. We stamp
    /// `currentRollGroupId` so the eventual `WatchPendingClip`
    /// carries it.
    func handoffToNewClip(rollGroupId: UUID, newClipIndex: Int) {
        currentRollGroupId = rollGroupId
    }
}

/// Thin one-shot location fetcher for the watch. We grab a single fix at
/// recording-start so the coordinate is fresh; if the user denies location
/// or no fix arrives within ~3s, we ship the clip without coordinates.
@MainActor
final class WatchLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOneShot() async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined else {
            return nil
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self?.fulfillIfPending(with: nil)
                }
            }
        }
    }

    private func fulfillIfPending(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.fulfillIfPending(with: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.fulfillIfPending(with: nil) }
    }
}
