import AuthorAI
import AuthorData
import SwiftUI

enum AssistantMode: String, CaseIterable, Identifiable {
    case editor, chat

    var id: String { rawValue }
    var title: String { self == .editor ? "Editor" : "Project chat" }
}

enum ProjectChatContextDetail {
    case compact, full
}

@MainActor
enum ProjectChatContextBuilder {
    private static let compactMaximumBytes = 48_000
    private static let fullMaximumBytes = 100_000

    static func make(for project: WritingProject, selectedDocument: Document?,
                     selectedEntity: SemanticEntity?, selectedCard: StoryBibleCard?,
                     detail: ProjectChatContextDetail) throws -> String {
        let documents = project.documents
            .filter { !$0.isDeleted && $0.sourceCharacterProfiles.isEmpty }
            .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
        let binder = documents.map { document in
            let path = (document.ancestors.reversed().map(\.title) + [document.title]).joined(separator: " / ")
            var entry = "DOCUMENT: \(path)\nTYPE: \(document.kind)"
            if detail == .full,
               let synopsis = document.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines), !synopsis.isEmpty {
                entry += "\nSYNOPSIS: \(synopsis)"
            }
            return entry
        }.joined(separator: "\n\n")
        let storyBible = detail == .full ? project.semanticEntities
            .filter { !$0.isDeleted }
            .sorted { $0.canonicalName.localizedStandardCompare($1.canonicalName) == .orderedAscending }
            .compactMap { entity -> String? in
                guard let summary = entity.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
                    return nil
                }
                return "\(entity.kind): \(entity.canonicalName)\n\(summary)"
            }
                .joined(separator: "\n\n") : ""
        let selectedDocumentText = selectedDocument?.plainText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedEntityDetails = selectedEntity.map { entity in
                var details = "\(entity.kind): \(entity.canonicalName)"
                if let summary = entity.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    details += "\nSummary: \(summary)"
                }
                if let profile = entity.characterProfile {
                    let fields = [
                        ("Age", profile.ageText ?? profile.age?.stringValue),
                        ("Location", profile.location),
                        ("Physical description", profile.physicalDescription),
                        ("Biography", profile.biography)
                    ].compactMap { label, value in
                        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "\(label): \(value!)" : nil
                    }
                    if !fields.isEmpty { details += "\n" + fields.joined(separator: "\n") }
                }
                if let card = selectedCard {
                    let fields = [
                        card.details, card.uniqueFeatures, card.locationDescription, card.streetAddress,
                        card.sights, card.sounds, card.smells
                    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if !fields.isEmpty { details += "\n" + fields.joined(separator: "\n") }
                }
                return details
        } ?? ""
        let context = """
        PROJECT: \(project.title)

        STORY BIBLE:
        \(storyBible.isEmpty ? "Use the selected item below; broader Story Bible summaries are not included in this compact briefing." : storyBible)

        BINDER:
        \(binder.isEmpty ? "No documents are available." : binder)

        CURRENTLY SELECTED ITEM:
        \(selectedEntityDetails.isEmpty ? "No Story Bible item is selected." : selectedEntityDetails)

        CURRENTLY SELECTED DOCUMENT TEXT:
        \(selectedDocumentText.isEmpty ? "No manuscript document is selected." : selectedDocumentText)
        """
        let maximumBytes = detail == .compact ? compactMaximumBytes : fullMaximumBytes
        guard context.utf8.count <= maximumBytes else {
            throw ReviewClientError.contextExceeded
        }
        return context
    }
}

struct ProjectChatView: View {
    @ObservedObject var workspace: WorkspaceController
    @ObservedObject var settings: AISettingsStore
    @State private var messages: [ProjectChatMessage] = []
    @State private var draft = ""
    @State private var provider = AIProvider.appleIntelligence
    @State private var isRunning = false
    @State private var progressMessage = "Thinking…"
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @AppStorage("AIEditor.openAIModel") private var openAIModelID = "gpt-4.1-mini"
    @AppStorage("AIEditor.anthropicModel") private var anthropicModelID = "claude-sonnet-4-5"
    @AppStorage("AIEditor.googleModel") private var googleModelID = "gemini-2.5-flash"
    @AppStorage("AIEditor.mistralModel") private var mistralModelID = "mistral-large-latest"
    @AppStorage("AIEditor.xaiModel") private var xAIModelID = "grok-4.6"
    @AppStorage("AIEditor.cohereModel") private var cohereModelID = "command-a"

