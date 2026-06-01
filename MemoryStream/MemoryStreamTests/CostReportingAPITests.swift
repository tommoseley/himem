import Testing
import Foundation
@testable import HiMem

/// Locks the iOS half of the COGS-logging contract documented in
/// `docs/api/himem-cost-logging.md`. These tests are pure — no
/// network — and exercise:
///   - `ReportPeriod.queryFragment` strings (server matches by
///     exact value; a rename here silently breaks the deployed app)
///   - `CostReport` JSON decoding from the server's snake_case shape
///   - `makeAnalyzeRequestBody` / `makeCleanupRequestBody`:
///     tier + action present, empty optional arrays omitted
///   - `ProcessingEngine` forwards the production tier + the
///     `memory_organize` action to the analyzer on the cloud path
///
/// If these fail, either the spec doc and the server's
/// `_resolve_period` / Pydantic models are out of sync with iOS,
/// or someone changed a string that's a wire contract.
@MainActor
@Suite(.serialized)
struct CostReportingAPITests {

    // MARK: - ReportPeriod query strings (locked vocabulary)

    @Test func reportPeriod_yesterday_emitsYesterday() {
        #expect(ClaudeAPIService.ReportPeriod.yesterday.queryFragment == "yesterday")
    }

    @Test func reportPeriod_lastWeek_emitsLastWeekHyphenated() {
        #expect(ClaudeAPIService.ReportPeriod.lastWeek.queryFragment == "last-week")
    }

    @Test func reportPeriod_lastMonth_emitsLastMonthHyphenated() {
        #expect(ClaudeAPIService.ReportPeriod.lastMonth.queryFragment == "last-month")
    }

    @Test func reportPeriod_month_emitsZeroPaddedYearAndMonth() {
        // Padding matters — server's `_resolve_period` splits on `-`
        // and `int()`-parses, so `month-2026-6` would actually still
        // work, but lock the canonical 4-2 form. Anything else is a
        // bug to surface in test.
        let p = ClaudeAPIService.ReportPeriod.month(year: 2026, month: 6)
        #expect(p.queryFragment == "month-2026-06")

        let p2 = ClaudeAPIService.ReportPeriod.month(year: 2026, month: 12)
        #expect(p2.queryFragment == "month-2026-12")
    }

    // MARK: - CostReport JSON decoding

    @Test func costReport_decodesServerSnakeCase() throws {
        let json = """
        {
          "period_label": "June 2026",
          "from_iso": "2026-06-01T00:00:00Z",
          "to_iso": "2026-07-01T00:00:00Z",
          "event_count": 1247,
          "total_usd": 234.56,
          "by_tier":   { "free": 12.10, "plus_monthly": 189.42, "founders": 33.04 },
          "by_action": { "memory_organize": 134.20, "project_assist": 78.30 },
          "by_model":  { "claude-haiku-4-5-20251001": 234.56 }
        }
        """.data(using: .utf8)!

        let r = try JSONDecoder().decode(ClaudeAPIService.CostReport.self, from: json)

        #expect(r.periodLabel == "June 2026")
        #expect(r.fromISO == "2026-06-01T00:00:00Z")
        #expect(r.toISO == "2026-07-01T00:00:00Z")
        #expect(r.eventCount == 1247)
        #expect(r.totalUSD == 234.56)
        #expect(r.byTier["plus_monthly"] == 189.42)
        #expect(r.byAction["memory_organize"] == 134.20)
        #expect(r.byModel["claude-haiku-4-5-20251001"] == 234.56)
    }

    @Test func costReport_decodesEmptyPeriod() throws {
        // Spec: a period with no events returns event_count 0 and
        // empty bucket dicts. iOS must decode this cleanly so the
        // Settings → Cost Report screen can render "no events yet".
        let json = """
        {
          "period_label": "Yesterday",
          "from_iso": "2026-05-29T00:00:00Z",
          "to_iso": "2026-05-30T00:00:00Z",
          "event_count": 0,
          "total_usd": 0.0,
          "by_tier": {},
          "by_action": {},
          "by_model": {}
        }
        """.data(using: .utf8)!

        let r = try JSONDecoder().decode(ClaudeAPIService.CostReport.self, from: json)
        #expect(r.eventCount == 0)
        #expect(r.totalUSD == 0.0)
        #expect(r.byTier.isEmpty)
    }

    // MARK: - Request body builders

