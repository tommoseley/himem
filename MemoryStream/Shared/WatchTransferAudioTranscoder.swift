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
    nonisolated static let targetSampleRate: Double = 16_000
    nonisolated static let targetChannels: AVAudioChannelCount = 1
    nonisolated static let targetBitRate: Int = 32_000

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
    nonisolated static func transcodeToTransferFormat(source: URL, destination: URL) throws {
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

        let outFormat = dest.processingFormat

        // P0 fix (2026-07-15): do the N-ch→mono downmix OURSELVES (average
        // every source channel per frame) and let AVAudioConverter do only
        // the well-supported mono→mono resample. AVAudioConverter's built-in
        // downmix produced pure SILENCE for the device's 3-channel *discrete*
        // layout (dogfood + `transcode_3ch_preservesAudioEnergy`: in_peak=0.3
        // → out_peak=0.0) — it has no downmix matrix for an unlabeled/discrete
        // >2ch source, so it emitted zeros. Averaging is deterministic and
        // captures the mic wherever it lands across the channels.
        guard let monoSrcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: srcFormat.sampleRate,
                                                channels: 1, interleaved: false) else {
            throw TranscodeError.makeConverterFailed
        }
        guard let converter = AVAudioConverter(from: monoSrcFormat, to: outFormat) else {
            throw TranscodeError.makeConverterFailed
        }

        let srcChannels = Int(srcFormat.channelCount)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: 16_384),
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoSrcFormat, frameCapacity: 16_384) else {
            throw TranscodeError.bufferAllocFailed
        }

        // Amplitude instrumentation — the capture-layer discriminator
        // (capture-gain P0, 2026-07-15). The `[Amp]` line reports PER-CHANNEL
        // input peaks (which channels carry the mic vs which are dead
        // reference — quantifies the downmix's ~1/N averaging loss), the
        // overall input peak (does the recorded level scale with input →
        // gain-too-low vs mic-route-broken), and the converter output peak
        // (silent-in vs silent-out). Read-only measurement over the captured
        // file — it does not change transcode behavior.
        final class ChannelPeaks {
            var v: [Float]
            init(_ n: Int) { v = Array(repeating: 0, count: max(n, 0)) }
        }
        let inPeaks = ChannelPeaks(srcChannels)

        // Single stateful pass — the input block reads the source in chunks,
        // averages N→1, and signals `.endOfStream` at EOF. It does NOT
        // restart the converter per chunk (resampler continuity — the July 5
        // saga). Boxed EOF flag so the block captures a `let`, not a `var`.
        final class EOFFlag { var reached = false }
        let eof = EOFFlag()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if eof.reached { outStatus.pointee = .endOfStream; return nil }
            inputBuffer.frameLength = 0
            do { try src.read(into: inputBuffer) }
            catch { eof.reached = true; outStatus.pointee = .endOfStream; return nil }
            let n = Int(inputBuffer.frameLength)
            if n == 0 {
                eof.reached = true; outStatus.pointee = .endOfStream; return nil
            }
            // Downmix: mono[i] = mean over channels; track per-channel peak.
            let inCh = inputBuffer.floatChannelData!
            let out = monoBuffer.floatChannelData![0]
            let scale = 1.0 / Float(srcChannels)
            for i in 0..<n {
                var acc: Float = 0
                for ch in 0..<srcChannels {
                    let s = inCh[ch][i]
                    acc += s
                    let a = abs(s)
                    if a > inPeaks.v[ch] { inPeaks.v[ch] = a }
                }
                out[i] = acc * scale
            }
            monoBuffer.frameLength = inputBuffer.frameLength
            outStatus.pointee = .haveData
            return monoBuffer
        }

        var outPeak: Float = 0
        let outCapacity = AVAudioFrameCount(outFormat.sampleRate * 0.5)  // ~0.5s chunks
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
                throw TranscodeError.bufferAllocFailed
            }
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
            if let convError { throw TranscodeError.convertFailed(convError.localizedDescription) }
            if outBuffer.frameLength > 0 {
                if let od = outBuffer.floatChannelData?[0] {
                    for i in 0..<Int(outBuffer.frameLength) { outPeak = max(outPeak, abs(od[i])) }
                }
                do { try dest.write(from: outBuffer) }
                catch { throw TranscodeError.convertFailed("write: \(error.localizedDescription)") }
            }
            if status == .endOfStream || status == .error { break }
        }
        let perCh = inPeaks.v.map { String(format: "%.4f", $0) }.joined(separator: ",")
        let overallIn = inPeaks.v.max() ?? 0
        NSLog("[HiMem][WC][Amp] transcode srcCh=\(srcChannels) inCh=[\(perCh)] "
              + String(format: "in_peak=%.4f conv_out_peak=%.4f", overallIn, outPeak))
        // `dest` finalizes the AAC container on dealloc (end of scope).
    }

    /// The guard predicate: is `url` a transfer-ready file — **mono,
    /// 16 kHz, AAC**? The money test asserts this on the transcoder's
    /// output; the send path uses it as the final gate before
    /// `transferFile` (a file that fails this never ships).
    nonisolated static func isTransferReady(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let fmt = file.fileFormat
        let isAAC = fmt.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC
        return isAAC
            && fmt.channelCount == targetChannels
            && Int(fmt.sampleRate.rounded()) == Int(targetSampleRate)
    }

    /// Transfer-ready **and complete** for a clip of `expectedSeconds`.
    ///
    /// The completeness check (output duration ≈ expected, ±0.5 s) is the
    /// send-path guard against transcoding a source that was still
    /// finalizing: `WatchRecordingService.stop` deliberately does NOT
    /// sync-drain the write queue (a sync drain trips the watchOS
    /// watchdog), so an early transcode could read a truncated recording
    /// and produce a valid-but-short `.m4a`. A short output fails this and
    /// is re-transcoded on the next send trigger, by which point the
    /// source has finalized. Idempotency uses THIS (not `isTransferReady`
    /// alone) so a truncated artifact is redone, not shipped.
    nonisolated static func isTransferReadyAndComplete(_ url: URL, expectedSeconds: Double) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let fmt = file.fileFormat
        let isAAC = fmt.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC
        let mono16k = fmt.channelCount == targetChannels
            && Int(fmt.sampleRate.rounded()) == Int(targetSampleRate)
        guard isAAC, mono16k, fmt.sampleRate > 0 else { return false }
        let seconds = Double(file.length) / fmt.sampleRate
        return abs(seconds - expectedSeconds) <= 0.5
    }
}
