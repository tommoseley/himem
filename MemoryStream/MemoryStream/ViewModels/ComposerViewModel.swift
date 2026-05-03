import Foundation
import SwiftUI
import Combine

/// Owns all state for a single new-memory composition.
/// JournalView creates this once and presents ComposerView when isPresented is true.
/// Appending to existing entries is handled inline on EntryExpandedView, not here.
@MainActor
class ComposerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var isPresented = false
    @Published var textContent = ""
    @Published var mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    @Published var pendingTranscripts: [String] = []
    @Published var selectedTopicName: String? = nil
    @Published var showCamera = false
    @Published var cameraMode: CameraPickerView.CaptureMode = .photo
    @Published var recordingDuration: TimeInterval = 0
    /// Set true by the view while a recording is active and the stop transition
    /// still needs to stage the captured audio + transcript. Cleared once the
    /// stop has been processed.
    @Published var pendingAudioAppend = false

    // MARK: - Service references (set by JournalView)

    var speechService: SpeechService?
    var cameraService: CameraService?

    // MARK: - Private

    private var durationTimer: AnyCancellable?
    private let silenceWatcher = VoiceSilenceWatcher()

    // MARK: - Computed

    var headerTitle: String { "New memory" }

    var commitButtonTitle: String { "Commit memory" }

    var commitButtonIcon: String { "checkmark" }

    var isRecording: Bool {
        speechService?.isRecording ?? false
    }

    var transcribedText: String {
        speechService?.transcribedText ?? ""
    }

    var canCommit: Bool {
        guard !isRecording else { return false }
        return !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaCaptures.isEmpty
            || !pendingTranscripts.isEmpty
    }

    // MARK: - Lifecycle

    func open(withRecording: Bool = false) {
        isPresented = true
        if withRecording {
            startRecording()
        }
    }

    func openWithSeedText(_ seed: String) {
        textContent = seed
        isPresented = true
    }

    func close() {
        if speechService?.isRecording == true {
            speechService?.stopRecording()
        }
        stopDurationTimer()
        isPresented = false
    }

    func reset() {
        textContent = ""
        mediaCaptures = []
        pendingTranscripts = []
        selectedTopicName = nil
        recordingDuration = 0
        pendingAudioAppend = false
        speechService?.transcribedText = ""
        speechService?.lastRecordingPath = nil
    }

    // MARK: - Recording

    func startRecording() {
        guard let speech = speechService else { return }
        speech.transcribedText = ""
        speech.lastRecordingPath = nil
        pendingAudioAppend = true
        speech.startRecording()
        recordingDuration = 0
        startDurationTimer()
        silenceWatcher.start(
            textProvider: { [weak speech] in speech?.transcribedText ?? "" },
            onSilence: { [weak self] in self?.stopRecording() }
        )
    }

    func stopRecording() {
        silenceWatcher.cancel()
        speechService?.stopRecording()
        stopDurationTimer()
    }

    /// Used by the Commit button: if recording is active, stop it and
    /// synchronously stage the live transcript + audio file so a follow-up
    /// `commitContent` read sees them. The view's `.onChange(of: isRecording)`
    /// handler stages on its own runloop tick, which is too late for a
    /// commit fired from the same tap. Idempotent — call any time.
    func stopRecordingAndStageIfActive() {
        guard let speech = speechService, speech.isRecording else { return }
        // Snapshot the live values BEFORE stopping. The recognition callback
        // can fire after cancel and clobber transcribedText.
        let transcript = speech.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)

        silenceWatcher.cancel()
        speech.stopRecording()
        stopDurationTimer()

        // After stopRecording, lastRecordingPath is set if a file landed.
        let saveVoice = (UserDefaults.standard.object(forKey: "saveVoiceEntries") as? Bool) ?? true
        if let path = speech.lastRecordingPath {
            if saveVoice {
                if !mediaCaptures.contains(where: { $0.localIdentifier == path }) {
                    mediaCaptures.append((localIdentifier: path, mediaType: .voice))
                }
            } else {
                AudioPlayerService.deleteAudio(filename: path)
            }
        }
        if !transcript.isEmpty, !pendingTranscripts.contains(transcript) {
            pendingTranscripts.append(transcript)
        }

        // Reset so the view's .onChange doesn't double-stage.
        pendingAudioAppend = false
        speech.transcribedText = ""
        speech.lastRecordingPath = nil
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Media

    func addMedia(localIdentifier: String, mediaType: MediaReference.MediaType) {
        mediaCaptures.append((localIdentifier: localIdentifier, mediaType: mediaType))
    }

    func removeMedia(at index: Int) {
        guard mediaCaptures.indices.contains(index) else { return }
        mediaCaptures.remove(at: index)
    }

    // MARK: - Commit data

    /// The content to save — typed text + concatenated voice transcripts.
    /// Assembled once per commit, per the "one inference per commit" rule.
    var commitContent: String {
        let typed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = ([typed] + pendingTranscripts)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.isEmpty { return "No text provided." }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Duration timer

    private func startDurationTimer() {
        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recordingDuration += 1
            }
    }

    private func stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = nil
    }
}
