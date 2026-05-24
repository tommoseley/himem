import Foundation

/// Pure decision: is this Next tap allowed to fire, or should it be
/// silently debounced as an accidental double-tap / rolling thumb?
///
/// Spec: `docs/design/on-a-roll-spec.md` § Edge cases · Minimum clip
/// length. A Next tap below 2 seconds since the recording started
/// (or since the last Next) is silently debounced — no haptic, no
/// save, no counter reset, nothing in pending. The principle is
/// "never punish the user for behavior they didn't intend."
///
/// Extracted as a pure function so the decision is unit-tested
/// without driving any recorder or UI. Threshold is a single
/// constant; tune in instrumentation if telemetry shows otherwise
/// (open question per spec).
enum MinClipDebouncer {
    static let minimumClipSeconds: TimeInterval = 2.0

    /// Returns true when the tap should fire (clip is long enough).
    /// `now` lets tests provide a fixed clock.
    ///
    /// - `sessionStart`: when the *recording session* started (the
    ///   user's first tap on Record). The first Next tap is gated
    ///   against this.
    /// - `lastNextAt`: when the most recent Next fired, if any. nil
    ///   on the first potential Next tap. Subsequent taps are gated
    ///   against this (the current clip's actual start time, which
    ///   is the previous Next tap or sessionStart if none).
    /// - `now`: the current time. Defaults to `Date()`.
    static func shouldFire(
        sessionStart: Date,
        lastNextAt: Date?,
        now: Date = Date()
    ) -> Bool {
        let currentClipStart = lastNextAt ?? sessionStart
        let clipAge = now.timeIntervalSince(currentClipStart)
        return clipAge >= minimumClipSeconds
    }
}
