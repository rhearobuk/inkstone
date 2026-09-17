import AuthorData
import AuthorAI
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct EditorPanelView: View {
    @ObservedObject var workspace: WorkspaceController
    @ObservedObject var editor: EditorialReviewController
    @ObservedObject var settings: AISettingsStore
    @State private var personaID: UUID?
    @State private var rootID: UUID?
    @State private var scope: EditorialScope = .document
    @State private var includeExcluded = false
    @State private var contextID: UUID?
    @State private var instructions = ""
    @State private var provider = AIProvider.appleIntelligence
    @AppStorage("AIEditor.openAIModel") private var modelID = "gpt-4.1-mini"
    @AppStorage("AIEditor.anthropicModel") private var anthropicModelID = "claude-sonnet-4-5"
    @AppStorage("AIEditor.googleModel") private var googleModelID = "gemini-2.5-flash"
    @AppStorage("AIEditor.mistralModel") private var mistralModelID = "mistral-large-latest"
    @AppStorage("AIEditor.xaiModel") private var xAIModelID = "grok-4.6"
    @AppStorage("AIEditor.cohereModel") private var cohereModelID = "command-a"
    @State private var openAIModels = ModelCatalog.openAI
    @State private var isLoadingOpenAIModels = false
    @State private var openAIModelError: String?
    @State private var showingOptions = false
    @State private var showingHistory = false
    @State private var filter = ""
    @State private var statusFilter = "all"
    @State private var showingPersonas = false
    @State private var showingSettings = false
    @State private var previousID: UUID?
    @State private var didLoadDefaults = false

    private var documents: [Document] {
        (workspace.selectedProject?.documents ?? []).filter {
            [DocumentKind.text.rawValue, DocumentKind.folder.rawValue, DocumentKind.draftFolder.rawValue].contains($0.kind)
            && $0.sourceCharacterProfiles.isEmpty
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var root: Document? { documents.first { $0.id == rootID } }
    private var persona: EditorPersona? { editor.personas.first { $0.id == personaID } }
    private var contextEntities: [SemanticEntity] {
        (workspace.selectedProject?.semanticEntities ?? []).sorted { $0.canonicalName < $1.canonicalName }
    }
    private var snapshots: Result<[ReviewInputSnapshot], Error> {
        Result {
            guard let root, let project = workspace.selectedProject else { throw ReviewScopeError.empty }
            var result = try ReviewScopeResolver.resolve(root: root, project: project, scope: scope, includeExcluded: includeExcluded)
            if let entry = contextEntities.first(where: { $0.id == contextID }) {
                let text = entry.summary ?? ""
                guard !text.isEmpty else { throw ReviewClientError.unavailable("This Story Bible entry has no summary to include.") }
                guard text.utf8.count + entry.canonicalName.utf8.count + 2 <= 1200 else {
                    throw ReviewClientError.unavailable("This Story Bible summary is too long for on-device reference context. Choose a shorter entry or leave context off.")
                }
                result.append(.init(documentID: entry.id, title: entry.canonicalName, path: "Story Bible", text: text, role: "context"))
            }
            return result
        }
    }
    private var unavailable: String? {
        switch provider {
        case .appleIntelligence:
            return settings.appleIntelligenceEnabled ? AppleIntelligenceReviewClient.unavailableReason : "Enable Apple Intelligence in app Preferences."
        case .openAI, .anthropic, .google, .mistral, .xai, .cohere:
            return !settings.hasAPIKey(for: provider) ? "Add your \(provider.displayName) key in Preferences." : activeModelID.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a model ID." : nil
        case .ollama:
            return settings.ollamaJuniorReviewerModel.trimmingCharacters(in: .whitespaces).isEmpty ||
                settings.ollamaSeniorReviewerModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Configure both Junior and Senior Reviewer models in Local AI settings."
                : nil
        }
    }
    private var projectReviews: [EditorialReview] {
        editor.reviews.filter { $0.project?.id == workspace.selectedProjectID }
    }
    private var selectedReview: EditorialReview? {
        projectReviews.first { $0.id == editor.selectedReviewID } ?? projectReviews.first
    }
    private var canReview: Bool {
        guard case .success = snapshots else { return false }
        return persona != nil && unavailable == nil && !editor.isRunning
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 1).id("conversation-top")
                        if let review = selectedReview {
                            ReviewDetailView(review: review, editor: editor, workspace: workspace, settings: settings) {
                                rootID = review.target?.id
                                scope = EditorialScope(rawValue: review.scope) ?? .document
                                personaID = review.persona?.id ?? editor.personas.first?.id
                                provider = AIProvider(rawValue: review.providerID) ?? .appleIntelligence
                                setModelID(review.modelID, for: provider)
                                previousID = review.id
                                showingOptions = true
                            }
                        } else {
                            welcome
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: editor.selectedReviewID) { _ in
                    withAnimation { reader.scrollTo("conversation-top", anchor: .top) }
                }
                .onChange(of: editor.isRunning) { running in
                    if !running { withAnimation { reader.scrollTo("conversation-top", anchor: .top) } }
                }
            }
            composer
        }
        .background(EditorStyle.background)
        .onAppear {
            if !didLoadDefaults { provider = settings.selectedProvider; didLoadDefaults = true }
            resetSelection()
        }
        .onChange(of: settings.selectedProvider) { value in if !editor.isRunning { provider = value } }
        .onChange(of: workspace.selectedProjectID) { _ in
            rootID = nil; contextID = nil; previousID = nil; resetSelection()
        }
        .onChange(of: workspace.selectedDocument?.id) { id in
            if !editor.isRunning && scope == .document { rootID = id; previousID = nil }
        }
        .sheet(isPresented: $showingPersonas) { EditorPersonaSettingsView(editor: editor) }
        .sheet(isPresented: $showingSettings) { AppPreferencesSheet(settings: settings) }
        .sheet(isPresented: $showingOptions) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Review options").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") { showingOptions = false }.keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("editor.optionsDone")
                }.padding(22)
                Divider()
                ScrollView { VStack(alignment: .leading, spacing: 18) { reviewForm }.padding(22) }
            }
            .frame(minWidth: 390, idealWidth: 440, minHeight: 480, idealHeight: 600)
            .background(EditorStyle.background)
        }
        .sheet(isPresented: $showingHistory) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Previous reviews").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") { showingHistory = false }
                }
                ScrollView { VStack(alignment: .leading, spacing: 12) { history } }
            }.padding(22).frame(minWidth: 370, idealWidth: 430, minHeight: 420)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            EditorAvatar(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your editor").font(.system(size: 21, weight: .semibold, design: .serif))
                Text(editor.isRunning
                    ? (editor.progress.isEmpty ? "Preparing your review…" : editor.progress)
                    : "A fresh perspective on your writing")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { showingHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").frame(width: 28, height: 28)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Previous reviews").accessibilityLabel("Previous reviews")
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let’s read it together.")
                .font(.system(size: 27, weight: .medium, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text("Send me a scene, a chapter, or your whole novel. I’ll share what’s working, what feels unclear, and where you might take another look.")
                .font(.system(size: 15)).lineSpacing(5).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "text.quote").foregroundStyle(EditorStyle.accent)
                Text("Your words stay untouched.").font(.system(size: 13))
            }.padding(.top, 4)
        }
        .padding(.top, 32).padding(.bottom, 28)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.isRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(editor.progress.isEmpty ? "Preparing your review…" : editor.progress)
                        .font(.system(size: 13))
                        .lineLimit(2)
                    Spacer()
                    Button("Stop") { editor.cancel() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if let error = editor.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("editor.error")
            }
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(EditorStyle.accent)
                Text(root?.title ?? "Choose something to review")
                    .accessibilityIdentifier("editor.target")
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Button("Change") { showingOptions = true }
                    .accessibilityIdentifier("editor.change")
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(EditorStyle.accent)
                    .disabled(editor.isRunning)
            }
            VStack(alignment: .leading, spacing: 12) {
                TextField("Anything you’d like me to focus on?", text: $instructions, axis: .vertical)
                    .accessibilityIdentifier("editor.instructions")
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(2...4)
                    .disabled(editor.isRunning)
                HStack {
                    Button { showingOptions = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            Text(EditorStyle.personaName(persona?.name ?? "Technical / Copy"))
                                .lineLimit(1)
                        }.font(.system(size: 12))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(editor.isRunning)
                        .help("Choose review options and editor persona")
                    Spacer(minLength: 4)
                    Button { run(); showingOptions = false } label: {
                        HStack(spacing: 7) {
                            Text("Review").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                        }.padding(.horizontal, 15).padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .background(canReview ? EditorStyle.buttonColor : Color.secondary.opacity(0.4), in: Capsule())
                    }.buttonStyle(.plain).disabled(!canReview)
                        .accessibilityIdentifier("editor.review")
                        .accessibilityLabel("Review with \(provider.displayName)")
                        .help("Review the selected text with \(provider.displayName)")
                }
            }
            .padding(14)
            .background(EditorStyle.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            HStack(spacing: 5) {
                Image(systemName: provider == .appleIntelligence ? "lock" : "cloud")
                Text(provider == .appleIntelligence ? "Apple Intelligence · On your device" : "Sent to \(provider.displayName) · API charges may apply")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if let reason = unavailable {
                HStack(alignment: .top, spacing: 8) {
                    Text(reason).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Set up") { showingSettings = true }.font(.system(size: 12))
                }.foregroundStyle(.secondary)
            } else if case .failure(let error) = snapshots, !editor.isRunning {
                Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(EditorStyle.background)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
    private func resetSelection() {
        if personaID == nil { personaID = editor.personas.first(where: { $0.presetKey == "technical" })?.id }
        if rootID == nil { rootID = workspace.selectedDocument?.id ?? documents.first(where: { $0.kind == DocumentKind.draftFolder.rawValue })?.id }
    }
    @ViewBuilder private var reviewForm: some View {
        Group {
            Picker("Editor", selection: $personaID) {
                Text("Choose persona").tag(UUID?.none)
                ForEach(editor.personas, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            Button("Customize personas…") { showingPersonas = true }
            Picker("AI service", selection: $provider) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("editor.provider")
            if provider == .appleIntelligence {
                Text("Apple Intelligence — On Device").font(.caption)
            } else if provider == .openAI {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Model", selection: $modelID) {
                        ForEach(openAIModels) { Text($0.name).tag($0.id) }
                        if !openAIModels.contains(where: { $0.id == modelID }) {
                            Text(modelID.isEmpty ? "Enter a model ID" : modelID).tag(modelID)
                        }
                    }
                    HStack(spacing: 6) {
                        if isLoadingOpenAIModels { ProgressView().controlSize(.small) }
                        Button("Refresh models") {
                            Task { await refreshOpenAIModels() }
                        }
                        .font(.caption)
                        .disabled(isLoadingOpenAIModels || !settings.hasAPIKey(for: .openAI))
                    }
                }
                DisclosureGroup("Use another model") { TextField("Model name", text: $modelID).textFieldStyle(.roundedBorder) }
                if let openAIModelError { Text(openAIModelError).font(.caption).foregroundStyle(.orange) }
                Text("Your selected text will be sent to OpenAI. API charges may apply.").font(.caption).foregroundStyle(.secondary)
                    .task(id: settings.apiKey(for: .openAI)) {
                        await refreshOpenAIModels()
                    }
            } else if provider == .ollama {
                LabeledContent("Junior Reviewer", value: settings.ollamaJuniorReviewerModel.isEmpty ? "Not configured" : settings.ollamaJuniorReviewerModel)
                LabeledContent("Senior Reviewer", value: settings.ollamaSeniorReviewerModel.isEmpty ? "Not configured" : settings.ollamaSeniorReviewerModel)
                Text("The Junior finds candidate issues; the Senior checks its evidence and returns the final review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Configure Local AI") { showingSettings = true }
                    .font(.caption)
            } else {
                TextField("Model", text: activeModelBinding)
                    .textFieldStyle(.roundedBorder)
                Text("Your selected text will be sent to \(provider.displayName). API charges may apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let unavailable { Text(unavailable).font(.caption).foregroundStyle(.orange) }
            Picker("Review", selection: $scope) { ForEach(EditorialScope.allCases, id: \.self) { Text(EditorStyle.scopeName($0)).tag($0) } }
            Picker("Manuscript", selection: $rootID) {
                Text("Choose a scene or folder").tag(UUID?.none)
                ForEach(documents, id: \.id) { Text($0.title).tag(Optional($0.id)) }
            }
            if let document = workspace.selectedDocument { Button("Use selected document") { rootID = document.id } }
            if scope != .document { Toggle("Include items excluded from compile", isOn: $includeExcluded) }
            Picker("Story Bible context", selection: $contextID) {
                Text("None").tag(UUID?.none)
                ForEach(contextEntities, id: \.id) { Text($0.canonicalName).tag(Optional($0.id)) }
            }

        }.disabled(editor.isRunning)
        switch snapshots {
        case .success(let inputs):
            let manuscript = inputs.filter { $0.role == "manuscript" }
            let words = manuscript.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            Text("\(manuscript.count) document\(manuscript.count == 1 ? "" : "s") · \(words) words").font(.subheadline.bold())
            DisclosureGroup("Included text") {
                ForEach(manuscript, id: \.documentID) { Text($0.path).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Non-text resources and character cards are excluded. Compile exclusions apply to chapter/novel scopes unless enabled above.").font(.caption).foregroundStyle(.secondary)
            }
            if previousID != nil { Text("Rerun uses current manuscript text and the settings above, with a link to the previous review.").font(.caption) }
            Button(provider == .openAI ? "Send to OpenAI & Review" : "Ask for a review") { run(); showingOptions = false }
                .buttonStyle(.borderedProminent).disabled(editor.isRunning || persona == nil || unavailable != nil)
        case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
        }
        Text("Mature fiction is reviewed as critique. A model may decline some material; any incomplete coverage is recorded.").font(.caption).foregroundStyle(.secondary)
    }
    private func run() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #elseif os(iOS) || os(visionOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        guard case .success(let inputs) = snapshots else { return }
        guard let project = workspace.selectedProject, let root, let persona else { return }
        let client: any EditorialReviewClient
        switch provider {
        case .appleIntelligence:
            client = AppleIntelligenceReviewClient()
        case .openAI:
            client = OpenAIReviewClient(apiKey: settings.apiKey(for: .openAI), modelID: activeModelID)
        case .anthropic:
            client = ExternalReviewClient(provider: .anthropic, apiKey: settings.apiKey(for: .anthropic), modelID: activeModelID)
        case .google:
            client = ExternalReviewClient(provider: .google, apiKey: settings.apiKey(for: .google), modelID: activeModelID)
        case .mistral:
            client = ExternalReviewClient(provider: .mistral, apiKey: settings.apiKey(for: .mistral), modelID: activeModelID)
        case .xai:
            client = ExternalReviewClient(provider: .xai, apiKey: settings.apiKey(for: .xai), modelID: activeModelID)
        case .cohere:
            client = ExternalReviewClient(provider: .cohere, apiKey: settings.apiKey(for: .cohere), modelID: activeModelID)
        case .ollama:
            client = OllamaTwoPhaseReviewClient(
                juniorModelID: settings.ollamaJuniorReviewerModel,
                seniorModelID: settings.ollamaSeniorReviewerModel
            )
        }
        editor.start(project: project, root: root, scope: scope, persona: persona, inputs: inputs,
                     providerID: provider.rawValue, modelID: provider == .appleIntelligence ? "apple-system-on-device" : activeModelID,
                     instructions: instructions, previousReviewID: previousID, client: client)
    }
    private var activeModelID: String {
        switch provider {
        case .openAI: modelID
        case .anthropic: anthropicModelID
        case .google: googleModelID
        case .mistral: mistralModelID
        case .xai: xAIModelID
        case .cohere: cohereModelID
        case .ollama: ""
        case .appleIntelligence: ""
        }
    }
    private var activeModelBinding: Binding<String> {
        switch provider {
        case .openAI: $modelID
        case .anthropic: $anthropicModelID
        case .google: $googleModelID
        case .mistral: $mistralModelID
        case .xai: $xAIModelID
        case .cohere: $cohereModelID
        case .ollama: .constant("")
        case .appleIntelligence: .constant("")
        }
    }
    private func setModelID(_ value: String, for provider: AIProvider) {
        switch provider {
        case .openAI: modelID = value
        case .anthropic: anthropicModelID = value
        case .google: googleModelID = value
        case .mistral: mistralModelID = value
        case .xai: xAIModelID = value
        case .cohere: cohereModelID = value
        case .ollama: break
        case .appleIntelligence: break
        }
    }
    private func refreshOpenAIModels() async {
        guard provider == .openAI, settings.hasAPIKey(for: .openAI), !isLoadingOpenAIModels else { return }
        isLoadingOpenAIModels = true
        defer { isLoadingOpenAIModels = false }
        do {
            let models = try await OpenAIModelCatalog.fetch(apiKey: settings.apiKey(for: .openAI))
            openAIModels = models
            openAIModelError = models.isEmpty
                ? "OpenAI returned no GPT models available to this account. Enter a model name manually."
                : nil
        } catch {
            openAIModelError = error.localizedDescription
        }
    }
    @ViewBuilder private var history: some View {
        TextField("Filter target, persona, model or date", text: $filter).textFieldStyle(.roundedBorder)
        Picker("Status", selection: $statusFilter) {
            Text("All").tag("all")
            ForEach(["completed", "partial", "failed", "refused", "cancelled", "interrupted"], id: \.self) { Text($0.capitalized).tag($0) }
        }
        let reviews = editor.reviews.filter {
            $0.project?.id == workspace.selectedProjectID && (statusFilter == "all" || $0.status == statusFilter)
            && (filter.isEmpty || "\($0.targetTitle) \($0.personaName) \($0.modelID) \($0.createdAt.formatted())".localizedCaseInsensitiveContains(filter))
        }
        if reviews.isEmpty { Text("No matching reviews yet.").foregroundStyle(.secondary) }
        ForEach(reviews, id: \.id) { review in
            Button { editor.selectedReviewID = review.id; showingHistory = false } label: {
                VStack(alignment: .leading) {
                    Text(review.targetTitle).font(.headline)
                    Text("\(review.personaName) · \(review.status)").font(.caption)
                    Text(review.createdAt.formatted()).font(.caption2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered)
        }
    }
}

private struct EditorPersonaSettingsView: View {
    @ObservedObject var editor: EditorialReviewController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var name = ""
    @State private var instructions = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Editor Personas").font(.title2); Spacer(); Button("Done") { dismiss() } }
            Picker("Start from", selection: $selected) {
                Text("New persona").tag(UUID?.none)
                ForEach(editor.personas, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }.onChange(of: selected) { id in
                let p = editor.personas.first { $0.id == id }; name = p?.name ?? ""; instructions = p?.instructions ?? ""
            }
            TextField("Name", text: $name)
            TextEditor(text: $instructions).frame(minHeight: 180).border(.secondary.opacity(0.3))
            Text("Describe editorial focus and depth. Built-in presets are duplicated when saved. All personas provide critique only.").font(.caption)
            Button("Save Persona") {
                editor.savePersona(name: name, instructions: instructions, existing: editor.personas.first { $0.id == selected })
            }.disabled(name.isEmpty || instructions.isEmpty)
            if let p = editor.personas.first(where: { $0.id == selected }), !p.isBuiltIn {
                Button("Delete Custom Persona", role: .destructive) { editor.deletePersona(p); selected = nil }
            }
            if let error = editor.errorMessage { Text(error).foregroundStyle(.red) }
        }.padding().frame(minWidth: 380, minHeight: 350)
    }
}
