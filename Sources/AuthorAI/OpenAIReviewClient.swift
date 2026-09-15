import Foundation

public struct OpenAIReviewClient: EditorialReviewClient, ProjectChatClient {
    private static let requestTimeout: TimeInterval = 60
    private let apiKey: String
    private let modelID: String
    private let session: URLSession

    public init(apiKey: String, modelID: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    public func review(_ request: ReviewRequest) async throws -> ReviewResponse {
        guard !apiKey.isEmpty, !modelID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ReviewClientError.unavailable("Choose an OpenAI model and configure an API key in Preferences.")
        }
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID, "store": false, "instructions": EditorPromptBuilder.contract,
            "input": EditorPromptBuilder.prompt(request), "max_output_tokens": 4096,
            "text": ["format": ["type": "json_schema", "name": "editorial_review", "strict": true, "schema": EditorPromptBuilder.EditorialReviewResponse.schema]]
        ])
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let error as URLError where error.code == .timedOut {
                throw ReviewClientError.unavailable("OpenAI did not respond within \(Int(Self.requestTimeout)) seconds. Try again or choose another model.")
            }
            guard let http = response as? HTTPURLResponse else { throw ReviewClientError.invalidResponse }
            if (http.statusCode == 429 || http.statusCode >= 500), attempt < 2 {
                let delay = min(max(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(attempt + 1) * 2, 1), 15)
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw ReviewClientError.service(http.statusCode) }
            return try Self.decode(data)
        }
        throw ReviewClientError.invalidResponse
    }

    public func respond(to request: ProjectChatRequest) async throws -> String {
        guard !apiKey.isEmpty, !modelID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ReviewClientError.unavailable("Choose an OpenAI model and configure an API key in Preferences.")
        }
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID, "store": false, "instructions": ProjectChatPromptBuilder.instructions,
            "input": ProjectChatPromptBuilder.prompt(request), "max_output_tokens": 2048
        ])
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ReviewClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ReviewClientError.service(http.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "completed",
              let output = root["output"] as? [[String: Any]] else {
            throw ReviewClientError.invalidResponse
        }
        let content = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        let text = content.filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined()
        if text.isEmpty, content.contains(where: { $0["type"] as? String == "refusal" }) {
            throw ReviewClientError.refused
        }
        guard !text.isEmpty else { throw ReviewClientError.invalidResponse }
        return text
    }

    public static func decode(_ data: Data) throws -> ReviewResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]] else { throw ReviewClientError.invalidResponse }
        let content = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        if content.contains(where: { $0["type"] as? String == "refusal" }) { throw ReviewClientError.refused }
        guard root["status"] as? String == "completed" else { throw ReviewClientError.invalidResponse }
        let text = content.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
        var result = try EditorPromptBuilder.EditorialReviewResponse.decode(text)
        let usage = root["usage"] as? [String: Any]
        result.inputTokens = usage?["input_tokens"] as? Int
        result.outputTokens = usage?["output_tokens"] as? Int
        result.resolvedModelID = root["model"] as? String
        return result
    }
}
