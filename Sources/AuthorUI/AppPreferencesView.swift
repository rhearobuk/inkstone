import AuthorAI
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Application-level preferences, distinct from `ProjectPreferencesView` (which configures a
/// single Scrivener-style project). This pane follows the modern macOS System Settings look:
/// a compact icon-labeled tab strip above a grouped, inset form.
public struct AppPreferencesView: View {
    @ObservedObject private var settings: AISettingsStore
    @ObservedObject private var authorInformation: AuthorInformationSettings

    public init(
        settings: AISettingsStore,
        authorInformation: AuthorInformationSettings = AuthorInformationSettings()
    ) {
        self.settings = settings
        self.authorInformation = authorInformation
    }

    public var body: some View {
        TabView {
            AuthorInformationPane(authorInformation: authorInformation)
                .tabItem {
                    Label("Author Information", systemImage: "person.text.rectangle")
                }
            AgentInformationPane(authorInformation: authorInformation)
                .tabItem {
                    Label("Agent Information", systemImage: "person.2")
                }
            AIProvidersPane(settings: settings)
                .tabItem {
                    Label("AI & Automation", systemImage: "sparkles")
                }
            LocalAISettingsPane(settings: settings)
                .tabItem {
                    Label("Local AI", systemImage: "desktopcomputer")
                }
        }

        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 560)
    }
}

private struct LocalAISettingsPane: View {
    @ObservedObject var settings: AISettingsStore

