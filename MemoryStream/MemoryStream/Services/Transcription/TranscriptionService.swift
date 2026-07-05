import Foundation
import AVFoundation
import Speech

/// On-device speech-to-text for HiMem. Wraps Apple's iOS-26 `SpeechAnalyzer`
/// + `SpeechTranscriber` stack — purpose-built for long-form audio, no
/// 60-second ceiling, no `isFinal`-arbitration bug class. Replaces the
/// legacy `SFSpeechRecognizer` path.
///
/// Designed as a swappable component (Jig-candidate seam): HiMem-specific
/// orchestration code calls only the public `transcribe(...)` and
/// `ensureModelReady(...)` methods. If the engine ever needs to swap (a
/// future Whisper-based pipeline, etc.), the public surface stays
/// unchanged.
///
/// Permission: same `NSSpeechRecognitionUsageDescription` as before.
/// Model assets: per-locale, downloaded from Apple's system asset
/// catalog on first use. Pre-warm via `ensureModelReady` during
/// onboarding so the first dictation isn't a blocking download.
@available(iOS 26.0, *)
final class TranscriptionService {
    static let shared = TranscriptionService()

    /// Result of a transcription pass. `text` is the joined transcript.
    /// `coverage` reports the audio range the engine actually transcribed
    /// vs the file's duration — used for diagnostic logging when a clip
    /// looks suspiciously short.
    struct Result: Sendable {
        let text: String
        let coverageSeconds: TimeInterval
        let fileDurationSeconds: TimeInterval
        let segmentCount: Int
    }

    /// What happened on a `transcribe(audioURL:)` call. Introduced
    /// 2026-05-29 after a hero-path bug: the prior signature
    /// returned `Result(text: "")` for four distinct failure modes
    /// (model-not-installed, file-unreadable, transcriber-failed,
    /// genuine-no-speech) — so the inbox sweep couldn't tell an
    /// infrastructure failure apart from a real silent recording
    /// and marked every empty result as "attempted," silently
    /// burning real user clips that arrived during the cold-launch
    /// model-install race.
    ///
    /// Callers that act on the outcome (e.g., the inbox-manifest
    /// sweep deciding whether to flip `transcriptionAttempted`)
    /// MUST switch on the cases — only `.transcribed` represents
    /// "model ran end-to-end and produced a definitive answer."
    /// All other cases are transient failures and the clip should
    /// stay pending so the next sweep retries.
    ///
    /// Callers that genuinely can't act on the failure (a manual
    /// retry button, a UI surface with no retry queue) may use
    /// `.textOrEmpty` to fall back to the prior behavior of
    /// treating any failure as empty text.
    enum Outcome: Sendable {
        case transcribed(Result)
        case modelNotInstalled
        case fileUnreadable(any Error)
        case transcriberFailed(any Error)

        var textOrEmpty: String {
            if case .transcribed(let r) = self { return r.text }
            return ""
        }

        /// User-facing message for surfaces with no retry queue
        /// (phone-direct voice composer save path). `nil` when the
        /// outcome was definitive (transcribed, including empty for
        /// genuine silence) — the user doesn't need to be told
        /// anything; the transcript (or its absence) IS the answer.
        ///
        /// For infrastructure failures (model not installed, file
        /// unreadable, transcriber threw) the message tells the user
        /// transcription will be deferred — they don't need to know
        /// which specific failure mode hit. Honest-label voice; never
        /// blames the user; never blames the device.
        ///
        /// The watch-arrival inbox path uses
        /// `InboxTranscriptionDispatcher.shouldMarkAttempted` instead
        /// — the sweep retries transient failures automatically, so
        /// the user never needs to know.
        var userFacingDeferralMessage: String? {
            switch self {
            case .transcribed:
                return nil
            case .modelNotInstalled, .fileUnreadable, .transcriberFailed:
                return "Transcription deferred — we'll try again next time."
            }
        }
    }

    private init() {}

    // MARK: - Asset / model management

