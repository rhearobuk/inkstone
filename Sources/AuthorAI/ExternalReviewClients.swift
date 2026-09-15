import Foundation

public enum ExternalReviewProvider: Sendable {
    case anthropic, google, mistral, xai, cohere, ollama
}

public struct ExternalReviewClient: EditorialReviewClient {
    private static let requestTimeout: TimeInterval = 60
    private let provider: ExternalReviewProvider
    private let apiKey: String
    private let modelID: String
    private let session: URLSession

    public init(provider: ExternalReviewProvider, apiKey: String, modelID: String, session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    public func review(_ request: ReviewRequest) async throws -> ReviewResponse {
        guard (provider == .ollama || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewClientError.unavailable("Choose a model and configure an API key in Preferences.")
        }
        let urlRequest = try makeURLRequest(for: request)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw ReviewClientError.unavailable("The selected model did not respond within \(Int(Self.requestTimeout)) seconds. Try again or choose another model.")
        }
        guard let http = response as? HTTPURLResponse else { throw ReviewClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ReviewClientError.service(http.statusCode) }
        return try decode(data)
    }

    private func makeURLRequest(for request: ReviewRequest) throws -> URLRequest {
        let prompt = EditorPromptBuilder.prompt(request)
        var url: URL
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]
        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": modelID, "max_tokens": 4096, "system": EditorPromptBuilder.contract,
                "messages": [["role": "user", "content": prompt]],
                "output_config": ["format": ["type": "json_schema", "schema": EditorPromptBuilder.EditorialReviewResponse.schema]]
            ]
        case .google:
            let encodedModel = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")!
            headers["x-goog-api-key"] = apiKey
            body = [
                "systemInstruction": ["parts": [["text": EditorPromptBuilder.contract]]],
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": ["responseMimeType": "application/json", "responseJsonSchema": EditorPromptBuilder.EditorialReviewResponse.schema]
            ]
        case .mistral:
            url = URL(string: "https://api.mistral.ai/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(apiKey)"
            body = chatBody(system: EditorPromptBuilder.contract, prompt: prompt)
        case .xai:
            url = URL(string: "https://api.x.ai/v1/responses")!
            headers["Authorization"] = "Bearer \(apiKey)"
            body = [
                "model": modelID, "store": false, "instructions": EditorPromptBuilder.contract, "input": prompt,
                "max_output_tokens": 1200,
                "text": ["format": ["type": "json_schema", "name": "editorial_review", "strict": true, "schema": EditorPromptBuilder.EditorialReviewResponse.schema]]
            ]
        case .cohere:
            url = URL(string: "https://api.cohere.com/v2/chat")!
            headers["Authorization"] = "Bearer \(apiKey)"
            headers["Accept"] = "application/json"
            headers["X-Client-Name"] = "Scribe"
            body = [
                "model": modelID,
                "messages": [
                    ["role": "system", "content": EditorPromptBuilder.contract],
                    ["role": "user", "content": prompt]
                ],
                "response_format": ["type": "json_object", "schema": EditorPromptBuilder.EditorialReviewResponse.schema]
            ]
        case .ollama:
            url = URL(string: "http://127.0.0.1:11434/api/chat")!
            body = [
                "model": modelID,
                "stream": false,
                "messages": [
                    ["role": "system", "content": EditorPromptBuilder.contract],
                    ["role": "user", "content": prompt]
                ],
                "format": EditorPromptBuilder.EditorialReviewResponse.schema
            ]
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func chatBody(system: String, prompt: String) -> [String: Any] {
        let responseFormat: [String: Any] = [
            "type": "json_schema",
            "json_schema": [
                "name": "editorial_review",
                "strict": true,
                "schema": EditorPromptBuilder.EditorialReviewResponse.schema
            ]
        ]
        return [
            "model": modelID,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            "response_format": responseFormat
        ]
    }

    private func decode(_ data: Data) throws -> ReviewResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReviewClientError.invalidResponse
        }
        let text: String?
        switch provider {
        case .anthropic:
            text = (root["content"] as? [[String: Any]])?
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .google:
            text = ((root["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                .flatMap { $0 as? [[String: Any]] }?
                .compactMap { $0["text"] as? String }
                .joined()
        case .mistral:
            text = ((root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        case .xai:
            text = (root["output"] as? [[String: Any]])?
                .filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .cohere:
            text = ((root["message"] as? [String: Any])?["content"] as? [[String: Any]])?
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        case .ollama:
            text = (root["message"] as? [String: Any])?["content"] as? String
        }
        guard let text, !text.isEmpty else { throw ReviewClientError.invalidResponse }
        return try EditorPromptBuilder.EditorialReviewResponse.decode(text)
    }
}
