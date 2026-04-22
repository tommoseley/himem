import Foundation
import SwiftUI
import Combine

/// Owns all state for a single Composer session — new memory or append to existing.
/// JournalView creates this once and presents ComposerView when isPresented is true.
@MainActor
class ComposerViewModel: ObservableObject {

    enum Mode: Equatable {
        case new
        case append(entryId: UUID, title: String)
    }

    // MARK: - Published state

    @Published var isPresented = false
    @Published var mode: Mode = .new
    @Published var textContent = ""
    @Published var mediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    @Published var selectedTopicName: String? = nil
    @Published var showCamera = false
    @Published var recordingDuration: TimeInterval = 0

    /// Existing media shown dimmed in append mode
    @Published var existingMedia: [MediaDisplayItem] = []

    // MARK: - Service references (set by JournalView)

    var speechService: SpeechService?
    var cameraService: CameraService?

    // MARK: - Private

    private var durationTimer: AnyCancellable?

    // MARK: - Computed

    var headerTitle: String {
        switch mode {
        case .new: return "New memory"
        case .append(_, let title): return title
        }
    }

    var isAppendMode: Bool {
        if case .append = mode { return true }
        return false
    }

    var commitButtonTitle: String {
        isAppendMode ? "Attach to memory" : "Commit memory"
    }

    var commitButtonIcon: String {
        isAppendMode ? "plus" : "checkmark"
    }

    var isRecording: Bool {
        speechService?.isRecording ?? false
    }

    var transcribedText: String {
        speechService?.transcribedText ?? ""
    }

    var canCommit: Bool {
        !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaCaptures.isEmpty
            || !transcribedText.isEmpty
    }

    // MARK: - Lifecycle

    func open(mode: Mode, withRecording: Bool = false) {
        self.mode = mode
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
        selectedTopicName = nil
        existingMedia = []
        recordingDuration = 0
        mode = .new
        speechService?.transcribedText = ""
        speechService?.lastRecordingPath = nil
    }

    // MARK: - Recording

    func startRecording() {
        guard let speech = speechService else { return }
        speech.transcribedText = ""
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

    /// The content to save — combines typed text and voice transcript.
    var commitContent: String {
        let typed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !typed.isEmpty && !voice.isEmpty {
            return typed + "\n\n" + voice
        }
        if !typed.isEmpty { return typed }
        if !voice.isEmpty { return voice }
        return "No text provided."
    }

    var commitAudioPath: String? {
        guard let speech = speechService else { return nil }
        let saveVoice = UserDefaults.standard.bool(forKey: "saveVoiceEntries")
        if saveVoice { return speech.lastRecordingPath }
        if let path = speech.lastRecordingPath {
            AudioPlayerService.deleteAudio(filename: path)
        }
        return nil
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
