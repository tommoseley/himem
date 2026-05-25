import Foundation
import AVFoundation

/// Transcodes recorded audio from raw PCM to AAC for storage. The
/// recording pipelines (`WatchRecordingService`, `SpeechService`) write
/// Float32 mono PCM via `AVAudioFile`, which is ~192 KB/sec — wildly
/// oversized for voice. AAC at 32 kbps mono is ~4 KB/sec, roughly 48×
/// smaller, while staying perfectly intelligible for speech and
/// decoding cleanly via `AVAudioFile` / `SpeechAnalyzer`.
///
/// **iOS-only.** AVFoundation's `AVAssetWriter` / `AVAssetReader` are
/// unavailable on watchOS, so this lives in the shared folder but is
/// only linked into the iPhone target. Watch clips arrive as raw PCM
/// via WatchConnectivity, then get compressed on the phone in
/// `WatchSessionDelegate` before landing in the inbox. Phone direct-
/// voice clips get compressed in the same pipeline that splits them.
///
/// AAC is iOS-native; no MP3 codec ships with `AVAssetWriter`. The
/// output container is `.m4a` (standard AAC home). Existing `.caf`
/// files on disk keep working — `AVAudioFile` sniffs by magic bytes,
/// not extension.
enum AudioCompressor {

    enum CompressError: Error, CustomStringConvertible {
        case noAudioTrack
        case writerInitFailed(String)
        case readerInitFailed(String)
        case writeFailed(String)

        var description: String {
            switch self {
            case .noAudioTrack:                return "no audio track in source"
            case .writerInitFailed(let s):     return "writer init failed: \(s)"
            case .readerInitFailed(let s):     return "reader init failed: \(s)"
            case .writeFailed(let s):          return "write failed: \(s)"
            }
        }
    }

    /// Reads `sourceURL`, transcodes to AAC mono at `sampleRate` Hz and
    /// `bitRate` bps, and writes the result to `destinationURL`. The
    /// caller is responsible for any rename/move/cleanup of the source.
    ///
    /// Defaults are tuned for voice: 16 kHz / 32 kbps. That's `SpeechAnalyzer`'s
    /// preferred input rate and a bitrate where speech is fully intelligible.
    static func compress(
        source sourceURL: URL,
        destination destinationURL: URL,
        sampleRate: Double = 16_000,
        bitRate: Int = 32_000
    ) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw CompressError.noAudioTrack
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destinationURL, fileType: .m4a)
        } catch {
            throw CompressError.writerInitFailed(error.localizedDescription)
        }

        let writerSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   bitRate,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw CompressError.readerInitFailed(error.localizedDescription)
        }

        // Reader produces 16-bit PCM at the target sample rate so the
        // writer's AAC encoder gets a clean, already-resampled input.
        let readerSettings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVSampleRateKey:             sampleRate,
            AVNumberOfChannelsKey:       1,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw CompressError.readerInitFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw CompressError.writerInitFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        let pump = PumpTask(input: input, output: output)
        try await pump.run()

        await writer.finishWriting()
        if writer.status != .completed {
            throw CompressError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// Compresses `sourceURL` in place. Writes to a sibling temp file,
    /// then atomically replaces the source. On failure the source is
    /// left untouched.
    static func compressInPlace(
        at sourceURL: URL,
        sampleRate: Double = 16_000,
        bitRate: Int = 32_000
    ) async throws {
        let tmpURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("." + sourceURL.lastPathComponent + ".aac-tmp")
        try await compress(source: sourceURL, destination: tmpURL, sampleRate: sampleRate, bitRate: bitRate)
        _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: tmpURL)
    }
}

/// Drives the read → encode pump on a serial queue.
/// `AVAssetWriterInput.requestMediaDataWhenReady` invokes the closure
/// repeatedly until backpressure is satisfied; the class wraps the
/// "did we finish" state so the continuation resumes exactly once.
private final class PumpTask {
    private let input: AVAssetWriterInput
    private let output: AVAssetReaderTrackOutput
    private let queue = DispatchQueue(label: "AudioCompressor.pump")
    private var continuation: CheckedContinuation<Void, Error>?
    private var didFinish = false

    init(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput) {
        self.input = input
        self.output = output
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            input.requestMediaDataWhenReady(on: queue) { [weak self] in
                self?.pump()
            }
        }
    }

    private func pump() {
        guard !didFinish else { return }
        while input.isReadyForMoreMediaData {
            if let sample = output.copyNextSampleBuffer() {
                if !input.append(sample) {
                    finish(error: AudioCompressor.CompressError.writeFailed("append returned false"))
                    return
                }
            } else {
                input.markAsFinished()
                finish(error: nil)
                return
            }
        }
        // Out of `isReadyForMoreMediaData` — the framework will re-invoke
        // the closure when buffer space is freed. Don't resume.
    }

    private func finish(error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
