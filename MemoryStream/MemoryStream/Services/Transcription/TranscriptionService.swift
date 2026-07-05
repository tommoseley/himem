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

        // **Ask the recognizer what format it wants.** Don't guess.
        // Troika reviewer 2 (July 5): hardcoding `Float32 16 kHz`
        // was wrong — `SpeechAnalyzer` may want `Int16`. The sibling
        // `SpeechService` class doc names this exact gotcha and
        // uses `bestAvailableAudioFormat` to negotiate. Mirror it.
        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            NSLog("[HiMem][Transcribe] SpeechAnalyzer.bestAvailableAudioFormat returned nil for locale=\(locale.identifier)")
            return .transcriberFailed(NSError(
                domain: "TranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recognizer wouldn't advertise a compatible format"]
            ))
        }
        NSLog("[HiMem][Transcribe] recognizer target format: \(bestFormat)")

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
        // a format it could handle.
        let fileFmt = originalFile.fileFormat
        let procFmt = originalFile.processingFormat
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? -1
        NSLog("[HiMem][Transcribe] file open ok bytes=\(fileSize) frames=\(originalFile.length) fileFmt=\(fileFmt) procFmt=\(procFmt)")

        // Transcode to the negotiated target format. We ALWAYS
        // transcode (not just when the source shape looks wrong),
        // because the check-and-skip optimization was a source of
        // subtle bugs. The transcode is cheap and produces exactly
        // what the recognizer asked for.
        //
        // Multi-channel input downmixes via AVAudioConverter's
        // default channel-mixing (not `channelMap = [0]` — Troika
        // reviewer 3 showed that with Voice Processing on, channel
        // 0 was the reference/downlink channel, so we were
        // extracting silence). Once the watch has VPIO disabled
        // (WatchRecordingService fix #1), future recordings are
        // mono at capture and this downmix is a no-op; for legacy
        // multi-channel files on disk, averaging all channels is
        // safer than picking one blind.
        let audioFile: AVAudioFile
        var transcodedTempURL: URL? = nil
        defer {
            if let transcodedTempURL {
                try? FileManager.default.removeItem(at: transcodedTempURL)
            }
        }
        do {
            let (tmpURL, tmpFile) = try Self.transcodeToFormat(sourceFile: originalFile, target: bestFormat)
            audioFile = tmpFile
            transcodedTempURL = tmpURL
            NSLog("[HiMem][Transcribe] transcoded procFmt=\(tmpFile.processingFormat) frames=\(tmpFile.length)")
        } catch {
            NSLog("[HiMem][Transcribe] transcode failed: \(error.localizedDescription)")
            return .transcriberFailed(error)
        }

        // Init the analyzer, seed the vocab context, and — CRITICALLY
        // — call `prepareToAnalyze(in:)`. Troika reviewer 2 named
        // this as the likely root cause of the 0-segment, 0-coverage
        // symptom: the sibling `SpeechService` class doc says
        // `prepareToAnalyze` MUST be called before the first
        // `start(inputSequence:)`, otherwise start returns
        // immediately without processing. Undocumented for the
        // file-input variant but the "returns immediately" signature
        // matches.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            let context = AnalysisContext()
            context.contextualStrings = [.general: Self.contextualVocabulary]
            try await analyzer.setContext(context)
        } catch {
            NSLog("[HiMem][Transcribe] setContext failed (continuing without vocab hint): \(error.localizedDescription)")
        }
        do {
            try await analyzer.prepareToAnalyze(in: bestFormat)
        } catch {
            NSLog("[HiMem][Transcribe] prepareToAnalyze failed: \(error.localizedDescription) — trying start anyway")
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

    // MARK: - Transcode

    /// Transcodes `sourceFile` into a temp CAF at `target` format.
    /// Returns `(tempURL, openedReaderFile)` — caller is
    /// responsible for deleting `tempURL` after use.
    ///
    /// **Single `AVAudioConverter.convert()` call.** Troika reviewer
    /// 1 (July 5) named the per-block `didConsume/noDataNow` loop
    /// as the resampler-starving pattern that produced silence at
    /// block seams. Fix: one convert call whose input block reads
    /// chunks directly from the source file and signals
    /// `.endOfStream` at EOF, preserving the resampler's filter
    /// state across the whole file.
    ///
    /// Multi-channel input downmixes via AVAudioConverter's default
    /// channel-mixing (average across channels). We do NOT set
    /// `converter.channelMap`. Troika reviewer 3 showed that with
    /// Voice Processing enabled on the watch (now fixed at source),
    /// channel 0 was the reference/downlink channel — extracting it
    /// via `channelMap = [0]` gave us silence. Averaging is the
    /// safe default for legacy multi-channel files on disk; new
    /// recordings will be mono at capture and this is a no-op.
    static func transcodeToFormat(sourceFile: AVAudioFile, target: AVAudioFormat) throws -> (URL, AVAudioFile) {
        let sourceFormat = sourceFile.processingFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw NSError(
                domain: "TranscriptionService.transcode",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't create converter from \(sourceFormat) to \(target)"]
            )
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("himem-transcribe-\(UUID().uuidString).caf")
        let destFile = try AVAudioFile(
            forWriting: tempURL,
            settings: target.settings,
            commonFormat: target.commonFormat,
            interleaved: target.isInterleaved
        )

        // Output capacity: source length × (target rate / source
        // rate), plus slack for edge frames the resampler emits.
        let expectedFrames = AVAudioFrameCount(
            (Double(sourceFile.length) * target.sampleRate / sourceFormat.sampleRate).rounded(.up)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: expectedFrames + 4096
        ) else {
            throw NSError(
                domain: "TranscriptionService.transcode",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't allocate output buffer at \(expectedFrames + 4096) frames"]
            )
        }

        // Stateful input block reads ~1s of source at a time. The
        // block is called repeatedly by convert() until it signals
        // `.endOfStream` at EOF, so the resampler's internal filter
        // maintains continuity across the whole file.
        sourceFile.framePosition = 0
        let sourceChunkFrames = AVAudioFrameCount(sourceFormat.sampleRate)  // ~1s
        var reachedEOF = false
        let inputProvider: AVAudioConverterInputBlock = { requested, outStatus in
            if reachedEOF {
                outStatus.pointee = .endOfStream
                return nil
            }
            let remaining = sourceFile.length - sourceFile.framePosition
            guard remaining > 0 else {
                reachedEOF = true
                outStatus.pointee = .endOfStream
                return nil
            }
            let take = AVAudioFrameCount(min(Int64(sourceChunkFrames), remaining))
            guard let chunk = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: take) else {
                outStatus.pointee = .noDataNow
                return nil
            }
            do {
                try sourceFile.read(into: chunk, frameCount: take)
            } catch {
                outStatus.pointee = .noDataNow
                return nil
            }
            if chunk.frameLength == 0 {
                reachedEOF = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return chunk
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputProvider)
        if let conversionError {
            throw conversionError
        }
        NSLog("[HiMem][Transcribe] convert status=\(status.rawValue) frames=\(outputBuffer.frameLength)")

        if outputBuffer.frameLength > 0 {
            try destFile.write(from: outputBuffer)
        }

        // Quick amplitude probe on the transcoded output. If this
        // reports near-zero peak, the recognizer will see silence
        // and we know the transcode itself is the failure — even
        // though the format math looks right (Troika reviewer 1
        // F5).
        if let channelData = outputBuffer.floatChannelData?[0] {
            var peak: Float = 0
            let n = Int(outputBuffer.frameLength)
            for i in 0..<n {
                let v = abs(channelData[i])
                if v > peak { peak = v }
            }
            NSLog("[HiMem][Transcribe] transcoded output peak amplitude=\(peak)")
        }

        // Reopen for reading — writer's `framePosition` is at the
        // end, and SpeechAnalyzer wants a fresh reader.
        let readerFile = try AVAudioFile(forReading: tempURL)
        return (tempURL, readerFile)
    }
}
