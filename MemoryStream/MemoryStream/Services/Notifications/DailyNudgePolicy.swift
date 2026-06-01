import Foundation

/// Pure decision surface for the daily nudge scheduler.
///
/// The shipped product (per Tom's Settings screenshot 2026-06-01)
/// is a user-chosen-time-of-day nudge that suppresses if the user
/// captured anything in the 24h window ending now. The chosen time
/// is the rollover anchor — picking midnight gives calendar-day
/// semantics (the legacy behavior); picking 8 PM gives 8 PM-to-8 PM
/// semantics.
///
/// Extracted from `NotificationService.refreshDailyNudge` so the
/// rollover math is testable without standing up `UNUserNotification
/// Center`, `UserDefaults`, or Core Data. `NotificationService`
/// composes this with the toggle check, scheduling, and request
/// identifier.
///
/// Spec home: `docs/design/CLAUDE.md` § Notifications · Channel B.
/// The current spec there describes the OLD 24h-baseline + weekly
/// cadence model; Step 13 of the pre-launch repair pass revises the
/// spec to match this shipped model.
enum DailyNudgePolicy {

    /// Given the user's chosen nudge time + the timestamp of the
    /// most recent capture (watch arrival or phone memory) + the
    /// current time, return the Date at which the next nudge should
    /// fire. `nil` if no fire should be scheduled — either because
    /// the user captured inside the rollover window or because the
    /// caller wants to leave existing schedules alone.
    ///
    /// **Rollover semantics:** the "window ending now" starts at the
    /// most recent occurrence of `nudgeMinutes` at or before `now`
    /// (i.e., the previous chosen-time tick). A capture timestamp
    /// `>= windowStart` suppresses the next nudge; a capture before
    /// the window opened doesn't count.
    ///
    /// **Schedule semantics:** when not suppressed, the next nudge
    /// fires at the next-occurring chosen-time tick. If today's tick
    /// hasn't passed yet, today; otherwise tomorrow. The scheduler
    /// always books a concrete Date — no "wait for the next refresh
    /// call to handle tomorrow" reliance, which under the prior
    /// `hasEntryToday` design left tomorrow's nudge un-scheduled if
    /// the user never opened the app between today's miss and
    /// tomorrow's anchor.
    static func nextFireDate(
        lastCaptureAt: Date?,
        nudgeMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let nudgeHour = nudgeMinutes / 60
        let nudgeMinute = nudgeMinutes % 60

        // The chosen-time tick that anchors today's nudge (could be
        // earlier or later than `now`).
        guard let todayTick = calendar.date(
            bySettingHour: nudgeHour,
            minute: nudgeMinute,
            second: 0,
            of: now
        ) else {
            return nil
        }

        // Window start = the most recent chosen-time tick at or
        // before `now`. If today's tick already passed → use it.
        // Otherwise the window opened yesterday at the chosen time.
        let windowStart: Date
        if todayTick > now {
            guard let yesterdayTick = calendar.date(byAdding: .day, value: -1, to: todayTick) else {
                return nil
            }
            windowStart = yesterdayTick
        } else {
            windowStart = todayTick
        }

        // Capture covers the window (inclusive boundary) → user is
        // covered, no nudge.
        if let lastCaptureAt, lastCaptureAt >= windowStart {
            return nil
        }

        // Fire at the NEXT chosen-time tick — today if not passed,
        // tomorrow if passed.
        if todayTick > now {
            return todayTick
        }
        return calendar.date(byAdding: .day, value: 1, to: todayTick)
    }
}
