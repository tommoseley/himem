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

    /// RH-3 (July 20 2026) — the phone's `compressIfPossible` skips
    /// recompression when the arrived clip already conforms to the transfer
    /// contract (mono/16k/AAC), because the watch already transcoded it; an
    /// AAC→AAC re-encode measured ~2.7× attenuation. The skip guard's
    /// predicate is `isTransferReady`: conforming → skip, non-conforming →
    /// compress. This asserts both branches distinctly.
    @Test func recompressionSkip_conformingSkips_nonConformingCompresses() throws {
        // Non-conforming raw PCM (stereo/48k) → NOT transfer-ready → compress.
        let raw = try writeSourcePCM(channels: 2, sampleRate: 48_000, seconds: 1.0)
        defer { try? FileManager.default.removeItem(at: raw) }
        #expect(WatchTransferAudioTranscoder.isTransferReady(raw) == false,
                "raw stereo/48k PCM must NOT read as conforming — it needs compression")

        // Conforming mono/16k/AAC (transcoder output) → transfer-ready → skip.
        let conforming = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: conforming) }
        try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: raw, destination: conforming)
        #expect(WatchTransferAudioTranscoder.isTransferReady(conforming) == true,
                "an already mono/16k/AAC clip must read as conforming so compressIfPossible skips it")
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

    /// Measures peak |amplitude| across all channels of a file — the
    /// energy check that "mono/16k/AAC" alone doesn't make.
    private func filePeak(_ url: URL) throws -> Float {
        let f = try AVAudioFile(forReading: url)
        guard f.length > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat,
                                         frameCapacity: AVAudioFrameCount(f.length)) else { return 0 }
        try f.read(into: buf)
        var peak: Float = 0
        let chs = Int(buf.format.channelCount)
        for ch in 0..<chs {
            if let d = buf.floatChannelData?[ch] {
                for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(d[i])) }
            }
        }
        return peak
    }

    /// P0 (2026-07-15) money test — the transcode produced format-correct
    /// but **SILENT** output on device (watch clips arrived with no speech,
    /// no playback). The stereo fixture + format-only assertions missed it:
    /// "format-correct-but-silent" is exactly what they don't catch. This
    /// runs a real **3-channel** source in the device shape — three live
    /// channels at DIFFERENT levels, mic hottest on ch2 (loud-clip dogfood:
    /// inCh=[0.0056,0.0071,0.0103]) — and asserts the OUTPUT carries the
    /// **hottest channel's** energy: the pick-hottest downmix (capture-gain
    /// P0) must extract the mic channel, not average it away.
    @Test func transcode_3ch_preservesAudioEnergy() throws {
        // 3-ch deinterleaved Float32 @48k with an explicit discrete layout
        // (`commonFormat` alone can't build 3ch; the device input is 3ch).
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3)!
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                interleaved: false, channelLayout: layout)
        let source = tempURL("caf")
        let dest = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: dest) }

        let file = try AVAudioFile(forWriting: source, settings: fmt.settings)
        let frames = AVAudioFrameCount(48_000)  // 1s
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        // Three live channels at distinct levels: ch0 silent, ch1 quiet (0.1),
        // ch2 the mic (0.3, hottest). Distinct levels make hottest (0.3) vs
        // mean (~0.13) separable — the pick-hottest downmix must land on ch2.
        if let d = buf.floatChannelData?[1] {
            for i in 0..<Int(frames) { d[i] = 0.1 * sinf(2 * .pi * 440 * Float(i) / 48_000) }
        }
        if let d = buf.floatChannelData?[2] {
            for i in 0..<Int(frames) { d[i] = 0.3 * sinf(2 * .pi * 440 * Float(i) / 48_000) }
        }
        try file.write(from: buf)

        let inPeak = try filePeak(source)
        try WatchTransferAudioTranscoder.transcodeToTransferFormat(source: source, destination: dest)
        let outPeak = try filePeak(dest)

        // The regression lock is the PAIRING — format AND hottest-channel
        // energy from a ≥3ch source, in one standing assertion. Either half
        // alone is a false negative: format-only passed the silent ship;
        // energy-only wouldn't catch a mis-formatted output. Both must hold.
        // > 0.25 locks pick-hottest: the output carries ch2 (~0.3), NOT the
        // diluted mean (~0.13) that averaging uncorrelated channels produces.
        #expect(inPeak > 0.1, "fixture should have real input energy (peak=\(inPeak))")
        #expect(outPeak > 0.25,
                "output should carry the hottest channel ~0.3, not the diluted mean (in_peak=\(inPeak) out_peak=\(outPeak))")
        #expect(WatchTransferAudioTranscoder.isTransferReady(dest), "output must be mono/16k/AAC")
        let out = try AVAudioFile(forReading: dest)
        #expect(out.fileFormat.channelCount == 1)
        #expect(Int(out.fileFormat.sampleRate.rounded()) == 16_000)
        #expect(out.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
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
