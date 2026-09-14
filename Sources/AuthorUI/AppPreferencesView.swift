import SwiftUI
import AuthorAI
#if canImport(AppKit)
import AppKit
#endif

/// Application-level preferences, distinct from `ProjectPreferencesView` (which configures a
/// single Scrivener-style project). This pane follows the modern macOS System Settings look:
/// a compact icon-labeled tab strip above a grouped, inset form.
public struct AppPreferencesView: View {
    @ObservedObject private var settings: AISettingsStore

    public init(settings: AISettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        TabView {
            AIProvidersPane(settings: settings)
                .tabItem {
                    Label("AI & Automation", systemImage: "sparkles")
                }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 560)
    }
}

/// A sheet-hosted variant of ``AppPreferencesView`` for platforms or contexts where the native
/// macOS `Settings` scene (Cmd-,) isn't the entry point, e.g. presenting from a toolbar button.
public struct AppPreferencesSheet: View {
    @ObservedObject private var settings: AISettingsStore
    @Environment(\.dismiss) private var dismiss

    public init(settings: AISettingsStore) {
        self.settings = settings
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
            AppPreferencesView(settings: settings)
        }
    }
}

// MARK: - AI Providers Pane

private struct AIProvidersPane: View {
    @ObservedObject var settings: AISettingsStore

    var body: some View {
        Form {
            if let error = settings.credentialError { Text(error).foregroundStyle(.red) }
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
    }

    private func commit() {
        settings.setAPIKey(keyText, for: provider)
    }
}
