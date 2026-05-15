import Foundation
import Combine
import AVFoundation
import CoreLocation
import WatchKit

/// Records audio on the watch and transcribes in parallel via on-device
/// `SFSpeechRecognizer`. Produces a `WatchPendingClip` on stop. Spec'd
/// behaviors:
///
/// - 5-minute hard cap with auto-stop
/// - Wrist-off → auto stop & save (never discards) — handled by
///   WKExtension's deactivate path; this service exposes `stop(save:)`
///   for the deactivate observer to call.
/// - Single shot — recording one clip at a time; calling `start()` while
///   active is a no-op.
@MainActor
final class WatchRecordingService: NSObject, ObservableObject, AVAudioRecorderDelegate {
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

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var timer: Timer?
    private var currentClipId: UUID?
    private var currentAudioURL: URL?
    private var currentLocation: CLLocation?

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

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder

            startedAt = Date()
            elapsed = 0
            transcript = ""
            audioLevel = 0
            peakAudioLevel = 0
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
    func stop(save: Bool) -> WatchPendingClip? {
        guard isRecording, let clipId = currentClipId, let audioURL = currentAudioURL else {
            return nil
        }

        recorder?.stop()
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        WatchSharedState.isRecording = false
        Task { await WidgetTimelineRefresher.refresh() }

        let duration = elapsed
        let captured = startedAt ?? Date()

        recorder = nil
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

        let clip = WatchPendingClip(
            clipId: clipId,
            capturedAt: captured,
            duration: duration,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            audioFilename: audioURL.lastPathComponent
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

    // MARK: - Permissions

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

        // Sample the recorder's averagePower (dBFS, typically ~-60 quiet
        // to 0 max) and map to a normalised 0...1 for the meter ring.
        // AVAudioRecorder needs explicit updateMeters() each read.
        if let r = recorder, r.isRecording {
            r.updateMeters()
            let avgDb = r.averagePower(forChannel: 0)
            audioLevel = normalisedLevel(forDb: avgDb)
            if audioLevel > peakAudioLevel {
                peakAudioLevel = audioLevel
            }
        }

        if elapsed >= Self.maxDuration {
            // Hard cap — auto-save and exit recording.
            stop(save: true)
        }
    }

    /// Maps an `AVAudioRecorder` average-power dBFS reading to a
    /// perceptually-flat 0...1 amplitude for the UI. The recorder's range
    /// is roughly -60 dB (silent) to 0 dB (clipping); below -55 dB we
    /// treat as ambient noise floor and floor the output at 0 so the meter
    /// doesn't twitch in a quiet room.
    private func normalisedLevel(forDb db: Float) -> CGFloat {
        let minDb: Float = -55
        let maxDb: Float = -5
        if db < minDb { return 0 }
        if db > maxDb { return 1 }
        // Linear in dB → roughly perceptual for speech-band loudness.
        return CGFloat((db - minDb) / (maxDb - minDb))
    }

    private func cleanupAfterError() {
        stopTimer()
        recorder?.stop()
        recorder = nil
        startedAt = nil
        currentClipId = nil
        if let audioURL = currentAudioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        currentAudioURL = nil
        isRecording = false
        elapsed = 0
        transcript = ""
        audioLevel = 0
        peakAudioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // The recorder finished on its own — no-op; `stop(save:)` already
        // handled the manifest write if the caller asked us to save.
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
