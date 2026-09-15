import Foundation

public struct EditorialModel: Identifiable, Sendable {
    public let id: String
    public let name: String
}
public enum ModelCatalog {
    /// Available while the account-specific catalog is loading or unavailable.
    public static let openAI: [EditorialModel] = [
        .init(id: "gpt-4.1-mini", name: "GPT-4.1 mini"),
        .init(id: "gpt-4.1", name: "GPT-4.1")
    ]
}

public enum OpenAIModelCatalogError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidResponse
    case service(Int)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .invalidResponse: "OpenAI returned an invalid model list."
        case .service(let status): "OpenAI could not load your available models (HTTP \(status))."
        }
    }
}

public enum OpenAIModelCatalog {
    public static func fetch(apiKey: String, session: URLSession = .shared) async throws -> [EditorialModel] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIModelCatalogError.unavailable("Add your OpenAI key in Preferences to load available models.")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIModelCatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OpenAIModelCatalogError.service(http.statusCode) }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> [EditorialModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["data"] as? [[String: Any]] else {
            throw OpenAIModelCatalogError.invalidResponse
        }
        let modelIDs = records.compactMap { record in record["id"] as? String }
        let ids = Set(modelIDs.filter { $0.lowercased().hasPrefix("gpt-") })
        return ids
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { EditorialModel(id: $0, name: $0) }
    }
}
