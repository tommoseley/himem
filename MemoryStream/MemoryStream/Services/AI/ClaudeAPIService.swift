import Foundation

final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"
    private let apiVersion = "2023-06-01"

    private var apiKey: String {
        KeychainService.shared.retrieve(key: "anthropic_api_key") ?? ""
    }

    // MARK: - Entity Extraction + Topic Inference + Summary

    struct AnalysisResult: Codable {
        let entities: [EntityResult]
        let topics: [String]
        let summary: String
        let title: String?
    }

    struct EntityResult: Codable {
        let type: String       // "project", "person", "issue", "idea", "next_action"
        let value: String
        let confidence: Double
    }

    func analyzeEntry(_ text: String) async throws -> AnalysisResult {
        let prompt = """
        Analyze this journal entry and extract structured data. Return JSON only, no other text.

        Journal entry:
        \"\"\"\(text)\"\"\"

        Return this exact JSON structure:
        {
          "entities": [
            {"type": "project|person|issue|idea|next_action", "value": "short label", "confidence": 0.0-1.0}
          ],
          "topics": ["Topic Name"],
          "summary": "One or two sentence natural-language summary of what the AI inferred from this entry.",
          "title": "Short descriptive title for this entry or null"
        }

        Entity types:
        - project: A project, location, or named thing being worked on (e.g., "Bed 4", "Kitchen remodel")
        - person: A person mentioned by name
        - issue: A problem, concern, or thing needing attention (e.g., "Water stress", "pest damage")
        - idea: A creative thought or future possibility (e.g., "YouTube idea", "try drip irrigation")
        - next_action: A concrete, actionable task the user intends to do. Start with a verb. (e.g., "Water Bed 4", "Film YouTube video", "Buy compost")

        Rules for entity values:
        - Keep values SHORT: 1-4 words max. These are searchable tags, not sentences.
        - Normalize names consistently: always use digits for numbers ("Bed 4" not "Bed Four"). Always use singular form ("Bed 3" not "Beds 3"). Capitalize proper references ("Bed 4" not "bed 4").
        - Split compound references into separate entities: "beds 3, 5, and 7" becomes three entities: "Bed 3", "Bed 5", "Bed 7".
        - next_action must be clearly actionable — a user should be able to add it to a reminders list as-is.
        - Do not quote or echo full sentences from the entry as entity values.

        Topic: A high-level category this entry belongs to (e.g., "Garden", "Work", "Health", "Finance"). One or two words max.

        Summary: Write as if explaining to the user what the app understood. Use phrases like "linked to...", "flagged as...", "identified as...".

        Only include entities with confidence >= 0.7. Be precise, not exhaustive.
        """

        let response = try await sendMessage(prompt)
        return try parseAnalysisResult(response)
    }

    // MARK: - API Communication

    private func sendMessage(_ content: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: response.statusCode, body: errorBody)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }) else {
            throw APIError.noTextContent
        }

        return textContent.text
    }

    private func parseAnalysisResult(_ text: String) throws -> AnalysisResult {
        // Extract JSON from response — handle cases where the model wraps it in markdown
        let jsonString: String
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            jsonString = String(text[start...end])
        } else {
            throw APIError.parseError("No JSON object found in response")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw APIError.parseError("Failed to convert JSON string to data")
        }

        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    // MARK: - Response Types

    private struct APIResponse: Codable {
        let content: [ContentBlock]
    }

    private struct ContentBlock: Codable {
        let type: String
        let text: String
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case httpError(statusCode: Int, body: String)
        case noTextContent
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key configured."
            case .invalidResponse:
                return "Invalid response from API."
            case .httpError(let code, let body):
                return "API error \(code): \(body)"
            case .noTextContent:
                return "No text content in API response."
            case .parseError(let detail):
                return "Failed to parse API response: \(detail)"
            }
        }
    }
}