    var body: some View {
        Form {
            Section {
                TextField("Junior Reviewer", text: $settings.ollamaJuniorReviewerModel)
                    .textFieldStyle(.roundedBorder)
                Text("Uses a faster local Ollama model to identify candidate editorial issues and exact evidence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Senior Reviewer", text: $settings.ollamaSeniorReviewerModel)
                    .textFieldStyle(.roundedBorder)
                Text("Uses a more capable local Ollama model to check the Junior’s evidence, reject unsupported claims, and deliver the final notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ollama review team")
            } footer: {
                Text("Ollama must be running locally at 127.0.0.1:11434. The Senior Reviewer has the final say; unresolved evidence is presented as a minor editorial question, not a defect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AuthorInformationPane: View {
    @ObservedObject var authorInformation: AuthorInformationSettings

    var body: some View {
        Form {
            Section {
                TextField("Author's name", text: $authorInformation.name)
                TextField("Pen name", text: $authorInformation.penName)
            } header: {
                Text("Identity")
            } footer: {
                Text("Use your legal name for correspondence and your pen name when your work is published under a different byline.")
            }

            Section {
                TextField("Address line 1", text: $authorInformation.addressLine1)
                TextField("Address line 2", text: $authorInformation.addressLine2)
                TextField("City or locality", text: $authorInformation.locality)
                TextField("State, province, or region", text: $authorInformation.region)
                TextField("Postal or ZIP code", text: $authorInformation.postalCode)
                TextField("Country or region", text: $authorInformation.country)
            } header: {
                Text("Postal Address")
            } footer: {
                Text("Use the address format required by your country. State/province and postal-code fields are optional.")
            }

            Section {
                TextField("Email address", text: $authorInformation.email)
                TextField("Phone number", text: $authorInformation.phone)
                TextField("Website", text: $authorInformation.website)
            } header: {
                Text("Contact")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentInformationPane: View {
    @ObservedObject var authorInformation: AuthorInformationSettings

    var body: some View {
        Form {
            Section {
                TextField("Agent's name", text: $authorInformation.agentName)
                TextField("Agency", text: $authorInformation.agency)
            } header: {
                Text("Identity")
            }

            Section {
                TextField("Address line 1", text: $authorInformation.agentAddressLine1)
                TextField("Address line 2", text: $authorInformation.agentAddressLine2)
                TextField("City or locality", text: $authorInformation.agentLocality)
                TextField("State, province, or region", text: $authorInformation.agentRegion)
                TextField("Postal or ZIP code", text: $authorInformation.agentPostalCode)
                TextField("Country or region", text: $authorInformation.agentCountry)
            } header: {
                Text("Postal Address")
            } footer: {
                Text("Use the address format required by your agent's country. State/province and postal-code fields are optional.")
            }

            Section {
                TextField("Email address", text: $authorInformation.agentEmail)
                TextField("Phone number", text: $authorInformation.agentPhone)
                TextField("Website", text: $authorInformation.agentWebsite)
            } header: {
                Text("Contact")
            }
        }
        .formStyle(.grouped)
    }
}

/// A sheet-hosted variant of ``AppPreferencesView`` for platforms or contexts where the native
/// macOS `Settings` scene (Cmd-,) isn't the entry point, e.g. presenting from a toolbar button.
public struct AppPreferencesSheet: View {
    @ObservedObject private var settings: AISettingsStore
    @ObservedObject private var authorInformation: AuthorInformationSettings
    @Environment(\.dismiss) private var dismiss

    public init(
        settings: AISettingsStore,
        authorInformation: AuthorInformationSettings = AuthorInformationSettings()
    ) {
        self.settings = settings
        self.authorInformation = authorInformation
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preferences")
                        .font(.headline)
                    Text("Application-wide settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            AppPreferencesView(settings: settings, authorInformation: authorInformation)
        }
    }
}

// MARK: - AI Providers Pane

private struct AIProvidersPane: View {
    @ObservedObject var settings: AISettingsStore

    var body: some View {
        Form {
            if let error = settings.credentialError {
                Text(error)
                    .foregroundStyle(.red)
            }
            Section {
                Picker("Preferred Provider", selection: $settings.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.iconSystemName)
                            .tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text("Used for AI-assisted features such as editor feedback and consistency checking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Active Provider")
            }

            Section {
                AppleIntelligenceRow(settings: settings)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Runs entirely on-device. No API key, account, or network connection required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(AIProvider.allCases.filter(\.requiresAPIKey)) { provider in
                    ProviderKeyRow(provider: provider, settings: settings)
                }
            } header: {
                Text("API Keys")
            } footer: {
                Text("Keys are stored securely in the macOS Keychain and are never written to disk in plain text or synced outside this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppleIntelligenceRow: View {
    @ObservedObject var settings: AISettingsStore

    var body: some View {
        Toggle(isOn: $settings.appleIntelligenceEnabled) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AIProvider.appleIntelligence.displayName)
                    Text(AppleIntelligenceReviewClient.unavailableReason ?? "On-device model is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: AIProvider.appleIntelligence.iconSystemName)
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct ProviderKeyRow: View {
    let provider: AIProvider
    @ObservedObject var settings: AISettingsStore
    @State private var keyText: String = ""
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(provider.displayName, systemImage: provider.iconSystemName)
                    .font(.body)
                Spacer()
                statusBadge
            }
            Text(provider.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Group {
                    if isRevealed {
                        TextField(provider.apiKeyPlaceholder, text: $keyText)
                    } else {
                        SecureField(provider.apiKeyPlaceholder, text: $keyText)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)
                #if os(macOS) || os(iOS)
                .autocorrectionDisabled(true)
                #endif
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide key" : "Show key")
                .accessibilityLabel(isRevealed ? "Hide API key" : "Show API key")

                if !keyText.isEmpty {
                    Button(role: .destructive) {
                        keyText = ""
                        commit()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Remove key")
                }
            }
            if let url = provider.consoleURL {
                Link("Get an API key from \(provider.displayName) \u{2192}", destination: url)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .onAppear { keyText = settings.apiKey(for: provider) }
        .onChange(of: isFocused) { focused in
            if !focused { commit() }
        }
    }

    private var statusBadge: some View {
        Group {
            if settings.hasAPIKey(for: provider) {
                Label("Configured", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Label("Not configured", systemImage: "circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .help(settings.hasAPIKey(for: provider) ? "\(provider.displayName) API key configured" : "\(provider.displayName) API key not configured")
    }

    private func commit() {
        settings.setAPIKey(keyText, for: provider)
    }
}
