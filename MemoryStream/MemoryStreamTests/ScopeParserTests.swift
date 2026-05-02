import Testing
import Foundation
@testable import MemoryStream

struct ScopeParserTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = hour
        return calendar.date(from: comps)!
    }

    // MARK: - Empty / plain text

    @Test func parse_empty_isAllEmpty() {
        let q = ScopeParser.parse("")
        #expect(q == ParsedQuery())
    }

    @Test func parse_plainText_goesToTextField() {
        let q = ScopeParser.parse("tomato seedlings")
        #expect(q.text == "tomato seedlings")
        #expect(q.topicSlug == nil)
        #expect(q.typeScope == nil)
        #expect(q.dateRange == nil)
    }

    // MARK: - Topic scope

    @Test func parse_topicScope_capturesSlug() {
        let q = ScopeParser.parse("topic:garden")
        #expect(q.topicSlug == "garden")
        #expect(q.text == "")
    }

    @Test func parse_topicScope_lowercasesValue() {
        let q = ScopeParser.parse("topic:Garden")
        #expect(q.topicSlug == "garden")
    }

    @Test func parse_topicScope_withResidualText() {
        let q = ScopeParser.parse("topic:garden tomato")
        #expect(q.topicSlug == "garden")
        #expect(q.text == "tomato")
    }

    // MARK: - Type scope

    @Test func parse_typeVoice() {
        #expect(ScopeParser.parse("type:voice").typeScope == .voice)
    }

    @Test func parse_typeText() {
        #expect(ScopeParser.parse("type:text").typeScope == .text)
    }

    @Test func parse_typePhoto() {
        #expect(ScopeParser.parse("type:photo").typeScope == .photo)
    }

    @Test func parse_typeVideo() {
        #expect(ScopeParser.parse("type:video").typeScope == .video)
    }

    @Test func parse_typeUnknown_isIgnored_andLeavesTokenInText() {
        let q = ScopeParser.parse("type:bogus tomato")
        #expect(q.typeScope == nil)
        #expect(q.text == "type:bogus tomato")
    }

    // MARK: - Composition

    @Test func parse_composesTopicTypeAndText() {
        let q = ScopeParser.parse("topic:garden type:voice tomato")
        #expect(q.topicSlug == "garden")
        #expect(q.typeScope == .voice)
        #expect(q.text == "tomato")
    }

    @Test func parse_lastSameScopeWins() {
        let q = ScopeParser.parse("topic:garden topic:cooking")
        #expect(q.topicSlug == "cooking")
    }

    // MARK: - Date scope

    @Test func parse_dateToday_isCalendarDay() {
        let now = date(2026, 5, 1, hour: 14)
        let q = ScopeParser.parse("date:today", now: now, calendar: calendar)
        let expected = calendar.dateInterval(of: .day, for: now)
        #expect(q.dateRange == expected)
    }

    @Test func parse_dateYesterday() {
        let now = date(2026, 5, 1, hour: 14)
        let q = ScopeParser.parse("date:yesterday", now: now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(q.dateRange == calendar.dateInterval(of: .day, for: yesterday))
    }

    @Test func parse_dateThisWeek() {
        let now = date(2026, 5, 1, hour: 14) // a Friday
        let q = ScopeParser.parse("date:this-week", now: now, calendar: calendar)
        #expect(q.dateRange == calendar.dateInterval(of: .weekOfYear, for: now))
    }

    @Test func parse_dateLastMonth() {
        let now = date(2026, 5, 1, hour: 14)
        let q = ScopeParser.parse("date:last-month", now: now, calendar: calendar)
        let april = calendar.date(byAdding: .month, value: -1, to: now)!
        #expect(q.dateRange == calendar.dateInterval(of: .month, for: april))
    }

    @Test func parse_dateYear_coversFullYear() {
        let q = ScopeParser.parse("date:2024", calendar: calendar)
        let start = date(2024, 1, 1, hour: 0)
        let dayOfStart = calendar.startOfDay(for: start)
        #expect(q.dateRange?.start == dayOfStart)
        let end = calendar.date(byAdding: .year, value: 1, to: dayOfStart)!
        #expect(q.dateRange?.end == end)
    }

    @Test func parse_dateBeforeISO_endsAtDay() {
        let q = ScopeParser.parse("date:before:2024-04-01", calendar: calendar)
        let day = calendar.startOfDay(for: date(2024, 4, 1, hour: 0))
        #expect(q.dateRange?.start == .distantPast)
        #expect(q.dateRange?.end == day)
    }

    @Test func parse_dateAfterISO_startsAtDay() {
        let q = ScopeParser.parse("date:after:2024-04-01", calendar: calendar)
        let day = calendar.startOfDay(for: date(2024, 4, 1, hour: 0))
        #expect(q.dateRange?.start == day)
        #expect(q.dateRange?.end == .distantFuture)
    }

    @Test func parse_dateUnknown_isIgnored() {
        let q = ScopeParser.parse("date:whenever tomato", calendar: calendar)
        #expect(q.dateRange == nil)
        #expect(q.text == "date:whenever tomato")
    }

    @Test func parse_dateMissingValue_isIgnored() {
        let q = ScopeParser.parse("date: tomato", calendar: calendar)
        #expect(q.dateRange == nil)
        #expect(q.text == "date: tomato")
    }

    // MARK: - Edge cases

    @Test func parse_keyOnly_isText() {
        let q = ScopeParser.parse("topic")
        #expect(q.topicSlug == nil)
        #expect(q.text == "topic")
    }

    @Test func parse_emptyValue_isIgnored() {
        let q = ScopeParser.parse("topic: tomato")
        #expect(q.topicSlug == nil)
        #expect(q.text == "topic: tomato")
    }

    @Test func parse_caseInsensitiveScopeKey() {
        let q = ScopeParser.parse("Topic:Garden TYPE:Voice")
        #expect(q.topicSlug == "garden")
        #expect(q.typeScope == .voice)
    }

    @Test func parse_preservesTextCase() {
        let q = ScopeParser.parse("Tomato SEEDS topic:garden")
        #expect(q.text == "Tomato SEEDS")
        #expect(q.topicSlug == "garden")
    }

    @Test func parse_collapsesMultipleSpaces() {
        let q = ScopeParser.parse("  hello   world  ")
        #expect(q.text == "hello world")
    }

    @Test func parse_textWithColonNotScope_staysInText() {
        // Free text containing a colon but unknown key falls through.
        let q = ScopeParser.parse("note: see later")
        #expect(q.topicSlug == nil)
        #expect(q.typeScope == nil)
        #expect(q.text == "note: see later")
    }
}
