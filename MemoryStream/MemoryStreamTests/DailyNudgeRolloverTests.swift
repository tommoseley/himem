import Testing
import Foundation
@testable import HiMem

/// Money tests for the daily nudge's chosen-time rollover semantics.
///
/// Tom's intent (Settings screenshot 2026-06-01): the daily nudge
/// should suppress if the user captured anything in the chosen-time
/// window ending now, not since calendar midnight. If nudge time is
/// 8 PM and they captured at 8:30 PM yesterday, the 8 PM nudge
/// today should NOT fire — the user captured in the last 24h. Under
/// the prior midnight-rollover logic that same scenario fired the
/// nudge because the 8:30 PM capture was on a different calendar
/// day than the 8 PM trigger.
///
/// Tom's design intent (chat transcript 2026-06-01): the user can
/// pick midnight as the nudge time to get the legacy calendar-day
/// semantics. The mechanism is the same; only the chosen anchor
/// time changes.
///
/// `DailyNudgePolicy.nextFireDate` is the pure decision: given the
/// nudge time + the most recent capture + now, return the Date the
/// next nudge should fire, or nil if no fire should be scheduled.
struct DailyNudgeRolloverTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")! // pin so DST flips don't drift the tests
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func minutes(_ hour: Int, _ minute: Int) -> Int {
        hour * 60 + minute
    }

    /// The scenario from Tom's chat transcript: nudge time 8 PM,
    /// user captured at 8:30 PM yesterday, now is 7:55 PM today.
    /// Under chosen-time rollover the capture is INSIDE the 24h
    /// window ending now (since 8 PM yesterday) → suppress.
    @Test func suppresses_whenCaptureWithinChosenTimeWindow() {
        let lastCapture = date(2026, 6, 1, 20, 30)
        let now = date(2026, 6, 2, 19, 55)
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCapture,
            nudgeMinutes: minutes(20, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == nil)
    }

    /// Last capture was two days ago at 8:30 PM. The window ending
    /// now (7:55 PM today) opened at 8 PM yesterday. The capture
    /// predates that → fire. Next nudge time today 8 PM hasn't
    /// passed yet, so schedule for today 8 PM.
    @Test func fires_whenNoCaptureSinceLastChosenTime() {
        let lastCapture = date(2026, 5, 31, 20, 30) // 2 days ago
        let now = date(2026, 6, 2, 19, 55)
        let expectedFire = date(2026, 6, 2, 20, 0)
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCapture,
            nudgeMinutes: minutes(20, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == expectedFire)
    }

    /// User opens the app at 9 PM (after the nudge time today).
    /// They haven't captured anything in the window ending now —
    /// the window opened at today 8 PM, lastCapture is older. Today
    /// 8 PM already passed; schedule for tomorrow 8 PM.
    @Test func firesNextDay_whenNudgeTimeAlreadyPassedToday() {
        let lastCapture = date(2026, 5, 31, 14, 30)
        let now = date(2026, 6, 2, 21, 0)
        let expectedFire = date(2026, 6, 3, 20, 0)
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCapture,
            nudgeMinutes: minutes(20, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == expectedFire)
    }

    /// Tom's "pick midnight for calendar-day semantics" case. Nudge
    /// time is midnight. Last capture was yesterday 11:59 PM. Now is
    /// today 9 AM. The window ending now opened at today 00:00, so
    /// the 23:59 capture is OUTSIDE the window → fire. Next
    /// occurrence of midnight is tomorrow 00:00.
    @Test func midnightChoice_behavesLikeCalendarDay() {
        let lastCapture = date(2026, 6, 1, 23, 59)
        let now = date(2026, 6, 2, 9, 0)
        let expectedFire = date(2026, 6, 3, 0, 0)
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCapture,
            nudgeMinutes: minutes(0, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == expectedFire)
    }

    /// First launch with no entries ever. `lastCaptureAt` is nil.
    /// Schedule the next nudge — today if not passed, tomorrow
    /// otherwise.
    @Test func firesForFirstTimeEver_withNoEntriesYet() {
        let now = date(2026, 6, 2, 14, 0) // 2 PM
        let expectedFire = date(2026, 6, 2, 20, 0) // 8 PM same day
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: nil,
            nudgeMinutes: minutes(20, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == expectedFire)
    }

    /// Capture happened EXACTLY at the window boundary (windowStart
    /// itself). Lock the inclusive boundary: a capture AT the
    /// window start counts as covering the window → suppress.
    @Test func suppresses_whenCaptureAtExactWindowStart() {
        let lastCapture = date(2026, 6, 1, 20, 0)
        let now = date(2026, 6, 2, 19, 55)
        let result = DailyNudgePolicy.nextFireDate(
            lastCaptureAt: lastCapture,
            nudgeMinutes: minutes(20, 0),
            now: now,
            calendar: calendar
        )
        #expect(result == nil)
    }
}
