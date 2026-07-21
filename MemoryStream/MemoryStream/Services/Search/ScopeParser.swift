import Foundation

struct ParsedQuery: Equatable {
    var text: String = ""
    var topicSlug: String?
    var typeScope: TypeScope?
    var dateRange: DateInterval?
}

enum TypeScope: String, CaseIterable, Equatable {
    case voice
    case text
    case photo
    case video
}

/// Which object a search returns (`Himem · Search.html` §"Object scope").
/// Default `.memories` — the narrative unit; a memory's searchable text
/// already includes its clips' transcripts, so it covers spoken words.
/// `.clips` surfaces matching clips directly (essential: a loose clip is
/// invisible to a memory-only search). `.all` interleaves both.
enum ObjectScope: String, CaseIterable, Equatable {
    case memories
    case clips
    case all

    var label: String {
        switch self {
        case .memories: return "Memories"
        case .clips:    return "Clips"
        case .all:      return "All"
        }
    }
}

enum ScopeParser {

    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedQuery {
        var query = ParsedQuery()
        var residual: [String] = []

        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        for token in tokens {
            if let scope = consumeScope(token, now: now, calendar: calendar) {
                apply(scope, to: &query)
            } else {
                residual.append(token)
            }
        }

        query.text = residual.joined(separator: " ")
        return query
    }

    private enum Scope {
        case topic(String)
        case type(TypeScope)
        case date(DateInterval)
    }

    private static func consumeScope(_ token: String, now: Date, calendar: Calendar) -> Scope? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let key = token[..<colon].lowercased()
        let value = String(token[token.index(after: colon)...])
        guard !value.isEmpty else { return nil }

        switch key {
        case "topic":
            return .topic(value.lowercased())
        case "type":
            guard let scope = TypeScope(rawValue: value.lowercased()) else { return nil }
            return .type(scope)
        case "date":
            guard let interval = parseDateValue(value, now: now, calendar: calendar) else { return nil }
            return .date(interval)
        default:
            return nil
        }
    }

    private static func apply(_ scope: Scope, to query: inout ParsedQuery) {
        switch scope {
        case .topic(let slug):
            query.topicSlug = slug
        case .type(let type):
            query.typeScope = type
        case .date(let interval):
            query.dateRange = interval
        }
    }

    // MARK: - Date parsing

    private static func parseDateValue(_ value: String, now: Date, calendar: Calendar) -> DateInterval? {
        let lower = value.lowercased()
        switch lower {
        case "today":
            return dayInterval(containing: now, calendar: calendar)
        case "yesterday":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return dayInterval(containing: yesterday, calendar: calendar)
        case "this-week":
            return weekInterval(containing: now, calendar: calendar)
        case "last-week":
            guard let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
            return weekInterval(containing: lastWeek, calendar: calendar)
        case "this-month":
            return monthInterval(containing: now, calendar: calendar)
        case "last-month":
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return monthInterval(containing: lastMonth, calendar: calendar)
        default:
            break
        }

        if let year = Int(lower), year > 1900, year < 9999 {
            return yearInterval(year: year, calendar: calendar)
        }

        if lower.hasPrefix("before:") {
            let raw = String(lower.dropFirst("before:".count))
            guard let date = parseISODate(raw, calendar: calendar) else { return nil }
            return DateInterval(start: .distantPast, end: date)
        }

        if lower.hasPrefix("after:") {
            let raw = String(lower.dropFirst("after:".count))
            guard let date = parseISODate(raw, calendar: calendar) else { return nil }
            return DateInterval(start: date, end: .distantFuture)
        }

        return nil
    }

    private static func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date)
    }

    private static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    private static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .month, for: date)
    }

    private static func yearInterval(year: Int, calendar: Calendar) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .year, value: 1, to: start)
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private static func parseISODate(_ raw: String, calendar: Calendar) -> Date? {
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }
}
