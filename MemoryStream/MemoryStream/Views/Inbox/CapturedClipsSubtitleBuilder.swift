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
    ///
    /// **`sessionCount: nil` drops the session term entirely**, leaving the
    /// span alone (ruled by Tom, 2026-08-09). A header saying "1 session"
    /// over a cluster card asserts the grouping the card is only *proposing*
    /// — J5's observe-don't-conclude line, crossed by the surface's own
    /// chrome rather than by the AI. *"1 group"* was rejected too: it mints a
    /// noun the user has not accepted, and a second word for a sitting she
    /// would have to learn. Saying less is the honest option — the span is a
    /// fact about drawn items however they are grouped, and the cluster card
    /// already speaks for itself in its own careful language.
    ///
    /// The caller decides *whether* the term is carried (`DrawnBench
    /// .sessionTerm` is nil when every session is clustered); this only
    /// decides how it reads. **The arithmetic is uniform; only the sentence
    /// is conditional.**
    static func subtitle(
        earliest: Date,
        latest: Date,
        sessionCount: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let sessionPart = sessionCount.map { $0 == 1 ? "1 session" : "\($0) sessions" }
        let span = spanText(
            earliest: earliest, latest: latest, now: now, calendar: calendar
        )
        guard let sessionPart else { return span }
        return "\(sessionPart) · \(span)"
    }

    /// The time-range half, shared by both variants. Same calendar day →
    /// "<day>, <timeRange>"; cross-day → "<earlyDay> <earlyTime> – <lateDay>
    /// <lateTime>", with both day labels surfaced so the user can never be
    /// misled about when the latest clip was actually captured.
    private static func spanText(
        earliest: Date,
        latest: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
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
            return "\(earliestDay), \(timeRange)"
        }
        return "\(earliestDay) \(earliestTime) – \(latestDay) \(latestTime)"
    }

    /// Sync-aware variant. When at least one clip is syncing
    /// (downloading / waiting / transcribing in
    /// `InboxArrivalTracker`), the counts portion of the subtitle
    /// breaks out "K ready · J syncing" so the user sees both
    /// totals at a glance. Time range covers the full set so the
    /// header window reflects everything in the inbox, in flight
    /// or not. Spec § SYNC / INCOMING (`CCHeaderSync`).
    ///
    /// **`readySessionCount: nil` drops the ready-session term**, on the same
    /// ruling as `subtitle`. The syncing count is *not* dropped with it: "2
    /// syncing" reports transfer state, which the surface knows for certain,
    /// where "1 session" would assert a grouping the cluster card is only
    /// proposing. Only the term that claims a grouping is conditional.
    static func syncAwareSubtitle(
        earliest: Date,
        latest: Date,
        readySessionCount: Int?,
        syncingClipCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        // Counts portion adapts to whether anything is in flight.
        let readyPart = readySessionCount.map { count -> String in
            syncingClipCount > 0
                ? "\(count) ready"
                : (count == 1 ? "1 session" : "\(count) sessions")
        }
        let syncingPart = syncingClipCount > 0
            ? (syncingClipCount == 1 ? "1 syncing" : "\(syncingClipCount) syncing")
            : nil
        let countsPart = [readyPart, syncingPart].compactMap { $0 }.joined(separator: " · ")

        let span = spanText(
            earliest: earliest, latest: latest, now: now, calendar: calendar
        )
        guard !countsPart.isEmpty else { return span }
        return "\(countsPart) · \(span)"
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
