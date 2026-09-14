import AuthorData
import SwiftUI
import UniformTypeIdentifiers

public struct AuthorWorkspaceView: View {
    @ObservedObject private var controller: WorkspaceController
    @State private var showsNewProject = false
    @State private var showsImporter = false
    @State private var newProjectTitle = ""

    public init(controller: WorkspaceController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationSplitView {
            projectList
        } content: {
            binder
        } detail: {
            WorkspaceDetailView(controller: controller)
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            importProject(result)
        }
        .alert("New Project", isPresented: $showsNewProject) {
            TextField("Project title", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { newProjectTitle = "" }
            Button("Create") {
                let title = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                do {
                    _ = try controller.createProject(title: title)
                } catch {
                    controller.report(error)
                }
                newProjectTitle = ""
            }
        }
        .alert(
            "Import Complete",
            isPresented: Binding(
                get: { controller.importSummary != nil },
                set: { if !$0 { controller.clearImportSummary() } }
            )
        ) {
            Button("OK") { controller.clearImportSummary() }
        } message: {
            Text(controller.importSummary ?? "")
        }
        .overlay(alignment: .bottom) {
            if controller.isImporting {
                ProgressView("Importing Scrivener project…")
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            } else if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }

    private var projectList: some View {
        List(selection: Binding(
            get: { controller.selectedProjectID },
            set: { if let id = $0 { controller.selectProject(id) } }
        )) {
            ForEach(controller.projects, id: \.id) { project in
                Label(project.title, systemImage: "book.closed")
                    .tag(project.id)
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsImporter = true
                } label: {
                    Label("Import Scrivener Project", systemImage: "square.and.arrow.down")
                }
                .disabled(controller.isImporting)

                Button {
                    showsNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
    }

    private func importProject(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            _ = try controller.importScrivenerProject(from: url)
        } catch {
            controller.report(error)
        }
    }

    private var binder: some View {
        List(selection: $controller.selection) {
            OutlineGroup(controller.binderItems, children: \.children) { item in
                BinderRow(item: item, controller: controller)
                    .tag(item.selection)
            }
        }
        .navigationTitle(controller.selectedProject?.title ?? "Binder")
    }
}

private struct BinderRow: View {
    let item: BinderItem
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        Label(item.title, systemImage: item.systemImage)
            .draggable(item.documentID?.uuidString ?? "")
            .dropDestination(for: String.self) { identifiers, _ in
                guard let identifier = identifiers.first,
                      let draggedID = UUID(uuidString: identifier),
                      let targetID = item.documentID else {
                    return false
                }
                do {
                    try controller.moveDocument(draggedID, onto: targetID)
                    return true
                } catch {
                    controller.report(error)
                    return false
                }
            }
    }
}

private struct WorkspaceDetailView: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        Group {
            switch controller.selection {
            case .projectDefinition:
                ProjectDefinitionView(controller: controller)
            case .storyBible:
                StoryBibleOverview(controller: controller)
            case .storyBibleCategory(_, let category):
                StoryBibleCategoryView(category: category, controller: controller)
            case .narrative:
                NarrativeOverview(controller: controller)
            case .semanticEntity:
                SemanticEntityEditor(controller: controller)
            case .document:
                DocumentEditor(controller: controller)
            case nil:
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.largeTitle)
                    Text("Select an Item")
                        .font(.title2)
                    Text("Choose a project and binder item to begin.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NarrativeOverview: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
            Text("Narrative")
                .font(.title2)
            Text("Select a script, chapter, or scene in the binder.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(controller.selectedProject?.title ?? "Narrative")
    }
}

private struct ProjectDefinitionView: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        if let project = controller.selectedProject {
            Form {
                Section("Identity") {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { project.title },
                            set: { controller.updateProject(title: $0, author: project.author) }
                        )
                    )
                    TextField(
                        "Author",
                        text: Binding(
                            get: { project.author ?? "" },
                            set: { controller.updateProject(title: project.title, author: $0) }
                        )
                    )
                    LabeledContent("Format", value: project.sourceFormat)
                }
                Section("Project") {
                    LabeledContent("Created", value: project.createdAt.formatted())
                    LabeledContent("Modified", value: project.modifiedAt.formatted())
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Project Definition")
        }
    }
}

private struct StoryBibleOverview: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        List(StoryBibleCategory.allCases) { category in
            Button {
                guard let projectID = controller.selectedProjectID else { return }
                controller.selection = .storyBibleCategory(projectID: projectID, category: category)
            } label: {
                Label(category.rawValue, systemImage: category.systemImage)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Story Bible")
    }
}

private struct StoryBibleCategoryView: View {
    let category: StoryBibleCategory
    @ObservedObject var controller: WorkspaceController
    @State private var showsNewEntry = false
    @State private var entryName = ""

