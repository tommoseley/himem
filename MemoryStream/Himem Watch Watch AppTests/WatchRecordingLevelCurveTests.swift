import Testing
import Foundation
@testable import Himem_Watch_Watch_App

/// Money tests for the watch's `normalisedLevel(forPeakAmplitude:)`
/// — the dB → 0…1 mapping that drives the live waveform's bar
/// heights.
///
/// The bug context (2026-05-29): Tom recorded at "good volume" on
/// the watch and saw the bars stay short. Root cause: the watch's
/// dB ceiling (-10) was looser than the phone's (-18), so the same
/// speech registered ~30% lower on the watch. Recalibrated to match
/// the phone. These tests lock that calibration so a future
/// "let's widen the range again" change can't silently re-introduce
/// the gap.
///
/// All test inputs are linear peak amplitudes; the function converts
/// to dB internally (`20 * log10f(peak)`).
struct WatchRecordingLevelCurveTests {

    /// 10^(dB/20). Convenience for writing tests in dB terms.
    private static func linearAmplitude(forDb db: Float) -> Float {
        powf(10, db / 20)
    }

    private static func tolerance(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.02) -> Bool {
        abs(a - b) < slack
    }

    /// Zero peak (silence buffer) maps to zero — no division by log10
    /// crash, no spurious low-bar rendering.
    @Test
    func zeroPeak_returnsZero() {
        let level = WatchRecordingService.normalisedLevel(forPeakAmplitude: 0)
        #expect(level == 0)
    }

    /// Below -50 dB (the room-floor) is the noise floor and renders
    /// nothing. Watch must not "twitch" in a quiet room.
    @Test
    func belowFloor_returnsZero() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -60)
        )
        #expect(level == 0)
    }

    /// Exactly at the floor → zero. Edge consistency with "below
    /// floor."
    @Test
    func atFloor_returnsZero() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -50)
        )
        #expect(Self.tolerance(level, 0))
    }

    /// **THE BUG-FIX MONEY ASSERTION.** A peak around -25 dB is what
    /// a normal "good speaking volume" produces on the watch at wrist
    /// distance. Pre-fix this rendered at 62% (-25 maps to (25/40)
    /// against the -50→-10 range). Post-fix must be at least 75%
    /// (~78% with -50→-18). If this number drops back below 75%
    /// the calibration regressed.
    @Test
    func normalSpeakingVolume_around25dB_rendersAtLeast75Percent() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -25)
        )
        #expect(level >= 0.75, "Normal-volume speech (-25 dB) should fill ≥ 75% of the band, got \(level)")
    }

    /// -30 dB is conversational speech further from the mic. Should
    /// fall in the visible mid-band (50–75%), not the noise floor.
    @Test
    func conversationalSpeech_around30dB_rendersMidBand() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -30)
        )
        #expect(level >= 0.5 && level <= 0.75, "Conversational speech (-30 dB) should land in 50–75% band, got \(level)")
    }

    /// At the ceiling, the bar is at full. Loud peaks shouldn't
    /// require *louder-than-loud* peaks to fill.
    @Test
    func atCeiling_returnsOne() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -18)
        )
        #expect(Self.tolerance(level, 1))
    }

    /// Above the ceiling clamps to 1 (no values > 1 escape into
    /// the layout).
    @Test
    func aboveCeiling_returnsOne() {
        let level = WatchRecordingService.normalisedLevel(
            forPeakAmplitude: Self.linearAmplitude(forDb: -5)
        )
        #expect(level == 1)
    }

    /// Curve monotonicity sanity: louder input never produces a
    /// shorter bar. Tests the actual function rather than reasoning
    /// about it abstractly.
    @Test
    func curveIsMonotonicNonDecreasing() {
        let dbValues: [Float] = [-60, -50, -40, -35, -30, -25, -20, -18, -10]
        var prior: CGFloat = -1
        for db in dbValues {
            let level = WatchRecordingService.normalisedLevel(
                forPeakAmplitude: Self.linearAmplitude(forDb: db)
            )
            #expect(level >= prior, "Curve regressed at \(db) dB: prior=\(prior), current=\(level)")
            prior = level
        }
    }
}
