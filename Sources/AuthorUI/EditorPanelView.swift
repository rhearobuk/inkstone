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
    @State private var tab = "review"
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
        case .openAI:
            return !settings.hasAPIKey(for: .openAI) ? "Add your OpenAI key in Preferences." : modelID.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a model ID." : nil
        default: return "This provider's review adapter is not implemented yet. Choose Apple Intelligence or OpenAI."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Editor", systemImage: "text.magnifyingglass").font(.title2.bold())
                Spacer()
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }.help("AI preferences")
            }
            Text("Critique and recommendations. Your manuscript stays yours.").font(.caption).foregroundStyle(.secondary)
            Picker("View", selection: $tab) { Text("Review").tag("review"); Text("History").tag("history") }.pickerStyle(.segmented)
            if editor.isRunning {
                HStack { ProgressView().controlSize(.small); Text(editor.progress).font(.caption); Spacer(); Button("Cancel") { editor.cancel() } }
            }
            if let message = editor.errorMessage { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == "review" { reviewForm } else { history }
                    if let review = editor.reviews.first(where: { $0.id == editor.selectedReviewID && $0.project?.id == workspace.selectedProjectID }) {
                        Divider()
                        ReviewDetailView(review: review, editor: editor, workspace: workspace) {
                            rootID = review.target?.id; scope = EditorialScope(rawValue: review.scope) ?? .document
                            personaID = review.persona?.id ?? editor.personas.first?.id
                            provider = AIProvider(rawValue: review.providerID) ?? .appleIntelligence
                            if provider == .openAI { modelID = review.modelID }
                            previousID = review.id; tab = "review"
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear {
            if !didLoadDefaults { provider = settings.selectedProvider; didLoadDefaults = true }
            resetSelection()
        }
        .onChange(of: settings.selectedProvider) { value in if !editor.isRunning { provider = value } }
        .onChange(of: workspace.selectedProjectID) { _ in rootID = nil; contextID = nil; previousID = nil; resetSelection() }
        .sheet(isPresented: $showingPersonas) { EditorPersonaSettingsView(editor: editor) }
        .sheet(isPresented: $showingSettings) { AppPreferencesSheet(settings: settings) }
    }
    private func resetSelection() {
        if personaID == nil { personaID = editor.personas.first(where: { $0.presetKey == "technical" })?.id }
        if rootID == nil { rootID = workspace.selectedDocument?.id ?? documents.first(where: { $0.kind == DocumentKind.draftFolder.rawValue })?.id }
    }
    @ViewBuilder private var reviewForm: some View {
        Group {
            Picker("Persona", selection: $personaID) {
                Text("Choose persona").tag(UUID?.none)
                ForEach(editor.personas, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            Button("Customize personas…") { showingPersonas = true }
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
            }
            if provider == .appleIntelligence {
                Text("Apple Intelligence — On Device").font(.caption)
            } else if provider == .openAI {
                Picker("Model", selection: $modelID) {
                    ForEach(ModelCatalog.openAI) { Text($0.name).tag($0.id) }
                    if !ModelCatalog.openAI.contains(where: { $0.id == modelID }) { Text(modelID.isEmpty ? "Enter a model ID" : modelID).tag(modelID) }
                }
                TextField("OpenAI model ID", text: $modelID).textFieldStyle(.roundedBorder)
                Text("Requires a Responses API model with structured outputs. Selected text is sent to OpenAI; API charges may apply.").font(.caption).foregroundStyle(.secondary)
            }
            if let unavailable { Text(unavailable).font(.caption).foregroundStyle(.orange) }
            Picker("Scope", selection: $scope) { ForEach(EditorialScope.allCases, id: \.self) { Text($0.label).tag($0) } }
            Picker("Root / target", selection: $rootID) {
                Text("Choose manuscript target").tag(UUID?.none)
                ForEach(documents, id: \.id) { Text($0.title).tag(Optional($0.id)) }
            }
            if let document = workspace.selectedDocument { Button("Use selected document") { rootID = document.id } }
            if scope != .document { Toggle("Include items excluded from compile", isOn: $includeExcluded) }
            Picker("Story Bible context", selection: $contextID) {
                Text("None").tag(UUID?.none)
                ForEach(contextEntities, id: \.id) { Text($0.canonicalName).tag(Optional($0.id)) }
            }
            TextField("Additional editorial focus (optional)", text: $instructions, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
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
            Button(provider == .openAI ? "Send to OpenAI & Review" : "Run Review") { run() }
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
        let client: any EditorialReviewClient = provider == .appleIntelligence ? AppleIntelligenceReviewClient() : OpenAIReviewClient(apiKey: settings.apiKey(for: .openAI), modelID: modelID)
        editor.start(project: project, root: root, scope: scope, persona: persona, inputs: inputs,
                     providerID: provider.rawValue, modelID: provider == .appleIntelligence ? "apple-system-on-device" : modelID,
                     instructions: instructions, previousReviewID: previousID, client: client)
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
            Button { editor.selectedReviewID = review.id } label: {
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
