import Testing
import Foundation
@testable import HiMem

/// Locks the wire contract for `/himem/project-assist`. Mirrors
/// `CostReportingAPITests` for `/himem/analyze` — pure builder +
/// decoder coverage so a server-side payload change can't slip
/// past the iOS client without flipping a test red.
@MainActor
@Suite(.serialized)
struct ProjectAssistAPITests {

    // MARK: - Request body builder

    @Test func makeProjectAssistRequestBody_includesTierAndAction() throws {
        let memory = ClaudeAPIService.ProjectMemoryInput(
            title: "Compost notes",
            topics: ["Garden"],
            summary: "linked to gardening",
            createdAt: "2026-06-01T12:00:00Z"
        )
        let data = ClaudeAPIService.makeProjectAssistRequestBody(
            projectName: "Building HiMem",
            projectGoal: "Ship v1",
            memories: [memory],
            tier: "founders"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["project_name"] as? String == "Building HiMem")
        #expect(obj["project_goal"] as? String == "Ship v1")
        #expect(obj["tier"] as? String == "founders")
        #expect(obj["action"] as? String == "project_assist")
    }

    @Test func makeProjectAssistRequestBody_omitsEmptyGoal() throws {
        let memory = ClaudeAPIService.ProjectMemoryInput(
            title: "x",
            topics: [],
            summary: nil,
            createdAt: "2026-06-01T12:00:00Z"
        )
        let data = ClaudeAPIService.makeProjectAssistRequestBody(
            projectName: "p",
            projectGoal: "",
            memories: [memory],
            tier: "free"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["project_goal"] == nil)
    }

    @Test func makeProjectAssistRequestBody_omitsWhitespaceOnlyGoal() throws {
        let memory = ClaudeAPIService.ProjectMemoryInput(
            title: "x",
            topics: [],
            summary: nil,
            createdAt: "2026-06-01T12:00:00Z"
        )
        let data = ClaudeAPIService.makeProjectAssistRequestBody(
            projectName: "p",
            projectGoal: "   ",
            memories: [memory],
            tier: "free"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["project_goal"] == nil)
    }

    @Test func makeProjectAssistRequestBody_passesOnlySpecApprovedFieldsPerMemory() throws {
        // Spec § "What it sees": title, topics, summary, date. NO
        // raw content (transcripts / fragments stay client-side).
        // Lock the contract — if a future contributor accidentally
        // adds `content` to the request, this test goes red.
        let memory = ClaudeAPIService.ProjectMemoryInput(
            title: "compost",
            topics: ["Garden", "How We Work"],
            summary: "linked to gardening",
            createdAt: "2026-06-01T12:00:00Z"
        )
        let data = ClaudeAPIService.makeProjectAssistRequestBody(
            projectName: "p",
            projectGoal: nil,
            memories: [memory],
            tier: "founders"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let mems = obj["memories"] as! [[String: Any]]
        #expect(mems.count == 1)
        let m = mems[0]
        #expect(m["title"] as? String == "compost")
        #expect((m["topics"] as? [String]) == ["Garden", "How We Work"])
        #expect(m["summary"] as? String == "linked to gardening")
        #expect(m["created_at"] as? String == "2026-06-01T12:00:00Z")
        // No raw content / fragment field.
        #expect(m["content"] == nil)
        #expect(m["fragments"] == nil)
        #expect(m["transcript"] == nil)
    }

    @Test func makeProjectAssistRequestBody_omitsNilTitleAndSummary() throws {
        // Untitled memory with no AI summary yet — both fields
        // omitted rather than rendered as `null`. Matches the
        // analyze endpoint's empty-array convention.
        let memory = ClaudeAPIService.ProjectMemoryInput(
            title: nil,
            topics: ["Garden"],
            summary: nil,
            createdAt: "2026-06-01T12:00:00Z"
        )
        let data = ClaudeAPIService.makeProjectAssistRequestBody(
            projectName: "p",
            projectGoal: nil,
            memories: [memory],
            tier: "free"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let m = (obj["memories"] as! [[String: Any]])[0]
        #expect(m["title"] == nil)
        #expect(m["summary"] == nil)
        #expect((m["topics"] as? [String]) == ["Garden"])
    }

    // MARK: - Response decoder

    @Test func projectAssistResult_decodesSummary() throws {
        let json = """
        {"summary":"The memories center on..."}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ClaudeAPIService.ProjectAssistResult.self, from: json)
        #expect(r.summary == "The memories center on...")
    }

    @Test func projectAssistResult_ignoresUnknownFields() throws {
        // The server may add `suggested_memberships` etc. in v1.1
        // — make sure v1 iOS clients decode cleanly when a server
        // ahead of them returns extra fields. (Default Codable
        // behavior; locked as a contract.)
        let json = """
        {"summary":"hello","extra_field":"ignored"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ClaudeAPIService.ProjectAssistResult.self, from: json)
        #expect(r.summary == "hello")
    }
}
