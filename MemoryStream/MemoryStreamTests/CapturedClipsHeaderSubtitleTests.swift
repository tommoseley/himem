import Testing
import Foundation
@testable import HiMem

/// Money tests for the Captured Clips header subtitle.
///
/// The bug (2026-05-29): inbox contained clips spanning two days
/// (May 27 3:37 PM, May 27 3:46 PM, May 28 6:30 PM). Header subtitle
/// rendered "3 sessions · May 27, 3:37 PM–6:30 PM" — collapsing the
/// 6:30 PM clip to the earlier day. The date and the time range
/// disagreed: clearly false information about when the clips were
/// captured.
///
/// Root cause: `headerSubtitle` derived `dayLabel` from `first`
/// (the earliest clip) and a time range from `first`/`last`, without
/// checking whether they were on the same calendar day.
///
/// Fix: pure `subtitleString` static that emits separate day labels
/// for the ends of the range when they're on different days, and
/// the single-day form when they're not.
@MainActor
@Suite(.serialized)
struct CapturedClipsHeaderSubtitleTests {

    /// A fixed reference "now" anchored to noon UTC so the
    /// today/yesterday tests don't depend on what time of day the
    /// suite runs.
    private var now: Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 5, day: 29, hour: 12, minute: 0)
        )!
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: y, month: m, day: d, hour: h, minute: min
        ))!
    }

    // MARK: - Same-day ranges

    @Test func sameDayToday_includesTodayLabel() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 29, 9, 0),
            latest: date(2026, 5, 29, 10, 30),
            sessionCount: 2,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("today"))
        #expect(s.contains("9:00 AM"))
        #expect(s.contains("10:30 AM"))
        #expect(s.contains("2 sessions"))
    }

    @Test func sameDayYesterday_includesYesterdayLabel() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 28, 9, 0),
            latest: date(2026, 5, 28, 10, 30),
            sessionCount: 1,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("yesterday"))
        #expect(s.contains("1 session"))
    }

    @Test func sameDayOlder_usesMonthDayLabel() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 20, 9, 0),
            latest: date(2026, 5, 20, 10, 30),
            sessionCount: 3,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("May 20"))
        // Must NOT carry the today / yesterday shortcuts when the
        // day is too old.
        #expect(!s.contains("today"))
        #expect(!s.contains("yesterday"))
    }

    // MARK: - Cross-day ranges (the bug)

    /// **THE BUG.** Tom's exact scenario: 3:37 PM May 27 to 6:30 PM
    /// May 28, with "today" being May 29. Pre-fix string was
    /// "3 sessions · May 27, 3:37 PM–6:30 PM" — the 6:30 PM clip's
    /// date got eaten.
    @Test func crossDay_doesNotLieAboutTheLatestClipDay() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 27, 15, 37),
            latest: date(2026, 5, 28, 18, 30),
            sessionCount: 3,
            now: now,
            calendar: calendar
        )
        // Both day signals must be present somewhere in the string.
        // The earliest clip was on May 27.
        #expect(s.contains("May 27"))
        // The latest clip was yesterday (relative to May 29). It
        // MUST surface — pre-fix code dropped it entirely.
        #expect(s.contains("yesterday"))
        #expect(s.contains("3 sessions"))
    }

    @Test func crossDay_olderToYesterday_includesBothDayLabels() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 20, 9, 0),
            latest: date(2026, 5, 28, 18, 0),
            sessionCount: 5,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("May 20"))
        #expect(s.contains("yesterday"))
    }

    @Test func crossDay_yesterdayToToday_includesBothDayLabels() {
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 28, 23, 30),
            latest: date(2026, 5, 29, 0, 30),
            sessionCount: 2,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("yesterday"))
        #expect(s.contains("today"))
    }

    // MARK: - Time formatting

    @Test func sameTime_doesNotRenderRedundantRange() {
        // Edge case: only one clip in the inbox, so first == last.
        // No "9:00 AM–9:00 AM" garbage.
        let s = CapturedClipsSubtitleBuilder.subtitle(
            earliest: date(2026, 5, 29, 9, 0),
            latest: date(2026, 5, 29, 9, 0),
            sessionCount: 1,
            now: now,
            calendar: calendar
        )
        #expect(s.contains("9:00 AM"))
        #expect(!s.contains("9:00 AM–9:00 AM"))
        #expect(!s.contains("9:00 AM-9:00 AM"))
    }
}
