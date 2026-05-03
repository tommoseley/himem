import Foundation

final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let analyzeURL = URL(string: "https://api.thecombine.ai/himem/analyze")!

    // MARK: - Types

    struct AnalysisResult: Codable {
        let entities: [EntityResult]
        let topics: [String]
        let summary: String
        let title: String?
    }

    struct EntityResult: Codable {
        let type: String
        let value: String
        let confidence: Double
    }

    struct CleanupResult: Codable {
        let text: String
    }

    // MARK: - Analyze

    func analyzeEntry(_ text: String, existingTopics: [String] = []) async throws -> AnalysisResult {
        var request = URLRequest(url: analyzeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        var body: [String: Any] = ["text": text]
        if !existingTopics.isEmpty {
            body["existing_topics"] = existingTopics
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

    func cleanupTranscription(_ text: String) async throws -> String {
        let cleanupURL = URL(string: "https://api.thecombine.ai/himem/cleanup")!

        var request = URLRequest(url: cleanupURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard response.statusCode == 200 else {
            throw APIError.httpError(statusCode: response.statusCode)
        }

        return try JSONDecoder().decode(CleanupResult.self, from: data).text
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
