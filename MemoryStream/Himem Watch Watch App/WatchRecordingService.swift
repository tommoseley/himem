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
    /// Audio-level throttle clock — `nonisolated(unsafe)` so the
    /// audio tap thread can read/write without crossing actor
    /// boundaries on every buffer. Guarded by `levelLock`.
    private nonisolated(unsafe) var lastLevelPublishedAt: CFTimeInterval = 0
    private let levelLock = NSLock()
    /// On-a-roll session id. Stamped at `start()`; every clip in the
    /// session — the initial clip plus each clip created via a
    /// `handoffToNewClip()` call from `NextClipController` — carries
    /// this same id. Cleared on `stop(save:)`.
    private(set) var currentRollGroupId: UUID?

    // Speech recognition isn't available on watchOS — Speech.framework isn't
    // in the watchOS SDK. Clips ship with empty transcripts; the iPhone runs
    // SFSpeechRecognizer once the file lands and updates the inbox row.
    private let locationProvider = WatchLocationProvider()

    /// Begins a recording. Requests permissions if needed.
    func start() async {
        guard !isRecording else { return }

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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // AVAudioEngine + tap. The input node's native format
            // drives both the file we write and the buffers we peek
            // at for the live waveform. Using the input format
            // directly (vs forcing a settings dictionary) avoids the
            // hidden conversion that drove the metering smoothing on
            // the AVAudioRecorder path.
            //
            // The tap closure captures `file` directly (rather than
            // going through `self?.audioFile?`) — the audio thread
            // can fire callbacks the moment `engine.start()` returns,
            // and reaching back into `self.audioFile` would either
            // race the main-actor assignment that follows or, when
            // following a prior recording's cleanup that left
            // `self.audioFile = nil`, drop writes silently. Direct
            // capture keeps the reference alive in the closure for
            // the lifetime of the tap.
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            let file = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, file] buffer, _ in
                try? file.write(from: buffer)
                self?.publishAudioLevelIfDue(from: buffer)
            }

            // Assign before start so any subsequent main-actor work
            // (or the tap's `self.publishAudioLevelIfDue`) sees the
            // engine + file as live.
            self.audioEngine = engine
            self.audioFile = file

            engine.prepare()
            try engine.start()

            startedAt = Date()
            elapsed = 0
            transcript = ""
            audioLevel = 0
            peakAudioLevel = 0
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
        } catch {
            cleanupAfterError()
        }
    }

    /// Stops the recording. `save: true` builds a `WatchPendingClip` and
    /// hands it to the manifest; `save: false` discards both audio file
    /// and transcript. Sync — watchOS has no on-device speech recognizer
    /// (Speech.framework isn't in the watchOS SDK), so the clip ships with
    /// an empty transcript and the iPhone fills it in after transfer.
    @discardableResult
    func stop(save: Bool, nextTapOffsets: [TimeInterval] = []) -> WatchPendingClip? {
        guard isRecording, let clipId = currentClipId, let audioURL = currentAudioURL else {
            return nil
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        // Closing the AVAudioFile happens by releasing the reference
        // — the file finalizes its header on dealloc, so any further
        // attempt to read it would race that flush. Drop our handle
        // before computing duration, since `duration` reads `elapsed`
        // (not the file).
        audioFile = nil
        stopTimer()
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
        NSLog("[Himem][WC] watch — stop(save:true) clipId=\(clipId) rollGroupId=\(rollId?.uuidString ?? "nil") duration=\(duration)")
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
    /// permission *before* presenting the 3-2-1-Listening countdown
    /// — without this, the system prompt can pop in the middle of
    /// the countdown sweep on first launch, which interrupts the
    /// gather-yourself rhythm.
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
        // `CACurrentMediaTime` is iOS/macOS only; `systemUptime` is the
        // monotonic equivalent available on watchOS.
        let now = ProcessInfo.processInfo.systemUptime
        levelLock.lock()
        let due = (now - lastLevelPublishedAt) >= 0.1
        if due { lastLevelPublishedAt = now }
        levelLock.unlock()
        guard due else { return }
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<frameLength {
            let s = abs(channelData[i])
            if s > peak { peak = s }
        }
        let normalized = Self.normalisedLevel(forPeakAmplitude: peak)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioLevel = normalized
            if normalized > self.peakAudioLevel {
                self.peakAudioLevel = normalized
            }
        }
    }

    /// Maps 0…1 linear peak amplitude to a 0…1 perceptual band for
    /// the live waveform. Peak DB range -50 → -10 puts ambient near
    /// zero, normal speech around 0.7+, with headroom for loud
    /// peaks to fill the band. Below -50 dB is the room-noise floor
    /// and zeroed so the waveform doesn't twitch in a quiet room.
    /// `nonisolated` so the audio-thread path can call it without an
    /// actor hop.
    private nonisolated static func normalisedLevel(forPeakAmplitude peak: Float) -> CGFloat {
        guard peak > 0 else { return 0 }
        let db = 20 * log10f(peak)
        let minDb: Float = -50
        let maxDb: Float = -10
        if db < minDb { return 0 }
        if db > maxDb { return 1 }
        return CGFloat((db - minDb) / (maxDb - minDb))
    }

    private func cleanupAfterError() {
        stopTimer()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        startedAt = nil
        currentClipId = nil
        if let audioURL = currentAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        currentAudioURL = nil
        currentRollGroupId = nil
        isRecording = false
        elapsed = 0
        transcript = ""
        audioLevel = 0
        peakAudioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
