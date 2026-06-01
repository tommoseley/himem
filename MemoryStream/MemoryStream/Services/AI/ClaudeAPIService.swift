import Foundation

final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private static let analyzeURLString = "https://api.thecombine.ai/himem/analyze"
    private static let cleanupURLString = "https://api.thecombine.ai/himem/cleanup"
    private static let costReportURLString = "https://api.thecombine.ai/himem/cost-report"

    private let analyzeURL = URL(string: analyzeURLString)!

    // MARK: - Types

    struct AnalysisResult: Codable {
        let entities: [EntityResult]
        let topics: [String]
        let summary: String
        let title: String?
        /// Server-returned next-step bullets — short, verb-first,
        /// concrete actions / commitments / reminders / follow-ups.
        /// Optional so responses from servers that haven't yet been
        /// updated to emit this field decode cleanly (treated the same
        /// as an empty array — Next steps row hides in the UI).
        ///
        /// Server contract (see `docs/design/next-steps-server-prompt.md`):
        /// only populated when the memory contains a concrete action.
        /// No invented "consider reflecting on…" filler. Strings
        /// suitable as Reminders/Calendar titles down the line.
        let nextSteps: [String]?
    }

    struct EntityResult: Codable {
        let type: String
        let value: String
        let confidence: Double
    }

    struct CleanupResult: Codable {
        let text: String
    }

    /// Cost-report aggregate as returned by `GET /himem/cost-report`.
    /// Wire shape pinned in `docs/api/himem-cost-logging.md`; keys
    /// here map snake_case → camelCase via `CodingKeys`.
    struct CostReport: Codable, Equatable {
        let periodLabel: String
        let fromISO: String
        let toISO: String
        let eventCount: Int
        let totalUSD: Double
        let byTier: [String: Double]
        let byAction: [String: Double]
        let byModel: [String: Double]

        enum CodingKeys: String, CodingKey {
            case periodLabel = "period_label"
            case fromISO = "from_iso"
            case toISO = "to_iso"
            case eventCount = "event_count"
            case totalUSD = "total_usd"
            case byTier = "by_tier"
            case byAction = "by_action"
            case byModel = "by_model"
        }
    }

    /// Named cost-report periods the iOS surface and server agree on.
    /// Lock these strings — server matches by exact value, and
    /// renaming would silently break the deployed app.
    enum ReportPeriod: Equatable {
        case yesterday
        case lastWeek
        case lastMonth
        case month(year: Int, month: Int)

        /// Value for the `?period=` query parameter, e.g.
        /// `yesterday`, `last-week`, `last-month`, `month-2026-06`.
        /// Server's `_resolve_period` is the matching parser.
        var queryFragment: String {
            switch self {
            case .yesterday: return "yesterday"
            case .lastWeek:  return "last-week"
            case .lastMonth: return "last-month"
            case .month(let year, let month):
                return String(format: "month-%04d-%02d", year, month)
            }
        }
    }

    // MARK: - Request body builders (pure, testable)

    /// Pure builder for the analyze request body. Tested in
    /// `CostReportingAPITests` — verifies tier/action are included
    /// and empty topic/mention arrays are omitted (preserves the
    /// pre-COGS server-prompt convention).
    static func makeAnalyzeRequestBody(
        text: String,
        existingTopics: [String],
        existingMentions: [String],
        tier: String,
        action: String
    ) -> Data {
        var body: [String: Any] = [
            "text": text,
            "tier": tier,
            "action": action,
        ]
        if !existingTopics.isEmpty {
            body["existing_topics"] = existingTopics
        }
        if !existingMentions.isEmpty {
            body["existing_mentions"] = existingMentions
        }
        // Force-try is safe: `body` only contains JSON-representable
        // types (String, [String], [String:Any] of the same). A
        // serialization failure here would mean the runtime is
        // broken in a way the app can't recover from.
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func makeCleanupRequestBody(
        text: String,
        tier: String,
        action: String
    ) -> Data {
        let body: [String: Any] = [
            "text": text,
            "tier": tier,
            "action": action,
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Analyze

    func analyzeEntry(
        _ text: String,
        existingTopics: [String] = [],
        existingMentions: [String] = [],
        tier: String,
        action: String
    ) async throws -> AnalysisResult {
        var request = URLRequest(url: analyzeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        request.httpBody = Self.makeAnalyzeRequestBody(
            text: text,
            existingTopics: existingTopics,
            existingMentions: existingMentions,
            tier: tier,
            action: action
        )

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard response.statusCode == 200 else {
            throw APIError.httpError(statusCode: response.statusCode)
        }

        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    // MARK: - Cleanup

    func cleanupTranscription(
        _ text: String,
        tier: String,
        action: String = "transcript_cleanup"
    ) async throws -> String {
        let cleanupURL = URL(string: Self.cleanupURLString)!

        var request = URLRequest(url: cleanupURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        request.httpBody = Self.makeCleanupRequestBody(
            text: text,
            tier: tier,
            action: action
        )

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard response.statusCode == 200 else {
            throw APIError.httpError(statusCode: response.statusCode)
        }

        return try JSONDecoder().decode(CleanupResult.self, from: data).text
    }

    // MARK: - Cost report

    /// Fetches the aggregate cost report for the given period. See
    /// `docs/api/himem-cost-logging.md` for the wire contract and
    /// the server-side period semantics.
    func fetchCostReport(period: ReportPeriod) async throws -> CostReport {
        guard var components = URLComponents(string: Self.costReportURLString) else {
            throw APIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "period", value: period.queryFragment)]
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw APIError.httpError(statusCode: response.statusCode)
        }

        return try JSONDecoder().decode(CostReport.self, from: data)
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server."
            case .httpError(let code):
                return "Processing failed (status \(code)). Please try again later."
            }
        }
    }
}
