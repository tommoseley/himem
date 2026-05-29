import Foundation

/// Pure formatter for the Captured Clips screen's subtitle line
/// ("3 sessions · May 27 3:37 PM – yesterday 6:30 PM"). Lifted out
/// of `SessionListView` 2026-05-29 to close a bug where the prior
/// inline logic used the earliest clip's day for the date label but
/// then rendered a time range that included the latest clip's
/// time — which silently lied when the two clips were captured on
/// different calendar days (Tom's exact QA scenario: "May 27,
/// 3:37 PM–6:30 PM" while the 6:30 PM clip was actually May 28).
///
/// **Contract:** the returned string must never disagree with the
/// underlying dates. If `earliest` and `latest` are on the same
/// calendar day, render the single-day form. If they cross a day
/// boundary, render the long form with explicit day labels on
/// both ends.
enum CapturedClipsSubtitleBuilder {

    /// Builds the subtitle. `calendar` and `now` are injected so
    /// tests can pin to a deterministic timezone.
    static func subtitle(
        earliest: Date,
        latest: Date,
        sessionCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let sessionPart = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"

        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.timeZone = calendar.timeZone
        timeFmt.dateFormat = "h:mm a"
        let earliestTime = timeFmt.string(from: earliest)
        let latestTime = timeFmt.string(from: latest)

        let earliestDay = dayLabel(for: earliest, now: now, calendar: calendar)
        let latestDay = dayLabel(for: latest, now: now, calendar: calendar)

        // Same calendar day → "<sessionPart> · <day>, <timeRange>"
        if calendar.isDate(earliest, inSameDayAs: latest) {
            let timeRange = earliestTime == latestTime ? earliestTime : "\(earliestTime)–\(latestTime)"
            return "\(sessionPart) · \(earliestDay), \(timeRange)"
        }

        // Cross-day → "<sessionPart> · <earlyDay> <earlyTime> – <lateDay> <lateTime>"
        // Both day labels surface so the user can never be misled
        // about when the latest clip was actually captured.
        return "\(sessionPart) · \(earliestDay) \(earliestTime) – \(latestDay) \(latestTime)"
    }

    /// Sync-aware variant. When at least one clip is syncing
    /// (downloading / waiting / transcribing in
    /// `InboxArrivalTracker`), the counts portion of the subtitle
    /// breaks out "K ready · J syncing" so the user sees both
    /// totals at a glance. Time range covers the full set so the
    /// header window reflects everything in the inbox, in flight
    /// or not. Spec § SYNC / INCOMING (`CCHeaderSync`).
    static func syncAwareSubtitle(
        earliest: Date,
        latest: Date,
        readySessionCount: Int,
        syncingClipCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        // Counts portion adapts to whether anything is in flight.
        let countsPart: String
        if syncingClipCount > 0 {
            let readyLabel = "\(readySessionCount) ready"
            let syncingLabel = syncingClipCount == 1
                ? "1 syncing"
                : "\(syncingClipCount) syncing"
            countsPart = "\(readyLabel) · \(syncingLabel)"
        } else {
            countsPart = readySessionCount == 1
                ? "1 session"
                : "\(readySessionCount) sessions"
        }

        // Time-range portion is the same dance as `subtitle(...)`.
        let timeFmt = DateFormatter()
        timeFmt.calendar = calendar
        timeFmt.timeZone = calendar.timeZone
        timeFmt.dateFormat = "h:mm a"
        let earliestTime = timeFmt.string(from: earliest)
        let latestTime = timeFmt.string(from: latest)
        let earliestDay = dayLabel(for: earliest, now: now, calendar: calendar)
        let latestDay = dayLabel(for: latest, now: now, calendar: calendar)
        if calendar.isDate(earliest, inSameDayAs: latest) {
            let timeRange = earliestTime == latestTime ? earliestTime : "\(earliestTime)–\(latestTime)"
            return "\(countsPart) · \(earliestDay), \(timeRange)"
        }
        return "\(countsPart) · \(earliestDay) \(earliestTime) – \(latestDay) \(latestTime)"
    }

    /// Same rules as the existing header used: today / yesterday /
    /// "MMM d". Pulled into a helper so both ends of a cross-day
    /// range can reuse it.
    private static func dayLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
