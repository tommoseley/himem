import Testing
import Foundation
@testable import MemoryStream

/// Tests for SearchViewModel.bucket — the pure date-classification used by
/// groupedHits to slot search results into Today/Yesterday/This week/etc.
/// Uses a fixed Gregorian UTC calendar so the boundaries don't drift.
struct SearchViewModelBucketTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        return calendar.date(from: c)!
    }

    @Test func bucket_today() {
        let now = date(2026, 5, 15, hour: 14)
        let earlierToday = date(2026, 5, 15, hour: 8)
        #expect(SearchViewModel.bucket(for: earlierToday, now: now, calendar: calendar) == .today)
    }

    @Test func bucket_yesterday() {
        let now = date(2026, 5, 15, hour: 14)
        let yesterday = date(2026, 5, 14, hour: 22)
        #expect(SearchViewModel.bucket(for: yesterday, now: now, calendar: calendar) == .yesterday)
    }

    @Test func bucket_thisWeek_excludesYesterday() {
        // Friday May 15. Same week (Mon May 11 — Sun May 17).
        let now = date(2026, 5, 15, hour: 14) // Friday
        let monday = date(2026, 5, 11, hour: 12) // Same week
        #expect(SearchViewModel.bucket(for: monday, now: now, calendar: calendar) == .thisWeek)
    }

    @Test func bucket_thisMonth_excludesThisWeek() {
        let now = date(2026, 5, 15, hour: 14)
        // Same month, but earlier than this week's Monday (May 11). May 5 is in
        // a prior week of May.
        let earlierInMonth = date(2026, 5, 5, hour: 12)
        #expect(SearchViewModel.bucket(for: earlierInMonth, now: now, calendar: calendar) == .thisMonth)
    }

    @Test func bucket_lastMonth() {
        let now = date(2026, 5, 15, hour: 14)
        let lastMonth = date(2026, 4, 20, hour: 12)
        #expect(SearchViewModel.bucket(for: lastMonth, now: now, calendar: calendar) == .lastMonth)
    }

    @Test func bucket_earlierThisYear() {
        let now = date(2026, 5, 15, hour: 14)
        let february = date(2026, 2, 1, hour: 12)
        #expect(SearchViewModel.bucket(for: february, now: now, calendar: calendar) == .earlierThisYear)
    }

    @Test func bucket_older_priorYear() {
        let now = date(2026, 5, 15, hour: 14)
        let lastYear = date(2024, 11, 3, hour: 12)
        #expect(SearchViewModel.bucket(for: lastYear, now: now, calendar: calendar) == .older)
    }

    @Test func bucket_boundary_endOfLastMonthGoesToLastMonth_notEarlierThisYear() {
        // April 30 with now = May 15. Should be lastMonth, not earlierThisYear.
        let now = date(2026, 5, 15, hour: 14)
        let lastDayOfApril = date(2026, 4, 30, hour: 23)
        #expect(SearchViewModel.bucket(for: lastDayOfApril, now: now, calendar: calendar) == .lastMonth)
    }
}
