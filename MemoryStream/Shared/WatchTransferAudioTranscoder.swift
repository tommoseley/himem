import Foundation
import AVFoundation

/// Post-stop, whole-file transcode of a recorded watch clip from raw PCM
/// to **mono · 16 kHz · AAC (`.m4a`)** before it is handed to
/// `transferFile`. This is the 4a fix for the ~50× watch→phone sync
/// slowness: a 59 s clip is ~33 MB of 3-ch / 48 kHz / Float32 PCM raw vs
/// ~230 KB compressed (~144× smaller). Locked in `Watch · spec.md` §2
/// "Audio format & pre-transfer transcode" and
/// `docs/architecture/2026-07-14-watch-audio-compression.md`.
///
/// **Whole-file, once, after stop — never per-callback.** The per-callback
/// inline-converter path inside the record tap starves the resampler's
/// continuity filter and produces silence (the July 5 2026 saga, shipped
/// and reverted twice — `feedback_avaudioconverter_nodatanow_starves_resampler`).
/// This runs a single stateful `AVAudioConverter` pass over the finished
/// file via an input block that signals `.endOfStream` at EOF.
///
/// **Explicit mono downmix.** `setVoiceProcessingEnabled(false)` does NOT
/// collapse the watch input to mono on device (dogfood 2026-07-14: still
/// 3 channels), so the target format is mono and the converter downmixes
/// (averages) N→1.
///
/// **Encoder shape (Tom, 2026-07-14 · Option 1):** `AVAudioConverter` for
/// the resample + downmix, `AVAudioFile(forWriting: settings:)` for the
/// AAC encode. Both are watchOS-native (no `AVAssetWriter`/`AVAssetReader`,
/// which are unavailable on watchOS — the reason `AudioCompressor` can't
/// be reused here).
///
/// **Timing (binding — see `WatchRecordingService.stop`):** the record
/// service does NOT sync-drain the write queue at stop (a sync drain on
/// the main thread trips the watchOS watchdog). So this transcode must run
/// **off the main thread, on the send path, after the file has finalized**
/// — never synchronously in `stop()`.
enum WatchTransferAudioTranscoder {

    /// The transfer-format contract. The assertion test asserts the output
    /// file matches these; that test failing IS the oversized-transfer bug.
    static let targetSampleRate: Double = 16_000
    static let targetChannels: AVAudioChannelCount = 1
    static let targetBitRate: Int = 32_000

    enum TranscodeError: Error, CustomStringConvertible {
        case openSourceFailed(String)
        case openDestinationFailed(String)
        case makeConverterFailed
        case bufferAllocFailed
        case convertFailed(String)

        var description: String {
            switch self {
            case .openSourceFailed(let s):      return "open source failed: \(s)"
            case .openDestinationFailed(let s): return "open destination failed: \(s)"
            case .makeConverterFailed:          return "could not make AVAudioConverter"
            case .bufferAllocFailed:            return "buffer allocation failed"
            case .convertFailed(let s):         return "convert failed: \(s)"
            }
        }
    }

    /// Transcodes `source` (any PCM `.caf`) → mono 16 kHz AAC `.m4a` at
    /// `destination`. Throws on failure so the caller keeps `source` and
    /// ships raw rather than losing audio (audio-is-truth > speed).
    static func transcodeToTransferFormat(source: URL, destination: URL) throws {
        let src: AVAudioFile
        do { src = try AVAudioFile(forReading: source) }
        catch { throw TranscodeError.openSourceFailed(error.localizedDescription) }
        let srcFormat = src.processingFormat

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // AAC output file. `AVAudioFile` encodes to AAC on write; its
        // `processingFormat` is the mono 16 kHz PCM we feed it.
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannels),
            AVEncoderBitRateKey: targetBitRate
        ]
        let dest: AVAudioFile
        do { dest = try AVAudioFile(forWriting: destination, settings: aacSettings) }
        catch { throw TranscodeError.openDestinationFailed(error.localizedDescription) }

        // Converter handles both the 48k→16k resample and the N-ch→mono
        // downmix, source PCM → the destination's mono-16k PCM format.
        let outFormat = dest.processingFormat
        guard let converter = AVAudioConverter(from: srcFormat, to: outFormat) else {
            throw TranscodeError.makeConverterFailed
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: 16_384) else {
            throw TranscodeError.bufferAllocFailed
        }

        // Single stateful pass — the input block reads the whole source
        // file in chunks and signals `.endOfStream` at EOF. This is the
        // proven pattern (mirrors `TranscriptionService` on the phone);
        // it does NOT restart the converter per chunk, so the resampler's
        // continuity filter is preserved.
        var sourceExhausted = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if sourceExhausted { outStatus.pointee = .endOfStream; return nil }
            inputBuffer.frameLength = 0
            do { try src.read(into: inputBuffer) }
            catch { sourceExhausted = true; outStatus.pointee = .endOfStream; return nil }
            if inputBuffer.frameLength == 0 {
                sourceExhausted = true; outStatus.pointee = .endOfStream; return nil
            }
            outStatus.pointee = .haveData
            return inputBuffer
        }

        let outCapacity = AVAudioFrameCount(outFormat.sampleRate * 0.5)  // ~0.5s chunks
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
                throw TranscodeError.bufferAllocFailed
            }
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
            if let convError { throw TranscodeError.convertFailed(convError.localizedDescription) }
            if outBuffer.frameLength > 0 {
                do { try dest.write(from: outBuffer) }
                catch { throw TranscodeError.convertFailed("write: \(error.localizedDescription)") }
            }
            if status == .endOfStream || status == .error { break }
        }
        // `dest` finalizes the AAC container on dealloc (end of scope).
    }

    /// The guard predicate: is `url` a transfer-ready file — **mono,
    /// 16 kHz, AAC**? The money test asserts this on the transcoder's
    /// output; the send path uses it defensively before `transferFile`.
    static func isTransferReady(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let fmt = file.fileFormat
        let isAAC = fmt.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC
        return isAAC
            && fmt.channelCount == targetChannels
            && Int(fmt.sampleRate.rounded()) == Int(targetSampleRate)
    }
}
