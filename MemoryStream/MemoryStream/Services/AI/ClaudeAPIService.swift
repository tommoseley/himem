import Foundation

final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let analyzeURL = URL(string: "http://44.210.125.40/himem/analyze")!

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

    func analyzeEntry(_ text: String) async throws -> AnalysisResult {
        var request = URLRequest(url: analyzeURL)
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
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: response.statusCode, body: errorBody)
        }

        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    // MARK: - Cleanup

    func cleanupTranscription(_ text: String) async throws -> String {
        let cleanupURL = URL(string: "http://44.210.125.40/himem/cleanup")!

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
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: response.statusCode, body: errorBody)
        }

        return try JSONDecoder().decode(CleanupResult.self, from: data).text
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server."
            case .httpError(let code, let body):
                return "Server error \(code): \(body)"
            }
        }
    }
}
