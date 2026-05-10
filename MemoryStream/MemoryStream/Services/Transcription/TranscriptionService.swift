import Foundation
import AVFoundation
import Speech

/// On-device speech-to-text for HiMem. Wraps Apple's iOS-26 `SpeechAnalyzer`
/// + `SpeechTranscriber` stack — purpose-built for long-form audio, no
/// 60-second ceiling, no `isFinal`-arbitration bug class. Replaces the
/// legacy `SFSpeechRecognizer` path.
///
/// Designed as a swappable component (Jig-candidate seam): Himem-specific
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
            NSLog("[Himem][Transcribe] locale unsupported: \(locale.identifier)")
            return
        case .supported, .downloading:
            NSLog("[Himem][Transcribe] requesting model install for \(locale.identifier)")
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
                NSLog("[Himem][Transcribe] model installed for \(locale.identifier)")
            }
        @unknown default:
            return
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file at `audioURL`. Returns the joined text +
    /// diagnostic coverage info. Empty `text` means the engine ran but
    /// found no speech (or model wasn't available); caller treats that as
    /// the "no speech detected" state.
    func transcribe(audioURL: URL, locale: Locale = .current) async -> Result {
        let fileDuration = audioFileDuration(at: audioURL)

        // Surface the request before doing any work so a hang shows up in
        // logs at the right place.
        NSLog("[Himem][Transcribe] start url=\(audioURL.lastPathComponent) duration=\(fileDuration)s locale=\(locale.identifier)")

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // Verify the model is available — if not, bail early with empty
        // result. We don't auto-install here because download can be slow
        // and this method is called inline with watch-clip arrival; the
        // pre-warm during onboarding is the install path.
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        guard assetStatus == .installed else {
            NSLog("[Himem][Transcribe] model not installed (\(assetStatus)), skipping")
            return Result(text: "", coverageSeconds: 0, fileDurationSeconds: fileDuration, segmentCount: 0)
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            // Init with modules only — no input. `start(inputAudioFile:)`
            // provides the input. Passing the file to BOTH init and start
            // trips the "Cannot simultaneously analyze multiple input
            // sequences" precondition.
            let analyzer = SpeechAnalyzer(modules: [transcriber])

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
                    NSLog("[Himem][Transcribe] result stream error: \(error.localizedDescription)")
                }
                return (pieces.joined(separator: " "), coverage, count)
            }()

            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            let (text, coverage, count) = await collected

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog(
                "[Himem][Transcribe] done segments=\(count) coverage=\(String(format: "%.2f", coverage))s file=\(String(format: "%.2f", fileDuration))s textLen=\(trimmed.count)"
            )
            return Result(text: trimmed, coverageSeconds: coverage, fileDurationSeconds: fileDuration, segmentCount: count)
        } catch {
            NSLog("[Himem][Transcribe] failed: \(error.localizedDescription)")
            return Result(text: "", coverageSeconds: 0, fileDurationSeconds: fileDuration, segmentCount: 0)
        }
    }

    // MARK: - Helpers

    private func audioFileDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let frames = Double(file.length)
        let rate = file.fileFormat.sampleRate
        return rate > 0 ? frames / rate : 0
    }
}