    var body: some View {
        List {
            ForEach(entities, id: \.id) { entity in
                Button(entity.canonicalName) {
                    controller.selection = .semanticEntity(entity.id)
                }
                .buttonStyle(.plain)
            }
            ForEach(controller.storyBibleDocuments(in: category), id: \.id) { document in
                Button {
                    controller.selection = .document(document.id)
                } label: {
                    Label(document.title, systemImage: "folder")
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(category.rawValue)
        .toolbar {
            Button {
                showsNewEntry = true
            } label: {
                Label("Add Entry", systemImage: "plus")
            }
        }
        .alert("New \(category.rawValue) Entry", isPresented: $showsNewEntry) {
            TextField("Name", text: $entryName)
            Button("Cancel", role: .cancel) { entryName = "" }
            Button("Create") {
                let name = entryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                do {
                    _ = try controller.addStoryBibleEntry(named: name, category: category)
                } catch {
                    controller.report(error)
                }
                entryName = ""
            }
        }
    }

    private var entities: [SemanticEntity] {
        guard let project = controller.selectedProject else { return [] }
        return project.semanticEntities
            .filter { category.contains(kind: $0.kind) }
            .sorted {
                $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
            }
    }
}

private struct SemanticEntityEditor: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        if let entity = controller.selectedSemanticEntity {
            Form {
                TextField(
                    "Name",
                    text: Binding(
                        get: { entity.canonicalName },
                        set: { controller.updateSemanticEntity(name: $0, summary: entity.summary) }
                    )
                )
                TextField(
                    "Summary",
                    text: Binding(
                        get: { entity.summary ?? "" },
                        set: { controller.updateSemanticEntity(name: entity.canonicalName, summary: $0) }
                    ),
                    axis: .vertical
                )
                LabeledContent("Ontology kind", value: entity.kind)
                LabeledContent("Source", value: entity.source)
            }
            .formStyle(.grouped)
            .navigationTitle(entity.canonicalName)
        }
    }
}

private struct DocumentEditor: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        if let document = controller.selectedDocument {
            VStack(spacing: 0) {
                TextField(
                    "Title",
                    text: Binding(
                        get: { document.title },
                        set: {
                            controller.updateDocument(
                                title: $0,
                                synopsis: document.synopsis,
                                plainText: document.plainText
                            )
                        }
                    )
                )
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .padding()

                Divider()

                DocumentContentView(document: document, controller: controller)
            }
            .navigationTitle(document.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Scene") {
                            addDocument(
                                title: "New Scene",
                                kind: .text,
                                parentID: insertionParentID(for: document)
                            )
                        }
                        Button("New Folder") {
                            addDocument(
                                title: "New Folder",
                                kind: .folder,
                                parentID: insertionParentID(for: document)
                            )
                        }
                    } label: {
                        Label("Add Binder Item", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func insertionParentID(for document: Document) -> UUID? {
        let isContainer = document.kind == DocumentKind.folder.rawValue ||
            document.kind == DocumentKind.draftFolder.rawValue
        return isContainer ? document.id : document.parent?.id
    }

    private func addDocument(title: String, kind: DocumentKind, parentID: UUID?) {
        do {
            _ = try controller.addDocument(title: title, kind: kind, parentID: parentID)
        } catch {
            controller.report(error)
        }
    }
}
