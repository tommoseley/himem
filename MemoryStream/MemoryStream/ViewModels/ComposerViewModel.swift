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

    func close() {
        if isRecording {
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
    }

    func stopRecording() {
        speechService?.stopRecording()
        stopDurationTimer()
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
