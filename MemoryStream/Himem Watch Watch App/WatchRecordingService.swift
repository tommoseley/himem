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
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder

            startedAt = Date()
            elapsed = 0
            transcript = ""
            isRecording = true
            WatchSharedState.isRecording = true
            Task { await WidgetTimelineRefresher.refresh() }

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        if elapsed >= Self.maxDuration {
            // Hard cap — auto-save and exit recording.
            stop(save: true)
        }
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