    @Test func makeAnalyzeRequestBody_includesTierAndAction() throws {
        let data = ClaudeAPIService.makeAnalyzeRequestBody(
            text: "Met with Sarah.",
            existingTopics: ["Garden"],
            existingMentions: ["Sarah"],
            tier: "plus_monthly",
            action: "memory_organize"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["text"] as? String == "Met with Sarah.")
        #expect(obj["tier"] as? String == "plus_monthly")
        #expect(obj["action"] as? String == "memory_organize")
        #expect((obj["existing_topics"] as? [String]) == ["Garden"])
        #expect((obj["existing_mentions"] as? [String]) == ["Sarah"])
    }

    @Test func makeAnalyzeRequestBody_omitsEmptyTopicAndMentionArrays() throws {
        // Pre-COGS server-prompt convention: empty arrays are omitted
        // from the body so the server's prompt branch ("user has no
        // existing topics — suggest a new one") fires correctly.
        // Adding tier/action must NOT regress that contract.
        let data = ClaudeAPIService.makeAnalyzeRequestBody(
            text: "First entry ever.",
            existingTopics: [],
            existingMentions: [],
            tier: "free",
            action: "memory_organize"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["existing_topics"] == nil)
        #expect(obj["existing_mentions"] == nil)
        #expect(obj["tier"] as? String == "free")
        #expect(obj["action"] as? String == "memory_organize")
    }

    @Test func makeCleanupRequestBody_includesTierAndAction() throws {
        let data = ClaudeAPIService.makeCleanupRequestBody(
            text: "uh so I was thinking",
            tier: "founders",
            action: "transcript_cleanup"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["text"] as? String == "uh so I was thinking")
        #expect(obj["tier"] as? String == "founders")
        #expect(obj["action"] as? String == "transcript_cleanup")
    }

    // MARK: - ProcessingEngine forwards production tier + action

    /// Captures whatever the engine passed for tier + action on the
    /// cloud path. Combined with `EntitlementService.setTier`, this
    /// proves the production call site (`ProcessingEngine
    /// .processWithCloud`) plumbs the live entitlement tier through
    /// to the analyzer rather than hard-coding it.
    private final class TierActionCapturingAnalyzer: EntryAnalyzer, @unchecked Sendable {
        var capturedTier: String = ""
        var capturedAction: String = ""
        func analyzeEntry(_ text: String, existingTopics: [String], existingMentions: [String], tier: String, action: String) async throws -> ClaudeAPIService.AnalysisResult {
            capturedTier = tier
            capturedAction = action
            return ClaudeAPIService.AnalysisResult(
                entities: [],
                topics: [],
                summary: "",
                title: nil,
                nextSteps: nil
            )
        }
    }

    @Test func processEntry_cloudPath_forwardsInjectedTier_plusMonthly() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = TierActionCapturingAnalyzer()
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: analyzer,
            consumeAssist: { /* irrelevant for this test */ },
            readTier: { "plus_monthly" }
        )

        let entry = try storage.createEntry(content: "Quick note.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)

        // Lock both: tier is whatever the readTier closure returns
        // (in production: the live EntitlementService rawValue), and
        // the action is the locked organize-pass string.
        #expect(analyzer.capturedTier == "plus_monthly")
        #expect(analyzer.capturedAction == "memory_organize")
    }

    @Test func processEntry_cloudPath_forwardsInjectedTier_free() async throws {
        let storage = StorageService(inMemory: true)
        let analyzer = TierActionCapturingAnalyzer()
        let engine = ProcessingEngine(
            storage: storage,
            analyzer: analyzer,
            consumeAssist: { /* irrelevant for this test */ },
            readTier: { "free" }
        )

        let entry = try storage.createEntry(content: "Free-tier note.", inputType: .typed)
        _ = try storage.createProcessingTask(for: entry)

        await engine.processEntry(entry)

        #expect(analyzer.capturedTier == "free")
    }

    // Note: the production default `readTier` (a 1-line closure
    // that reads `EntitlementService.shared.tier.rawValue`) is not
    // exercised in unit tests — covering it requires mutating the
    // shared singleton, which races with `ProcessingEngineFallback
    // Tests.reprocess_upgradesLocalEntriesToCloud` across suite
    // brackets. The default is review-checkable; the production
    // smoke (set tier in Settings → organize → confirm tier in
    // `cost-report` output) verifies end-to-end.
}
