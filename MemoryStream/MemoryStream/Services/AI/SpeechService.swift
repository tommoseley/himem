import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var lastRecordingPath: String?
    @Published var error: SpeechError?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?

    enum SpeechError: LocalizedError, Equatable {
        case notAuthorized
        case notAvailable
        case audioSessionFailed(String)
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition not authorized. Enable in Settings."
            case .notAvailable:
                return "Speech recognition not available on this device."
            case .audioSessionFailed(let detail):
                return "Audio session error: \(detail)"
            case .recognitionFailed(let detail):
                return "Recognition error: \(detail)"
            }
        }
    }

    // MARK: - Audio Directory

    static var audioDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("VoiceEntries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return speechGranted && micGranted
    }

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
        AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: - Recording

    func startRecording() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = .notAvailable
            return
        }

        guard isAuthorized else {
            error = .notAuthorized
            return
        }

        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = .audioSessionFailed(error.localizedDescription)
            return
        }

        // Set up audio file for saving
        let filename = UUID().uuidString + ".caf"
        let fileURL = Self.audioDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                }

                if let error {
                    let nsError = error as NSError
                    // Cancellation is not a user-facing error — it happens when the audio
                    // session is interrupted (e.g. camera opens) or stopRecording() is called.
                    let isCanceled = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203
                        || nsError.code == NSUserCancelledError
                    if !isCanceled {
                        self.error = .recognitionFailed(error.localizedDescription)
                    }
                    self.stopRecording()
                }

                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create audio file for recording
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
        } catch {
            print("Failed to create audio file: \(error)")
            audioFile = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            // Write to file simultaneously
            try? self?.audioFile?.write(from: buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            self.error = .audioSessionFailed(error.localizedDescription)
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        audioFile = nil

        if let url = currentRecordingURL, FileManager.default.fileExists(atPath: url.path) {
            lastRecordingPath = url.lastPathComponent
        } else {
            lastRecordingPath = nil
        }
        currentRecordingURL = nil

        isRecording = false
    }

    // MARK: - Playback

    static func audioURL(for filename: String) -> URL {
        audioDirectory.appendingPathComponent(filename)
    }
}
