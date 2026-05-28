import Testing
import Foundation
@testable import HiMem

/// Tests for the day-group header formatter on `JournalView`. The
/// formatter was a private method buried in the view; lifted to a
/// static `JournalView.dateLabel(for:calendar:)` during the CRAP
/// audit 2026-05-28 (Batch 1) so it's testable without rendering.
///
/// "Today" and "Yesterday" win over the default weekday format —
/// regression here would mean the feed's day separators stop matching
/// "Today / Yesterday / Tuesday, May 27" reading the user expects.
@MainActor
@Suite(.serialized)
struct JournalDateLabelTests {

    private var calendar: Calendar { .current }

    @Test func today_returnsTodayLabel() {
        let label = JournalView.dateLabel(for: Date(), calendar: calendar)
        #expect(label == "Today")
    }

    @Test func yesterday_returnsYesterdayLabel() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let label = JournalView.dateLabel(for: yesterday, calendar: calendar)
        #expect(label == "Yesterday")
    }

    @Test func olderDate_returnsWeekdayMonthDayFormat() {
        // Pick a date safely in the past so it doesn't collide with
        // "Today" or "Yesterday" on any test runner clock.
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let label = JournalView.dateLabel(for: oneWeekAgo, calendar: calendar)
        // Format is "EEEE, MMMM d" — a comma separates weekday and
        // month-day, so the label always contains a comma for older
        // dates and never for Today/Yesterday.
        #expect(label.contains(","))
        #expect(label != "Today")
        #expect(label != "Yesterday")
    }
}
