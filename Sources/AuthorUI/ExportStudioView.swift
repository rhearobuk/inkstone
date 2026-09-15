import AuthorData
import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

public enum ExportStudioFormat: String, CaseIterable, Identifiable {
    case manuscript
    case ebook
    case pdf

    public var id: Self { self }
    var outputFormat: ExportOutputFormat {
        switch self {
        case .manuscript: .docx
        case .ebook: .epub
        case .pdf: .pdf
        }
    }
    var displayName: String { rawValue.capitalized }
}

@MainActor
public final class ExportStudioModel: ObservableObject {
    @Published public private(set) var candidates: [ExportScopeCandidate]
    @Published public private(set) var selectedCandidateID: UUID
    @Published public private(set) var scope: ExportScope
    @Published public var format: ExportStudioFormat {
        didSet {
            guard format != oldValue else { return }
            selectDefaultTemplate()
            resolve()
        }
    }
    @Published public private(set) var selectedTemplateID = ""
    @Published public var pageSize: ExportPageSize = .a4 { didSet { resolve() } }
    @Published public var proofISBNFormat: BookFormat? { didSet { resolve() } }
    @Published public var includesExcludedDocuments = false { didSet { resolve() } }
    @Published public private(set) var publication: ExportPublication?
    @Published public private(set) var resolvedPublication: ResolvedPublication?
    #if canImport(AppKit)
    @Published public private(set) var previewPDF: Data?
    #endif
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var exportMessage: String?

    private let store: AuthorDataStore
    private let projectID: UUID
    private let templates: [ExportTemplate]
    private let scopeCandidates: (ExportScope) -> [ExportScopeCandidate]
    private var contactInformation: ExportContactInformation

    public init(
        store: AuthorDataStore,
        projectID: UUID,
        candidates: [ExportScopeCandidate],
        scopeCandidates: @escaping (ExportScope) -> [ExportScopeCandidate] = { _ in [] },
        contactInformation: ExportContactInformation = .init()
    ) {
        self.store = store
        self.projectID = projectID
        self.candidates = candidates
        self.selectedCandidateID = candidates.first?.id ?? UUID()
        self.scope = candidates.first?.scope ?? .book
        self.format = .manuscript
        self.templates = (try? ExportTemplateLoader.builtIns()) ?? []
        self.scopeCandidates = scopeCandidates
        self.contactInformation = contactInformation
        selectDefaultTemplate()
        resolve()
    }

    public var selectedCandidate: ExportScopeCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    public var availableTemplates: [ExportTemplate] {
        templates.filter { $0.supportedFormats.contains(format.outputFormat) }
    }

    public var selectedTemplate: ExportTemplate? {
        availableTemplates.first { $0.id == selectedTemplateID }
    }

    public var supportsPageSize: Bool {
        !(selectedTemplate?.supportedPageSizes.isEmpty ?? true)
    }

    public var wordCount: Int64 {
        publication?.documents.reduce(Int64(0)) { total, document in
            total + (document.wordCount > 0
                ? document.wordCount
                : document.prose.reduce(Int64(0)) { $0 + WordCountService.count(in: $1.plainText) })
        } ?? 0
    }

    public var availableProofISBNFormats: [BookFormat] {
        publication?.book?.metadata.isbns.map(\.format) ?? []
    }

    public func selectProofISBNFormat(_ format: BookFormat) {
        guard availableProofISBNFormats.contains(format) else { return }
        proofISBNFormat = format
    }

    public var excludedTitles: [String] {
        guard let candidate = selectedCandidate,
              let root = try? store.documents.fetch(id: candidate.id) else { return [] }
        var titles: [String] = []
        func visit(_ document: Document) {
            if document.isPublishingExcluded {
                titles.append(document.title)
                return
            }
            document.orderedChildren.forEach(visit)
        }
        visit(root)
        return titles
    }

    public func selectCandidate(_ id: UUID) {
        guard candidates.contains(where: { $0.id == id }) else { return }
        selectedCandidateID = id
        resolve()
    }

