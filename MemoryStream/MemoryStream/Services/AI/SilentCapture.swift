import Foundation
import AVFoundation
import Darwin

/// **The `in_peak == 0` capture gate** (ruled 2026-08-02).
///
/// A recording whose every sample is exactly zero is a capture failure.
/// Before this gate the app saved it, compressed it, transcribed it to
/// nothing, and said nothing — the silent-success class, in the one place
/// where it costs a *memory* rather than a tap.
///
/// **Why nothing else in the app could see it.** B10 spent most of a device
/// pass on this: a held capture device leaves every layer we log perfectly
/// plausible — the session activates, the engine starts, `isRecording` is
/// true, the tap fires with correct frame counts, and the file is written at
/// exactly the right size for its duration. The *only* difference is sample
/// amplitude. So amplitude is the only thing that can be the gate.
///
/// **Exactly zero, no tolerance.** Any floor above zero would make this a
/// judgment about whether audio was *loud enough*, which we have no basis to
/// make — J5, observe don't conclude. Stated consequence: the
/// `.measurement`-era under-gained population (`in_peak ≈ 0.01`) had real
/// signal and correctly does not trip this. That population is D9/D9b's
/// item, not a hole in this one.
///
/// **The recording is always kept.** Nothing here deletes, truncates, or
/// declines to save audio. We report; the user decides.
enum SilentCaptureOutcome: Equatable {

    /// Signal was measured. Any non-zero peak at all.
    case heard

    /// No buffer was ever measured, so there is nothing to claim. A capture
    /// that never ran is F18's *"We couldn't start recording."* — a
    /// different fact with a different message. Reporting it as silence
    /// would be a confident falsehood, which is the sin this gate exists
    /// to end.
    case notMeasured

    /// Every measured sample was exactly zero.
    case silent

    /// Silent, **and a debugger is attached** — so the banner is withheld
    /// while the detection stands. Under Device Hub this fires constantly
    /// (that is B10's whole mechanism), and a message we see every day is
    /// a message we have learned to ignore by the time it matters.
    case silentDebuggerAttached
}

/// The pure decision. Kept free of `SpeechService`, of SwiftUI, and of the
/// audio stack so it can be exercised as a table.
enum SilentCaptureDecision {

    /// Ruled copy (Tom, 2026-08-02). Crucible voice: names the state, never
    /// blames the user, offers the one useful action. The wording *is* the
    /// promise here, so `SilentCaptureGateTests` pins the literal.
    static let message = "We didn't hear anything. Check that HiMem can use the microphone, and try again."

    static func evaluate(peak: Float, buffersMeasured: Int, debuggerAttached: Bool) -> SilentCaptureOutcome {
        guard buffersMeasured > 0 else { return .notMeasured }
        guard peak == 0 else { return .heard }
        return debuggerAttached ? .silentDebuggerAttached : .silent
    }

    /// Presentation, and *only* presentation, is what the debugger changes.
    static func showsBanner(_ outcome: SilentCaptureOutcome) -> Bool {
        outcome == .silent
    }

    /// What the banner should say about this outcome — **`nil` meaning "show
    /// nothing", never "leave what was there".**
    ///
    /// The caller assigns this unconditionally, which is the point: a
    /// message set on a silent capture and only ever cleared by hand would
    /// still be standing after a later recording that worked, describing a
    /// recording that is no longer the last one. Same class as the two
    /// frozen-snapshot defects (F24 D2, F25) — a correct value, rendered
    /// after it stopped being true.
    static func bannerMessage(for outcome: SilentCaptureOutcome) -> String? {
        showsBanner(outcome) ? message : nil
    }

    /// **The suppression announces itself.** A `print`-and-return reports as
    /// PASSED, and a suppression nobody can see is that same shape one layer
    /// out — the forbidden silent opt-out. What distinguishes this from one
    /// is that detection still runs and still speaks; only the banner is
    /// withheld.
    static func logLine(for outcome: SilentCaptureOutcome) -> String? {
        switch outcome {
        case .heard, .notMeasured:
            return nil
        case .silent:
            return "[HiMem][Speech][Amp] capture was silent — every sample zero"
        case .silentDebuggerAttached:
            return "[HiMem][Speech][Amp] capture was silent — banner suppressed (debugger attached)"
        }
    }
}

/// Running peak across one recording session, fed from the audio tap.
///
/// **Why this is not `[Amp]`.** `[Amp]` logs buffers 1–3 and every 50th —
/// an instrument, deliberately sampled so a long recording shows whether
/// signal dies partway. A *gate* cannot be sampled: a recording silent
/// everywhere except one unsampled buffer would read as silent, and one
/// silent only in the sampled windows would read as heard. This sees every
/// buffer and every channel.
///
/// **Every channel, not channel 0.** The watch's 3-channel input put the
/// downlink reference on channel 0 and the mic elsewhere; a channel-0-only
/// peak would call that recording dead.
///
/// Cost is one `fabsf` compare per sample (~44k/s), which is nothing next to
/// the file write and the format conversion already happening in the same
/// callback.
final class SilentCaptureObserver: @unchecked Sendable {

    private let lock = NSLock()
    private var peak: Float = 0
    private var buffers = 0

    /// Called at the start of each recording — a fresh session must not
    /// inherit the previous one's peak.
    func reset() {
        lock.lock()
        peak = 0
        buffers = 0
        lock.unlock()
    }

    /// Audio-thread entry point. Read-only with respect to the buffer.
    func observe(_ buffer: AVAudioPCMBuffer) {
        var bufferPeak: Float = 0
        if let channels = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            for c in 0..<Int(buffer.format.channelCount) {
                let samples = channels[c]
                for i in 0..<frames {
                    let s = abs(samples[i])
                    if s > bufferPeak { bufferPeak = s }
                }
            }
        }
        lock.lock()
        if bufferPeak > peak { peak = bufferPeak }
        buffers += 1
        lock.unlock()
    }

    var measuredPeak: Float {
        lock.lock(); defer { lock.unlock() }
        return peak
    }

    var buffersMeasured: Int {
        lock.lock(); defer { lock.unlock() }
        return buffers
    }

    func outcome(debuggerAttached: Bool) -> SilentCaptureOutcome {
        lock.lock()
        let (p, n) = (peak, buffers)
        lock.unlock()
        return SilentCaptureDecision.evaluate(peak: p, buffersMeasured: n, debuggerAttached: debuggerAttached)
    }
}

/// Is a debugger attached to this process right now?
///
/// **`P_TRACED`, deliberately not `#if DEBUG`.** A TestFlight build is a
/// release build, and an untethered TestFlight build is exactly the case
/// that matters — it is the one Judi runs. Gating on the build
/// configuration would silence the banner for the only user who cannot
/// read a console log. Gating on the *attachment* silences it precisely
/// when a human is already watching the log, and nowhere else.
///
/// Queried per recording (not cached): Xcode can attach or detach between
/// captures, which is the situation the whole B10 protocol is about.
enum DebuggerAttachment {

    static var isAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