    private var unavailable: String? {
        switch provider {
        case .appleIntelligence:
            return settings.appleIntelligenceEnabled ? AppleIntelligenceReviewClient.unavailableReason : "Enable Apple Intelligence in app Preferences."
        case .ollama:
            return settings.ollamaSeniorReviewerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Configure a Senior Reviewer model in Local AI settings." : nil
        default:
            return settings.hasAPIKey(for: provider) ? nil : "Add your \(provider.displayName) key in Preferences."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 1).id("chat-top")
                        if messages.isEmpty { welcome }
                        ForEach(messages) { message in
                            messageView(message)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) {
                    withAnimation { reader.scrollTo("chat-top", anchor: .top) }
                }
            }
            composer
        }
        .background(EditorStyle.background)
        .onAppear { provider = settings.selectedProvider }
        .onChange(of: settings.selectedProvider) { _, value in
            if !isRunning { provider = value }
        }
        .onChange(of: workspace.selectedProjectID) {
            task?.cancel()
            messages = []
            errorMessage = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            EditorAvatar(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Project chat").font(.system(size: 21, weight: .semibold, design: .serif))
                Text(isRunning ? progressMessage : "Explore your project together")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("AI service", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }
            } label: {
                Label(provider.displayName, systemImage: provider.iconSystemName)
                    .font(.system(size: 12, weight: .medium))
            }
            .disabled(isRunning)
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Talk through your project.")
                .font(.system(size: 27, weight: .medium, design: .serif))
            Text("Ask about characters, plot, structure, themes, or possibilities. I’ll use the project’s Story Bible and binder, plus the item you have selected.")
                .font(.system(size: 15)).lineSpacing(5).foregroundStyle(.secondary)
        }
        .padding(.top, 32).padding(.bottom, 28)
    }

    @ViewBuilder
    private func messageView(_ message: ProjectChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(message.role == .user ? EditorStyle.accent : .secondary)
            messageText(message)
                .font(.system(size: 14))
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? EditorStyle.paper : Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func messageText(_ message: ProjectChatMessage) -> Text {
        guard message.role == .assistant else {
            return Text(message.content)
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let attributedString = try? AttributedString(
            markdown: message.content,
            options: options
        ) else {
            return Text(message.content)
        }
        return Text(attributedString)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage).font(.system(size: 12))
                    Spacer()
                    Button("Stop") { task?.cancel() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(.orange)
            }
            TextField("Ask about your project…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .disabled(isRunning || workspace.selectedProject == nil)
                .onSubmit { send() }
            HStack {
                Text("Project context and your selected item are included with each message.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { send() } label: {
                    Label("Send", systemImage: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(canSend ? EditorStyle.buttonColor : Color.secondary.opacity(0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            if let unavailable {
                Text(unavailable).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(EditorStyle.background)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private var canSend: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            workspace.selectedProject != nil && unavailable == nil
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let project = workspace.selectedProject, !isRunning, unavailable == nil else { return }
        do {
            let context = try ProjectChatContextBuilder.make(
                for: project,
                selectedDocument: workspace.selectedDocument,
                selectedEntity: workspace.selectedSemanticEntity,
                selectedCard: workspace.selectedStoryBibleCard,
                detail: provider == .appleIntelligence ? .compact : .full
            )
            let userMessage = ProjectChatMessage(role: .user, content: question)
            let requestMessages = messages + [userMessage]
            let conversationLimit = 60_000
            guard requestMessages.reduce(0, { $0 + $1.content.utf8.count }) <= conversationLimit else {
                errorMessage = "This conversation is too long to send safely. Start a new project chat."
                return
            }
            let client = makeClient()
            draft = ""
            errorMessage = nil
            messages = requestMessages
            isRunning = true
            progressMessage = provider == .ollama ? "Preparing project context for \(settings.ollamaSeniorReviewerModel)…" : "Preparing project context…"
            task = Task {
                do {
                    let response = try await client.respond(
                        to: .init(
                            projectContext: context,
                            messages: requestMessages,
                            progress: { status in
                                Task { @MainActor in
                                    progressMessage = status
                                }
                            }
                        ),
                        timeout: provider == .ollama ? 180 : 120
                    )
                    try Task.checkCancellation()
                    messages.append(.init(role: .assistant, content: response))
                } catch is CancellationError {
                    errorMessage = "Response cancelled."
                } catch {
                    errorMessage = error.localizedDescription
                }
                isRunning = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeClient() -> any ProjectChatClient {
        switch provider {
        case .appleIntelligence: return AppleIntelligenceProjectChatClient()
        case .openAI: return OpenAIReviewClient(apiKey: settings.apiKey(for: .openAI), modelID: openAIModelID)
        case .anthropic: return ExternalReviewClient(provider: .anthropic, apiKey: settings.apiKey(for: .anthropic), modelID: anthropicModelID)
        case .google: return ExternalReviewClient(provider: .google, apiKey: settings.apiKey(for: .google), modelID: googleModelID)
        case .mistral: return ExternalReviewClient(provider: .mistral, apiKey: settings.apiKey(for: .mistral), modelID: mistralModelID)
        case .xai: return ExternalReviewClient(provider: .xai, apiKey: settings.apiKey(for: .xai), modelID: xAIModelID)
        case .cohere: return ExternalReviewClient(provider: .cohere, apiKey: settings.apiKey(for: .cohere), modelID: cohereModelID)
        case .ollama:
            return OllamaProjectChatClient(modelID: settings.ollamaSeniorReviewerModel)
        }
    }
}