    public func selectScope(_ scope: ExportScope) {
        guard scope != self.scope else { return }
        let candidates = scopeCandidates(scope)
        guard let candidate = candidates.first else { return }
        self.scope = scope
        self.candidates = candidates
        selectedCandidateID = candidate.id
        resolve()
    }

    public func selectTemplate(_ id: String) {
        guard availableTemplates.contains(where: { $0.id == id }) else { return }
        selectedTemplateID = id
        resolve()
    }

    public func updateContactInformation(_ contactInformation: ExportContactInformation) {
        self.contactInformation = contactInformation
        resolve()
    }

    #if canImport(AppKit)
    public func exportManuscript() {
        guard let resolvedPublication, resolvedPublication.outputFormat == .docx else {
            exportMessage = "Choose Manuscript before exporting."
            return
        }
        do {
            let rendered = try ManuscriptRenderer.render(resolvedPublication)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "docx")!]
            panel.nameFieldStringValue = rendered.suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try ManuscriptRenderer.write(rendered, to: url)
                    self.exportMessage = "Saved \(rendered.suggestedFilename)."
                } catch {
                    self.exportMessage = error.localizedDescription
                }
            }
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    public func exportPDF() {
        guard let resolvedPublication, resolvedPublication.outputFormat == .pdf else {
            exportMessage = "Choose PDF before exporting."
            return
        }
        do {
            let rendered = try PDFRenderer.render(publication: resolvedPublication)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = rendered.suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    guard !FileManager.default.fileExists(atPath: url.path) else {
                        throw PDFRendererError.destinationExists(url)
                    }
                    try rendered.data.write(to: url, options: .withoutOverwriting)
                    self.exportMessage = "Saved \(rendered.suggestedFilename)."
                } catch {
                    self.exportMessage = error.localizedDescription
                }
            }
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    public func exportEbook() {
        guard let resolvedPublication, resolvedPublication.outputFormat == .epub else {
            exportMessage = "Choose Ebook before exporting."
            return
        }
        do {
            let rendered = try EbookRenderer.render(resolvedPublication)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "epub")!]
            panel.nameFieldStringValue = rendered.suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try EbookRenderer.write(rendered, to: url)
                    self.exportMessage = "Saved \(rendered.suggestedFilename)."
                } catch {
                    self.exportMessage = error.localizedDescription
                }
            }
        } catch {
            exportMessage = error.localizedDescription
        }
    }
    #endif

    private func selectDefaultTemplate() {
        let preferredTemplateID = switch format {
        case .manuscript: "com.unit37.scribe.template.manuscript.standard"
        case .ebook: "com.rhearobuk.scribe.template.ebook.novel"
        case .pdf: "com.rhearobuk.scribe.template.proof.reading"
        }
        if availableTemplates.contains(where: { $0.id == preferredTemplateID }) {
            selectedTemplateID = preferredTemplateID
            return
        }
        if !availableTemplates.contains(where: { $0.id == selectedTemplateID }) {
            selectedTemplateID = availableTemplates.first?.id ?? ""
        }
    }

    private func resolve() {
        guard let candidate = selectedCandidate, let template = selectedTemplate else {
            publication = nil
            resolvedPublication = nil
            errorMessage = "No compatible export template is available."
            return
        }
        do {
            let compiled = try ExportCompiler(store: store).compile(ExportRequest(
                projectID: projectID,
                rootDocumentID: candidate.id,
                scope: candidate.scope,
                includesExcludedDocuments: includesExcludedDocuments,
                contactInformation: contactInformation
            ))
            publication = compiled
            let pageSize = template.supportedPageSizes.contains(pageSize) ? pageSize : nil
            resolvedPublication = ExportTemplateResolver.resolve(
                publication: compiled,
                template: template,
                parameters: ExportTemplateParameters(
                    outputFormat: format.outputFormat,
                    pageSize: pageSize,
                    publicationISBNFormat: format == .pdf ? proofISBNFormat : nil
                )
            )
            #if canImport(AppKit)
            if template.supportedFormats.contains(.pdf) {
                let previewPublication = ExportTemplateResolver.resolve(
                    publication: compiled,
                    template: template,
                    parameters: ExportTemplateParameters(
                        outputFormat: .pdf,
                        pageSize: pageSize,
                        publicationISBNFormat: proofISBNFormat
                    )
                )
                previewPDF = try? PDFRenderer.render(publication: previewPublication).data
            } else {
                previewPDF = nil
            }
            #endif
            errorMessage = nil
        } catch {
            publication = nil
            resolvedPublication = nil
            #if canImport(AppKit)
            previewPDF = nil
            #endif
            errorMessage = error.localizedDescription
        }
    }
}