    /// Ensures the speech model for `locale` is installed locally. If the
    /// asset is missing, this triggers a download from Apple's system
    /// asset catalog (network required on first call per locale; cached
    /// permanently after). Best-effort — throws on download failure but
    /// callers typically log and move on; a missing model causes
    /// `transcribe(...)` to return an empty result.
    /// Returns `true` when the SpeechTranscriber model for `locale` is
    /// already installed. Cheap; tests use it to gracefully skip when
    /// run on a fresh simulator without the asset cached.
    func modelIsInstalled(for locale: Locale) async -> Bool {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    func ensureModelReady(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            NSLog("[HiMem][Transcribe] locale unsupported: \(locale.identifier)")
            return
        case .supported, .downloading:
            NSLog("[HiMem][Transcribe] requesting model install for \(locale.identifier)")
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
                NSLog("[HiMem][Transcribe] model installed for \(locale.identifier)")
            }
        @unknown default:
            return
        }
    }

    // MARK: - Contextual vocabulary

    /// Phrases seeded into the analyzer's `AnalysisContext.contextualStrings`
    /// under the `.general` tag on every transcribe call. Biases the en-US
    /// model toward brand/product terms it doesn't know natively. Keep the
    /// list short — over-seeding tips the model toward false positives
    /// (recognizing "HiMem" in audio that actually said "hymn," etc.).
    ///
    /// Money 2026-07-04: "HiMem" was being transcribed as "iMem" / "hi mem"
    /// / "i, mem." Adding "HiMem" as a contextual string fixed the specific
    /// mishearing; leaving the list as a single-purpose surface for now.
    fileprivate static let contextualVocabulary: [String] = [
        "HiMem"
    ]

    // MARK: - Transcription

    /// Transcribes an audio file at `audioURL`. Returns an `Outcome`
    /// distinguishing model-not-installed / file-unreadable /
    /// transcriber-failed from a genuine "ran end-to-end, no speech"
    /// result. Critical for inbox-sweep retries: if this method
    /// returned `Result(text: "")` for all failure modes (as it did
    /// before 2026-05-29), the inbox would mark transient failures
    /// as "attempted" and silently lose real clips.
    func transcribe(audioURL: URL, locale: Locale = .current) async -> Outcome {
        let fileDuration = audioFileDuration(at: audioURL)

        // Surface the request before doing any work so a hang shows up in
        // logs at the right place.
        NSLog("[HiMem][Transcribe] start url=\(audioURL.lastPathComponent) duration=\(fileDuration)s locale=\(locale.identifier)")

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // Verify the model is available — if not, return a distinct
        // outcome so the caller can leave the clip pending for the
        // next sweep. We don't auto-install here because download
        // can be slow and this method is called inline with watch-
        // clip arrival; the pre-warm during app launch is the
        // install path.
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        guard assetStatus == .installed else {
            NSLog("[HiMem][Transcribe] model not installed (\(assetStatus)), deferring")
            return .modelNotInstalled
        }

        let originalFile: AVAudioFile
        do {
            originalFile = try AVAudioFile(forReading: audioURL)
        } catch {
            NSLog("[HiMem][Transcribe] file unreadable: \(error.localizedDescription)")
            return .fileUnreadable(error)
        }

        // Detailed format log. When a transcribe ends with empty text
        // and the user reports the audio is clearly speech, this is
        // the line that tells us whether SpeechTranscriber even got
        // a format it could handle. Common failure modes look like:
        //   - 8 kHz sample rate (no — needs 16+ kHz)
        //   - 2+ channels with no mixdown (transcriber wants mono)
        //   - integer PCM where Float32 was expected
        let fileFmt = originalFile.fileFormat
        let procFmt = originalFile.processingFormat
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? -1
        NSLog("[HiMem][Transcribe] file open ok bytes=\(fileSize) frames=\(originalFile.length) fileFmt=\(fileFmt) procFmt=\(procFmt)")

        // Transcode if the source isn't already mono 16 kHz Float32.
        // Money 2026-07-05: Tom's 3-ch 48 kHz Float32 recording (raw
        // uncompressed audio that skipped the compression pass on
        // arrival) got `[DIAG=rejected]` — SpeechAnalyzer.start()
        // bailed before scanning a single sample because the input
        // format didn't match the transcriber's expectations. The
        // transcoder pipes source frames through AVAudioConverter
        // into a temp CAF with the canonical mono/16k/Float32
        // shape, then hands THAT to the analyzer. Any weird format
        // that survives file open is now recoverable.
        var audioFile = originalFile
        var transcodedTempURL: URL? = nil
        defer {
            if let transcodedTempURL {
                try? FileManager.default.removeItem(at: transcodedTempURL)
            }
        }
        if !Self.isRecognizerCompatibleFormat(procFmt) {
            do {
                let (tmpURL, tmpFile) = try Self.transcodeToRecognizerFormat(sourceFile: originalFile)
                audioFile = tmpFile
                transcodedTempURL = tmpURL
                NSLog("[HiMem][Transcribe] transcoded to recognizer format procFmt=\(tmpFile.processingFormat) frames=\(tmpFile.length)")
            } catch {
                NSLog("[HiMem][Transcribe] transcode failed: \(error.localizedDescription) — trying analyzer on the raw file")
                // Fall through with `originalFile`. The analyzer
                // will likely still reject, but the failure will
                // land as `.transcriberFailed` with a clear
                // message rather than silent empty.
            }
        }

        // Init with modules only — no input. `start(inputAudioFile:)`
        // provides the input. Passing the file to BOTH init and start
        // trips the "Cannot simultaneously analyze multiple input
        // sequences" precondition.
        //
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Seed the analyzer's `AnalysisContext` with product-specific
        // vocabulary so the transcriber recognizes brand/UI words the
        // en-US model doesn't know natively. Money 2026-07-04: users
        // saying "HiMem" get "iMem" / "hi mem" / "i, mem" in
        // transcripts otherwise. `.general` biases scoring toward
        // these phrases without hard-locking them, so unrelated
        // audio still transcribes normally. Best-effort: if the
        // context setter throws we log and continue — a missing
        // vocab hint degrades to the "iMem" transcript, not a
        // failed transcription.
        do {
            let context = AnalysisContext()
            context.contextualStrings = [.general: Self.contextualVocabulary]
            try await analyzer.setContext(context)
        } catch {
            NSLog("[HiMem][Transcribe] setContext failed (continuing without vocab hint): \(error.localizedDescription)")
        }

        // Drain the result stream concurrently with the analyzer's
        // run. `finishAfterFile: true` on `start` guarantees the
        // stream terminates once the file's been fully consumed.
        async let collected: (joined: String, coverage: TimeInterval, count: Int) = {
            var pieces: [String] = []
            var coverage: TimeInterval = 0
            var count = 0
            do {
                for try await result in transcriber.results {
                    let chunk = String(result.text.characters)
                    if !chunk.isEmpty {
                        pieces.append(chunk)
                    }
                    coverage += CMTimeGetSeconds(result.range.duration)
                    count += 1
                }
            } catch {
                NSLog("[HiMem][Transcribe] result stream error: \(error.localizedDescription)")
            }
            return (pieces.joined(separator: " "), coverage, count)
        }()

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        } catch {
            NSLog("[HiMem][Transcribe] analyzer.start failed: \(error.localizedDescription)")
            // Cancel the collector so we don't leak. The collector
            // only stops cleanly when the results stream finishes,
            // which it won't if start() never produced input.
            return .transcriberFailed(error)
        }
        let (text, coverage, count) = await collected

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Coverage / segment cross-tabulation makes empty-result
        // diagnostics explicit:
        //   - segments=0 coverage=0  → recognizer rejected the audio
        //     before producing anything (format mismatch likely)
        //   - segments=0 coverage>0  → recognizer scanned the file
        //     but heard nothing recognizable (genuine silence OR
        //     audio with sub-perceptual speech for the model)
        //   - segments>0 textLen=0   → very rare; segments returned
        //     but every chunk was empty
        let diagnosticTag: String
        if count == 0 && coverage < 0.1 {
            diagnosticTag = " [DIAG=rejected]"
        } else if count == 0 {
            diagnosticTag = " [DIAG=scanned-no-recognition]"
        } else if trimmed.isEmpty {
            diagnosticTag = " [DIAG=segments-but-empty]"
        } else {
            diagnosticTag = ""
        }
        NSLog(
            "[HiMem][Transcribe] done segments=\(count) coverage=\(String(format: "%.2f", coverage))s file=\(String(format: "%.2f", fileDuration))s textLen=\(trimmed.count)\(diagnosticTag)"
        )
        return .transcribed(Result(text: trimmed, coverageSeconds: coverage, fileDurationSeconds: fileDuration, segmentCount: count))
    }

    // MARK: - Helpers

    private func audioFileDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let frames = Double(file.length)
        let rate = file.fileFormat.sampleRate
        return rate > 0 ? frames / rate : 0
    }

    // MARK: - Format compatibility + transcode

    /// The canonical audio format `SpeechTranscriber` accepts on iOS
    /// 26: mono, 16 kHz, Float32, non-interleaved. Values outside
    /// this cause `SpeechAnalyzer.start()` to silently reject the
    /// input — you get `[DIAG=rejected]` (0 segments, 0 coverage).
    static let recognizerTargetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }()

    /// True when the file's processing format matches what
    /// `SpeechTranscriber` will accept without conversion. We're
    /// deliberately strict — a file that's *almost* right (say 44.1
    /// kHz mono) may still work, but transcoding the outliers is
    /// cheap and consistent.
    static func isRecognizerCompatibleFormat(_ format: AVAudioFormat) -> Bool {
        format.channelCount == 1
            && format.sampleRate == 16_000
            && format.commonFormat == .pcmFormatFloat32
    }

    /// Transcodes `sourceFile` into a temp CAF at the recognizer's
    /// target format. Returns `(tempURL, openedFile)` — caller is
    /// responsible for deleting `tempURL` after use.
    ///
    /// Uses `AVAudioConverter`. Reads the source in ~1s blocks
    /// (16k frames at target rate) and writes converted frames to
    /// the destination. Multi-channel input gets automatic
    /// downmix; sample-rate conversion uses AVAudioConverter's
    /// built-in resampler.
    static func transcodeToRecognizerFormat(sourceFile: AVAudioFile) throws -> (URL, AVAudioFile) {
        let sourceFormat = sourceFile.processingFormat
        let targetFormat = recognizerTargetFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw NSError(
                domain: "TranscriptionService.transcode",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't create converter from \(sourceFormat) to \(targetFormat)"]
            )
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("himem-transcribe-\(UUID().uuidString).caf")
        let destFile = try AVAudioFile(
            forWriting: tempURL,
            settings: targetFormat.settings,
            commonFormat: targetFormat.commonFormat,
            interleaved: false
        )

        // Read in blocks. Source block size in target frames, back-
        // computed against source rate so we grab ~1s per iteration.
        let secondsPerBlock: Double = 1.0
        let sourceBlockFrames = AVAudioFrameCount(sourceFormat.sampleRate * secondsPerBlock)
        let targetBlockFrames = AVAudioFrameCount(targetFormat.sampleRate * secondsPerBlock)

        sourceFile.framePosition = 0
        while sourceFile.framePosition < sourceFile.length {
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceBlockFrames) else {
                break
            }
            try sourceFile.read(into: inputBuffer)
            if inputBuffer.frameLength == 0 { break }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetBlockFrames * 2) else {
                break
            }

            var errorOut: NSError?
            var didConsume = false
            let inputProvider: AVAudioConverterInputBlock = { _, outStatus in
                if didConsume {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didConsume = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            _ = converter.convert(to: outputBuffer, error: &errorOut, withInputFrom: inputProvider)
            if let errorOut {
                throw errorOut
            }
            if outputBuffer.frameLength > 0 {
                try destFile.write(from: outputBuffer)
            }
        }

        // Reopen for reading — writer file's `framePosition` is at
        // the end, and SpeechAnalyzer wants a fresh reader.
        let readerFile = try AVAudioFile(forReading: tempURL)
        return (tempURL, readerFile)
    }
}
