import Foundation
import Speech
import AVFoundation

/// Live in-app voice recording with streaming transcription. Uses Apple's
/// iOS-26 `SpeechAnalyzer` + `SpeechTranscriber` stack — same engine as
/// `TranscriptionService` (which handles file-based watch-clip
/// transcription). Replaces a hand-rolled multi-pass workaround for
/// `SFSpeechRecognizer`'s ~60s utterance-boundary cap.
///
/// Architecture mirrors the reference implementation by Itsuki
/// (github.com/0Itsuki0/SwiftUI_SpeechAnalyzerDemo) — the analyzer +
/// transcriber are persistent across recordings, with a single
/// `transcriber.results` consumer Task running for the service's
/// lifetime. Each recording creates a new `AsyncStream<AnalyzerInput>`
/// fed via `analyzer.start(inputSequence:)`. Stop calls
/// `continuation.finish()` and `analyzer.finalize(through:)` to flush
/// results without ending the analyzer (so the next recording reuses it).
///
/// **Hidden iOS 26 API contracts (learned the hard way 2026-05-10):**
/// 1. `analyzer.prepareToAnalyze(in:)` MUST be called before the first
///    `start(inputSequence:)`. Without it, start returns immediately
///    instead of waiting for the input stream to finish.
/// 2. Buffers must match the format from
///    `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.
///    `AVAudioEngine`'s native input is Float32; SpeechAnalyzer wants
///    Int16. Use `AVAudioConverter` to bridge.
/// 3. The model is locale-specific and rate-locked. Hardcoding 48kHz
///    fails with `SFSpeechErrorDomain Code=4 "Model not available for
///    OfflineTranscription en_US 48,000"`. Always use the format the
///    analyzer reports as best.
@MainActor
final class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var lastRecordingPath: String?
    @Published var error: SpeechError?
    /// True once the SpeechTranscriber model is installed AND the
    /// analyzer is prepared. UI gates the record button on this.
    @Published var isModelReady = false

    // MARK: - Persistent (across recordings)

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var bestFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    // MARK: - Per-recording

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?
    private var audioConverter: AVAudioConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerStartTask: Task<Void, Error>?

    /// Cumulative finalized transcript across utterance boundaries within
    /// a single recording. Cleared at startRecording. The volatile
    /// (in-flight) chunk is appended via `transcribedText` for the UI but
    /// not committed here until SpeechTranscriber emits an isFinal.
    private var finalizedTranscript: String = ""

    enum SpeechError: LocalizedError, Equatable {
        case notAuthorized
        case notAvailable
        case audioSessionFailed(String)
        case recognitionFailed(String)
        case modelNotReady

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
            case .modelNotReady:
                return "Setting up speech…"
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

    // MARK: - Authorization + analyzer prep

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

        // Fire-and-forget: prepare the analyzer in the background so
        // first record-tap doesn't pay the model-install + prepare cost.
        Task { await self.prepareAnalyzerIfNeeded() }

        return speechGranted && micGranted
    }

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Idempotent. Builds the persistent transcriber + analyzer pair,
    /// installs the locale-specific model if missing, calls
    /// `prepareToAnalyze` (a critical pre-flight without which
    /// `start(inputSequence:)` misbehaves), and starts the long-running
    /// `transcriber.results` consumer Task. Subsequent calls are no-ops.
    func ensureModelReady() async {
        await prepareAnalyzerIfNeeded()
    }

    private func prepareAnalyzerIfNeeded() async {
        if analyzer != nil { return }

        do {
            let locale = Locale.current
            // Live preset emits volatile (in-flight) results plus periodic
            // finals at utterance boundaries. `.transcription` is the
            // file-friendly preset; live needs the volatile-results flow.
            let preset: SpeechTranscriber.Preset = .timeIndexedProgressiveTranscription
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions,
                attributeOptions: preset.attributeOptions
            )
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: .init(
                    priority: .userInitiated,
                    modelRetention: .processLifetime
                )
            )

            // Install the model if it isn't already on this device. Same
            // path used by `TranscriptionService.ensureModelReady`.
            try await TranscriptionService.shared.ensureModelReady(for: locale)

            // Best format = what the analyzer's modules want. We convert
            // engine buffers to this in the live-input bridge.
            let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            // CRITICAL pre-flight. See class doc.
            try await analyzer.prepareToAnalyze(in: bestFormat, withProgressReadyHandler: nil)

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.bestFormat = bestFormat

            // Persistent results consumer — runs across all recordings.
            // SpeechTranscriber.Result.isFinal distinguishes committed
            // text from in-flight volatile text. We append finals to
            // `finalizedTranscript` and project the running view in
            // `transcribedText` (finalized + current volatile chunk).
            resultsTask = Task { [weak self] in
                guard let self else { return }
                NSLog("[Himem][Speech] persistent results consumer started")
                do {
                    for try await result in transcriber.results {
                        let chunk = String(result.text.characters)
                        let isFinal = result.isFinal
                        await MainActor.run {
                            if isFinal {
                                if !chunk.isEmpty {
                                    if self.finalizedTranscript.isEmpty {
                                        self.finalizedTranscript = chunk
                                    } else {
                                        self.finalizedTranscript += " " + chunk
                                    }
                                }
                                self.transcribedText = self.finalizedTranscript
                            } else {
                                // Volatile partial — concat with finalized
                                // for the running display.
                                if self.finalizedTranscript.isEmpty {
                                    self.transcribedText = chunk
                                } else if !chunk.isEmpty {
                                    self.transcribedText = self.finalizedTranscript + " " + chunk
                                } else {
                                    self.transcribedText = self.finalizedTranscript
                                }
                            }
                        }
                    }
                    NSLog("[Himem][Speech] persistent results consumer ended")
                } catch is CancellationError {
                    // Service deinit. Expected.
                } catch {
                    NSLog("[Himem][Speech] persistent consumer failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.error = .recognitionFailed(error.localizedDescription)
                    }
                }
            }

            isModelReady = true
            NSLog("[Himem][Speech] analyzer prepared, bestFormat=\(bestFormat?.description ?? "nil")")
        } catch {
            NSLog("[Himem][Speech] prepareAnalyzer failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording

    func startRecording() {
        NSLog("[Himem][Speech] startRecording entered authorized=\(isAuthorized) modelReady=\(isModelReady)")
        guard isAuthorized else {
            NSLog("[Himem][Speech] aborted: not authorized")
            error = .notAuthorized
            return
        }
        guard let analyzer, let transcriber, let bestFormat else {
            NSLog("[Himem][Speech] aborted: analyzer not prepared")
            error = .modelNotReady
            Task { await self.prepareAnalyzerIfNeeded() }
            return
        }
        _ = transcriber  // silence unused-let warning (used implicitly via results)

        stopRecording()

        finalizedTranscript = ""
        transcribedText = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("[Himem][Speech] audio session failed: \(error.localizedDescription)")
            self.error = .audioSessionFailed(error.localizedDescription)
            return
        }

        let filename = UUID().uuidString + ".caf"
        let fileURL = Self.audioDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[Himem][Speech] engine input format: \(recordingFormat)")

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
            NSLog("[Himem][Speech] audio file ready: \(filename)")
        } catch {
            NSLog("[Himem][Speech] failed to create audio file: \(error.localizedDescription)")
            audioFile = nil
        }

        // Cache the converter across recordings — re-create only if the
        // engine's format changed (rare; e.g. Bluetooth headset swap).
        if audioConverter == nil
            || audioConverter?.inputFormat != recordingFormat
            || audioConverter?.outputFormat != bestFormat {
            audioConverter = AVAudioConverter(from: recordingFormat, to: bestFormat)
            // Drops timestamp drift from the first few samples. Per the
            // reference impl: avoids glitches at recording boundaries.
            audioConverter?.primeMethod = .none
        }

        // New input stream per recording. Persistent analyzer reuses the
        // same transcriber/results pipeline; only the input source rotates.
        let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let bufferCounter = AtomicCounter()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            let n = bufferCounter.increment()
            if n <= 3 {
                NSLog("[Himem][Speech] tap buffer #\(n) frames=\(buffer.frameLength)")
            }
            self?.streamBuffer(buffer)
            try? self?.audioFile?.write(from: buffer)
        }

        // Analyzer.start with the new input sequence. Fire-and-forget Task
        // — start returns once the input loop is registered, then the
        // input loop runs in the background pulling from `inputStream`.
        // The persistent `transcriber.results` consumer (set up in
        // prepareAnalyzerIfNeeded) yields partials/finals as they arrive.
        analyzerStartTask = Task { [analyzer, inputStream] in
            NSLog("[Himem][Speech] analyzer.start(inputSequence:) called")
            do {
                try await analyzer.start(inputSequence: inputStream)
                NSLog("[Himem][Speech] analyzer.start returned cleanly")
            } catch {
                NSLog("[Himem][Speech] analyzer.start failed: \(error.localizedDescription)")
                throw error
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            NSLog("[Himem][Speech] engine started, isRecording=true")
        } catch {
            NSLog("[Himem][Speech] engine.start() failed: \(error.localizedDescription)")
            self.error = .audioSessionFailed(error.localizedDescription)
            stopRecording()
        }
    }

    /// Converts the engine's Float32 buffer to the analyzer's expected
    /// format and yields it to the input continuation. No-op if the
    /// continuation has been finished (recording stopped while a tap
    /// callback was in flight).
    private nonisolated func streamBuffer(_ buffer: AVAudioPCMBuffer) {
        // The properties accessed below are MainActor-isolated. Capture
        // them via assumeIsolated so we can read from the audio tap thread
        // without crossing actor isolation on every buffer. We're the
        // only writers; readers tolerate stale snapshots fine.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let converter = self.audioConverter,
                  let bestFormat = self.bestFormat,
                  let continuation = self.inputContinuation else { return }
            let ratio = bestFormat.sampleRate / buffer.format.sampleRate
            let outputCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
            guard outputCapacity > 0,
                  let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: bestFormat,
                    frameCapacity: outputCapacity
                  ) else { return }
            var delivered = false
            var convertError: NSError?
            let status = converter.convert(to: outputBuffer, error: &convertError) { _, statusPtr in
                if delivered {
                    statusPtr.pointee = .endOfStream
                    return nil
                }
                delivered = true
                statusPtr.pointee = .haveData
                return buffer
            }
            if status == .error || convertError != nil { return }
            guard outputBuffer.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: outputBuffer))
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        // Finish the input stream — analyzer's input loop drains and the
        // current `start(inputSequence:)` Task completes.
        inputContinuation?.finish()
        inputContinuation = nil

        analyzerStartTask?.cancel()
        analyzerStartTask = nil

        // Flush any in-flight results without ending the analyzer's
        // session — `finalize(through: nil)` finalizes everything taken
        // from the input sequence, leaving the analyzer ready for the
        // next start. We do NOT call cancelAndFinishNow, which would
        // tear down the persistent transcriber/results pipeline.
        if let analyzer {
            Task { try? await analyzer.finalize(through: nil) }
        }

        audioFile = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let url = currentRecordingURL, FileManager.default.fileExists(atPath: url.path) {
            lastRecordingPath = url.lastPathComponent
        } else {
            lastRecordingPath = nil
        }
        currentRecordingURL = nil

        isRecording = false
    }

    deinit {
        resultsTask?.cancel()
    }

    // MARK: - Playback

    static func audioURL(for filename: String) -> URL {
        audioDirectory.appendingPathComponent(filename)
    }
}

/// Tiny thread-safe counter used by the diagnostic NSLog in the audio
/// engine tap so we can log only the first few buffer arrivals without
/// flooding the console at 100Hz+.
private final class AtomicCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
