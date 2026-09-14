import Foundation

public struct EditorialModel: Identifiable, Sendable {
    public let id: String
    public let name: String
}
public enum ModelCatalog {
    /// Documented Responses/structured-output models. Account access is checked by the API.
    public static let openAI: [EditorialModel] = [
        .init(id: "gpt-4.1-mini", name: "GPT-4.1 mini"),
        .init(id: "gpt-4.1", name: "GPT-4.1")
    ]
}
