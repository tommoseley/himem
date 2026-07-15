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
/// **Explicit mono downmix (defensive).** Under `.measurement` session mode
/// the watch input was 3-channel (dogfood 2026-07-14); the capture-gain P0
/// fix (`WatchAudioSessionConfig.recordMode = .default`, 2026-07-15) now
/// yields mono on device, so N is normally 1. But we still downmix N→1
/// ourselves by **extracting the hottest channel** — retained as tested
/// defense for any future multichannel route. (Pick-hottest, not average:
/// the 3ch device channels were live but uncorrelated, so averaging cancelled
/// misaligned peaks and lost ~2×.)
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

        // P0 fix (2026-07-15): do the N-ch→mono downmix OURSELVES and let
        // AVAudioConverter do only the well-supported mono→mono resample.
        // AVAudioConverter's built-in downmix produced pure SILENCE for the
        // device's 3-channel *discrete* layout (dogfood + the 3ch energy
        // test: in_peak=0.3 → out_peak=0.0) — it has no downmix matrix for an
        // unlabeled/discrete >2ch source, so it emitted zeros. We combine the
        // channels ourselves.
        //
        // **Pick the hottest channel, don't average (capture-gain P0, 2026-07-15).**
        // The device's 3 channels are all live but MUTUALLY UNCORRELATED
        // (loud-clip dogfood: inCh=[0.0056,0.0071,0.0103], averaged out=0.0045
        // — the mean fell BELOW even the quietest channel's peak, because
        // per-sample averaging of misaligned peaks cancels). Averaging threw
        // away ~2× of the mic. So a cheap first pass finds the highest-energy
        // channel (the mic lands on a fixed channel for the whole clip) and
        // the convert pass extracts that single channel + resamples mono→mono.
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

        // Pass 1 — per-channel peak scan (read-only, then seek back to 0).
        // Doubles as the `[Amp]` discriminator: PER-CHANNEL input peaks (which
        // channel carries the mic), the overall input peak (does the recorded
        // level scale with input → gain-too-low vs mic-route-broken), and it
        // selects the channel to extract.
        var inPeaks = [Float](repeating: 0, count: max(srcChannels, 1))
        while true {
            inputBuffer.frameLength = 0
            do { try src.read(into: inputBuffer) } catch { break }
            let n = Int(inputBuffer.frameLength)
            if n == 0 { break }
            let inCh = inputBuffer.floatChannelData!
            for ch in 0..<srcChannels {
                var p = inPeaks[ch]
                for i in 0..<n { let a = abs(inCh[ch][i]); if a > p { p = a } }
                inPeaks[ch] = p
            }
        }
        src.framePosition = 0
        // The mic channel = the highest-peak channel (stable for the clip).
        let hottestCh = inPeaks.indices.max(by: { inPeaks[$0] < inPeaks[$1] }) ?? 0

        // Pass 2 — single stateful convert. The input block extracts the
        // hottest channel (no averaging) and signals `.endOfStream` at EOF.
        // It does NOT restart the converter per chunk (resampler continuity —
        // the July 5 saga). Boxed EOF flag so the block captures a `let`.
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
            let hot = inputBuffer.floatChannelData![hottestCh]
            let out = monoBuffer.floatChannelData![0]
            for i in 0..<n { out[i] = hot[i] }
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
        let perCh = inPeaks.map { String(format: "%.4f", $0) }.joined(separator: ",")
        let overallIn = inPeaks.max() ?? 0
        NSLog("[HiMem][WC][Amp] transcode srcCh=\(srcChannels) inCh=[\(perCh)] hottestCh=\(hottestCh) "
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
