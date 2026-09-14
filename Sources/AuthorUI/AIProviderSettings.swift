import Foundation
import Security

/// The large-language-model providers the app can call on behalf of the user for AI-assisted
/// features (editor feedback, consistency checking, and similar future tools). Each case other
/// than ``appleIntelligence`` requires the user to supply their own API key, which is stored in
/// the system Keychain rather than in `UserDefaults`.
public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI
    case anthropic
    case google
    case mistral
    case xai
    case cohere
    case appleIntelligence

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        case .mistral: return "Mistral AI"
        case .xai: return "xAI (Grok)"
        case .cohere: return "Cohere"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    public var summary: String {
        switch self {
        case .openAI: return "GPT models via the OpenAI API."
        case .anthropic: return "Claude models via the Anthropic API."
        case .google: return "Gemini models via Google AI Studio."
        case .mistral: return "Mistral and Mixtral models via La Plateforme."
        case .xai: return "Grok models via the xAI API."
        case .cohere: return "Command models via the Cohere API."
        case .appleIntelligence: return "On-device models built into macOS. No API key or network connection required."
        }
    }

    public var iconSystemName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "brain.head.profile"
        case .google: return "diamond"
        case .mistral: return "wind"
        case .xai: return "bolt.fill"
        case .cohere: return "cube.transparent"
        case .appleIntelligence: return "apple.logo"
        }
    }

    /// Apple Intelligence runs on-device and never needs a user-supplied credential.
    public var requiresAPIKey: Bool { self != .appleIntelligence }

    public var apiKeyPlaceholder: String {
        switch self {
        case .openAI: return "sk-…"
        case .anthropic: return "sk-ant-…"
        case .google: return "AIza…"
        case .mistral: return "API key"
        case .xai: return "xai-…"
        case .cohere: return "API key"
        case .appleIntelligence: return ""
        }
    }

    /// Where a user can generate a key for this provider, shown as a "Get an API key" link.
    public var consoleURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .google: return URL(string: "https://aistudio.google.com/apikey")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .xai: return URL(string: "https://console.x.ai")
        case .cohere: return URL(string: "https://dashboard.cohere.com/api-keys")
        case .appleIntelligence: return nil
        }
    }
}

/// Thin wrapper around Keychain Services for storing per-provider API keys. Keys never touch
/// `UserDefaults` or the app's SQLite store.
public final class AIKeychainStore: @unchecked Sendable {
    public static let shared = AIKeychainStore()

    private let service = "com.authorapp.aiProviderKeys"

    public init() {}

    public func apiKey(for provider: AIProvider) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setAPIKey(_ key: String?, for provider: AIProvider) throws {
        guard let key, !key.isEmpty else {
            try deleteAPIKey(for: provider)
            return
        }
        let data = Data(key.utf8)
        var query = baseQuery(for: provider)

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        } else {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            try check(SecItemAdd(query as CFDictionary, nil))
        }
    }

    public func deleteAPIKey(for provider: AIProvider) throws {
        let query = baseQuery(for: provider)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not save the API key to Keychain (status \(status))."])
        }
    }

    private func baseQuery(for provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

/// Observable store exposing the user's chosen AI provider and API keys to the rest of the app.
/// Later AI-assisted features (editor feedback, consistency checking, etc.) should read from
/// this store rather than accessing the Keychain directly.
@MainActor
public final class AISettingsStore: ObservableObject {
    @Published public private(set) var credentialError: String?
    @Published public var selectedProvider: AIProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider) }
    }

    @Published public var appleIntelligenceEnabled: Bool {
        didSet { defaults.set(appleIntelligenceEnabled, forKey: Keys.appleIntelligenceEnabled) }
    }

    @Published private var apiKeys: [AIProvider: String] = [:]

    private let defaults: UserDefaults
    private let keychain: AIKeychainStore

    private enum Keys {
        static let selectedProvider = "AISettings.selectedProvider"
        static let appleIntelligenceEnabled = "AISettings.appleIntelligenceEnabled"
    }

    public init(defaults: UserDefaults = .standard, keychain: AIKeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain

        if let rawValue = defaults.string(forKey: Keys.selectedProvider),
           let provider = AIProvider(rawValue: rawValue) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .appleIntelligence
        }

        self.appleIntelligenceEnabled = defaults.object(forKey: Keys.appleIntelligenceEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.appleIntelligenceEnabled)

        var loadedKeys: [AIProvider: String] = [:]
        for provider in AIProvider.allCases where provider.requiresAPIKey {
            if let key = keychain.apiKey(for: provider) {
                loadedKeys[provider] = key
            }
        }
        self.apiKeys = loadedKeys
    }

    public func apiKey(for provider: AIProvider) -> String {
        apiKeys[provider] ?? ""
    }

    public func hasAPIKey(for provider: AIProvider) -> Bool {
        !(apiKeys[provider] ?? "").isEmpty
    }

    public func setAPIKey(_ value: String, for provider: AIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain.setAPIKey(trimmed, for: provider)
            if trimmed.isEmpty { apiKeys.removeValue(forKey: provider) }
            else { apiKeys[provider] = trimmed }
            credentialError = nil
        } catch { credentialError = error.localizedDescription }

    }

    /// Whether the app is currently configured to make AI feature calls: either Apple
    /// Intelligence is enabled, or the selected provider has a stored API key.
    public var isConfigured: Bool {
        if selectedProvider == .appleIntelligence {
            return appleIntelligenceEnabled
        }
        return hasAPIKey(for: selectedProvider)
    }
}