#if false
public struct ExportStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ExportStudioModel

    public init(controller: WorkspaceController) {
        _model = StateObject(wrappedValue: ExportStudioModel(
            store: controller.store,
            projectID: controller.selectedProjectID ?? UUID(),
            candidates: controller.exportScopeCandidates(),
            scopeCandidates: { controller.exportScopeCandidates(for: $0) }
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                controls.frame(width: 330)
                Divider()
                PublicationPreviewView(publication: model.resolvedPublication)
            }
            Divider()
            footer.padding()
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Studio").font(.title2.weight(.semibold))
                Picker("Export", selection: Binding(get: { model.selectedCandidateID }, set: model.selectCandidate)) {
                    ForEach(model.candidates) { candidate in Text(candidate.title).tag(candidate.id) }
                }
                Text("Exports this \(model.selectedCandidate?.scope.displayName.lowercased() ?? "item") and its publishable descendants.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Format", selection: $model.format) {
                    ForEach(ExportStudioFormat.allCases) { format in Text(format.displayName).tag(format) }
                }
                .pickerStyle(.segmented)
                if model.availableTemplates.count > 1 {
                    Picker("Template", selection: Binding(get: { model.selectedTemplateID }, set: model.selectTemplate)) {
                        ForEach(model.availableTemplates) { template in Text(template.displayName).tag(template.id) }
                    }
                } else if let template = model.selectedTemplate {
                    Text(template.displayName).font(.headline)
                    Text(template.description).font(.caption).foregroundStyle(.secondary)
                }
                if model.supportsPageSize {
                    Picker("Paper size", selection: $model.pageSize) {
                        Text("US Letter").tag(ExportPageSize.usLetter)
                        Text("A4").tag(ExportPageSize.a4)
                    }
                    if model.format == .pdf, !model.availableProofISBNFormats.isEmpty {
                        Text("Reading Proof ISBN").font(.headline)
                        HStack {
                            ForEach(model.availableProofISBNFormats) { format in
                                Button(format.displayName) { model.selectProofISBNFormat(format) }
                                    .buttonStyle(.bordered)
                                    .tint(model.proofISBNFormat == format ? .accentColor : .secondary)
                            }
                        }
                    }
                }
                Divider()
                Toggle("Include content marked \"Do Not Publish\"", isOn: $model.includesExcludedDocuments)
                if !model.includesExcludedDocuments && !model.excludedTitles.isEmpty {
                    DisclosureGroup("Excluded from export (\(model.excludedTitles.count))") {
                        ForEach(model.excludedTitles, id: \.self) { Text($0).font(.caption) }
                    }
                }
                Divider()
                Text("Publication Summary").font(.headline)
                Text("Scope: \(model.selectedCandidate?.title ?? "None")")
                Text("Word count: \(model.wordCount.formatted())")
                if let book = model.publication?.book {
                    Text("Title: \(book.title)")
                    if let author = book.metadata.author { Text("Author: \(author)") }
                    Text(book.metadata.covers.contains(where: { $0.kind == .front }) ? "Cover: Available" : "Cover: Not set")
                }
            }
            .padding()
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if let readiness = model.resolvedPublication?.readiness {
                readinessLabel(readiness)
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Export…") {}
                .disabled(!isReady)
        }
    }

    @ViewBuilder private func readinessLabel(_ readiness: ExportReadiness) -> some View {
        switch readiness {
        case .ready(let warnings) where warnings.isEmpty:
            Label("Ready to Export", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .ready(let warnings):
            Label("Ready to Export — \(warnings.count) recommendations", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .blocked(let tags):
            Label("Cannot Export — \(tags.joined(separator: ", "))", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case .templateInvalid:
            Label("Cannot Export — invalid template", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var isReady: Bool {
        if case .ready = model.resolvedPublication?.readiness { return true }
        return false
    }
}

private struct ExportStudioPreview: View {
    let publication: ResolvedPublication?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let publication {
                    ForEach(publication.frontMatter.prefix(3)) { component in
                        Text(component.previewText)
                            .font(component.id == "title.book" ? .title2 : .body)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if let item = publication.narrative.first {
                        if item.rule.displaysTitle {
                            Text(item.title)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        ForEach(item.prose.indices, id: \.self) { index in
                            Text(item.prose[index].plainText)
                                .lineSpacing(publication.outputFormat == .docx ? 8 : 4)
                        }
                    }
                } else {
                    Text("Select a narrative item to preview its export.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }
}

private extension ResolvedTemplateComponent {
    var previewText: String {
        switch value {
        case .text(let text), .lateBound(let text): text
        case .integer(let number): number.formatted()
        case .date(let date): date.formatted(date: .long, time: .omitted)
        case .asset: "Cover"
        }
    }
}

private struct PublicationPreviewView: View {
    let publication: ResolvedPublication?

    var body: some View {
        ScrollView {
            if let publication {
                LazyVStack(spacing: 28) {
                    Text("Publication Preview").font(.title2.weight(.semibold))
                    ForEach(publication.frontMatter) { component in
                        PreviewSurface(isEbook: publication.outputFormat == .epub) {
                            Text(component.value.previewText).font(.title2).frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    ForEach(publication.narrative) { item in
                        PreviewSurface(isEbook: publication.outputFormat == .epub) {
                            VStack(alignment: .leading, spacing: 12) {
                                if item.rule.displaysTitle { Text(item.title).font(.title2).frame(maxWidth: .infinity, alignment: .center) }
                                else if item.rule.insertsSceneBreakBefore { Text(item.rule.sceneBreakMarker ?? "* * *").frame(maxWidth: .infinity, alignment: .center) }
                                ForEach(item.prose.indices, id: \.self) { index in
                                    Text(item.prose[index].plainText).lineSpacing(5)
                                }
                            }
                        }
                    }
                }
                .padding(32)
            } else {
                Text("Select a narrative item to preview its export.").padding()
            }
        }
        .background(Color.secondary.opacity(0.10))
    }
}

private struct PreviewSurface<Content: View>: View {
    let isEbook: Bool
    let content: Content

    init(isEbook: Bool, @ViewBuilder content: () -> Content) {
        self.isEbook = isEbook
        self.content = content()
    }

    var body: some View {
        content.padding(44).frame(maxWidth: isEbook ? 680 : 520, minHeight: isEbook ? 0 : 620, alignment: .topLeading)
            .background(isEbook ? Color.clear : Color.white, in: RoundedRectangle(cornerRadius: 4))
    }
}

private extension TemplateValue {
    var previewText: String {
        switch self {
        case .text(let value), .lateBound(let value): value
        case .integer(let value): value.formatted()
        case .date(let value): value.formatted(date: .long, time: .omitted)
        case .asset: "Cover"
        }
    }
}
#endif

public struct ExportStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authorInformation: AuthorInformationSettings
    @StateObject private var model: ExportStudioModel

    public init(controller: WorkspaceController) {
        _model = StateObject(wrappedValue: ExportStudioModel(
            store: controller.store,
            projectID: controller.selectedProjectID ?? UUID(),
            candidates: controller.exportScopeCandidates(),
            scopeCandidates: { controller.exportScopeCandidates(for: $0) }
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Studio").font(.title)
                    Text("Word count: \(model.wordCount.formatted())")
                    HStack {
                        ForEach([ExportScope.book, .section, .chapter, .scene], id: \.self) { scope in
                            Button(scope.displayName) { model.selectScope(scope) }
                                .buttonStyle(.bordered)
                                .tint(scope == model.scope ? .accentColor : .secondary)
                        }
                    }
                    HStack {
                        ForEach(ExportStudioFormat.allCases) { format in
                            Button(format.displayName) { model.format = format }
                                .buttonStyle(.bordered)
                                .tint(format == model.format ? .accentColor : .secondary)
                        }
                    }
                    HStack {
                        ForEach(model.availableTemplates) { template in
                            Button(template.displayName) { model.selectTemplate(template.id) }
                                .buttonStyle(.bordered)
                                .tint(template.id == model.selectedTemplateID ? .accentColor : .secondary)
                        }
                    }
                    if model.supportsPageSize {
                        HStack {
                            Button("A4") { model.pageSize = .a4 }
                                .buttonStyle(.bordered)
                                .tint(model.pageSize == .a4 ? .accentColor : .secondary)
                            Button("US Letter") { model.pageSize = .usLetter }
                                .buttonStyle(.bordered)
                                .tint(model.pageSize == .usLetter ? .accentColor : .secondary)
                        }

                    }
                    Toggle("Include content marked \"Do Not Publish\"", isOn: $model.includesExcludedDocuments)
                    Divider()
                    Text("Choose \(model.selectedCandidate?.scope.displayName ?? "Scope")").font(.headline)
                    ForEach(model.candidates) { candidate in
                        Button(candidate.title) {
                            model.selectCandidate(candidate.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(candidate.id == model.selectedCandidateID ? .accentColor : .secondary)
                    }
                    if let publication = model.resolvedPublication {
                        Divider()
                        Text(readinessTitle(publication.readiness)).font(.headline)
                    }
                }
                .padding()
                }
                .frame(width: 380)
                Divider()
                ExportRendererPreview(
                    publication: model.resolvedPublication,
                    pdfData: model.previewPDF
                )
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                #if canImport(AppKit)
                Button("Export…") { export() }
                    .disabled(!isReady)
                #else
                Button("Export…") {}
                    .disabled(true)
                #endif
            }
            .padding()
        }
        .frame(minWidth: 1_000, minHeight: 680)
        .onAppear {
            model.updateContactInformation(authorInformation.exportContactInformation)
        }
        .onReceive(authorInformation.objectWillChange) { _ in
            DispatchQueue.main.async {
                model.updateContactInformation(authorInformation.exportContactInformation)
            }
        }
    }

    private func readinessTitle(_ readiness: ExportReadiness) -> String {
        switch readiness {
        case .ready(let warnings): warnings.isEmpty ? "Ready to Export" : "Ready to Export — \(warnings.count) recommendations"
        case .blocked: "Cannot Export"
        case .templateInvalid: "Cannot Export — invalid template"
        }
    }

    #if canImport(AppKit)
    private func export() {
        switch model.format {
        case .manuscript:
            model.exportManuscript()
        case .pdf:
            model.exportPDF()
        case .ebook:
            model.exportEbook()
        }
    }
    #endif

    private var isReady: Bool {
        if case .ready = model.resolvedPublication?.readiness { return true }
        return false
    }
}

#if canImport(AppKit)
private struct ExportRendererPreview: NSViewRepresentable {
    let publication: ResolvedPublication?
    let pdfData: Data?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard let pdfData, let document = PDFDocument(data: pdfData) else {
            view.document = nil
            return
        }
        view.document = document
        view.autoScales = true
    }
}
#else
private struct ExportRendererPreview: View {
    let publication: ResolvedPublication?
    let pdfData: Data?

    var body: some View {
        Text("Publication Preview")
    }
}
#endif
