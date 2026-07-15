import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// P0 4a money tests — the Watch audio-format invariant guard
/// (`Watch · spec.md` §2 "Audio format & pre-transfer transcode").
///
/// The file handed to `transferFile` MUST be mono / 16 kHz / AAC. These
/// assert the transcoder produces exactly that from the on-device
/// 3-channel / 48 kHz / Float32 PCM the watch actually records. **A
/// failure here IS the ~50× oversized-transfer bug** (a 59 s clip is
/// ~33 MB raw vs ~230 KB compressed).
@Suite(.serialized)
struct WatchTransferAudioTranscoderTests {

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    /// Writes a synthetic multi-channel 48 kHz Float32 PCM `.caf` so the
    /// test exercises the real downmix + resample path, not an already-mono
    /// shortcut. Uses stereo: the simple `AVAudioFormat(commonFormat:…)`
    /// init can't build a 3-channel format without an explicit channel
    /// layout, and the device's 3-ch input downmixes through the identical
    /// `AVAudioConverter` N→1 path anyway.
    private func writeSourcePCM(channels: AVAudioChannelCount, sampleRate: Double, seconds: Double) throws -> URL {
        let url = tempURL("caf")
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<Int(channels) {
            if let data = buffer.floatChannelData?[ch] {
                for i in 0..<Int(frames) {
                    data[i] = 0.2 * sinf(2 * .pi * 440 * Float(i) / Float(sampleRate))
                }
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// The money test: 3ch/48k/Float32 PCM → mono/16k/AAC.
    @Test func transcode_producesMono16kAAC() throws {
        let source = try writeSourcePCM(channels: 2, sampleRate: 48_000, seconds: 1.0)
        let dest = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dest) }

        try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: source, destination: dest)

        #expect(WatchTransferAudioTranscoder.isTransferReady(dest), "output must be transfer-ready (mono/16k/AAC)")
        let out = try AVAudioFile(forReading: dest)
        #expect(out.fileFormat.channelCount == 1)
        #expect(Int(out.fileFormat.sampleRate.rounded()) == 16_000)
        #expect(out.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
    }

    /// Locks the payload win — the whole point of the fix.
    @Test func transcode_shrinksPayloadDrastically() throws {
        let source = try writeSourcePCM(channels: 2, sampleRate: 48_000, seconds: 2.0)
        let dest = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dest) }

        try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: source, destination: dest)

        let srcSize = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        let dstSize = (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        #expect(dstSize > 0)
        // 3ch/48k/Float32 → mono/16k/AAC is ~100×+ smaller; assert ≥10× to
        // stay robust against AAC container overhead on a short clip.
        #expect(dstSize * 10 < srcSize, "compressed \(dstSize) B should be « raw \(srcSize) B")
    }

    /// The red state, captured: the raw recording the bug ships must FAIL
    /// the guard. This is the "test failing is the bug" boundary.
    @Test func isTransferReady_rejectsRawPCM() throws {
        let source = try writeSourcePCM(channels: 2, sampleRate: 48_000, seconds: 0.5)
        defer { try? FileManager.default.removeItem(at: source) }
        #expect(!WatchTransferAudioTranscoder.isTransferReady(source))
    }

    /// The wiring's completeness gate: a correctly-durationed transcode is
    /// ready+complete; the same file checked against a much longer expected
    /// duration is NOT. That's what stops the send path shipping a `.m4a`
    /// transcoded from a source that hadn't finalized (the no-sync-drain
    /// window) — a short/truncated artifact is re-transcoded, never shipped.
    @Test func isTransferReadyAndComplete_gatesOnDuration() throws {
        let source = try writeSourcePCM(channels: 2, sampleRate: 48_000, seconds: 1.0)
        let dest = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dest) }

        try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: source, destination: dest)

        #expect(WatchTransferAudioTranscoder.isTransferReadyAndComplete(dest, expectedSeconds: 1.0))
        #expect(!WatchTransferAudioTranscoder.isTransferReadyAndComplete(dest, expectedSeconds: 10.0),
                "a 1s artifact must fail the completeness gate for a 10s clip (truncated-source simulation)")
    }
}
