import AuthorData
import SwiftUI
import UniformTypeIdentifiers

public struct AuthorWorkspaceView: View {
    @ObservedObject private var controller: WorkspaceController
    @EnvironmentObject private var aiSettings: AISettingsStore
    #if DEBUG
    @State private var showsEditor = ProcessInfo.processInfo.arguments.contains("--editor-preview")
    #else
    @State private var showsEditor = false
    #endif
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsNewProject = false
    @State private var showsImporter = false
    @State private var showsPreferences = false
    @State private var showsAppPreferences = false
    @State private var newProjectTitle = ""
    @State private var projectToDelete: UUID?

    public init(controller: WorkspaceController, editorInitiallyVisible: Bool = false) {
        self.controller = controller
        #if DEBUG
        let editorVisible = editorInitiallyVisible || ProcessInfo.processInfo.arguments.contains("--editor-preview")
        #else
        let editorVisible = editorInitiallyVisible
        #endif
        _showsEditor = State(initialValue: editorVisible)
        _columnVisibility = State(initialValue: editorVisible ? .detailOnly : .all)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            projectList
        } content: {
            binder
        } detail: {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    WorkspaceDetailView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsEditor && editorIsInline(width: geometry.size.width) {
                        Divider()
                        EditorPanelView(workspace: controller, editor: controller.editorialReviews, settings: aiSettings)
                            .frame(width: min(420, max(350, geometry.size.width * 0.43)))
                    }
                }
                .sheet(isPresented: Binding(get: { showsEditor && !editorIsInline(width: geometry.size.width) }, set: { if !$0 { showsEditor = false } })) {
                    VStack {
                        HStack { Spacer(); Button("Done") { showsEditor = false } }.padding()
                        EditorPanelView(workspace: controller, editor: controller.editorialReviews, settings: aiSettings)
                    }.frame(minWidth: 340, minHeight: 480)
                }
            }
            .toolbar {
                Button { showsEditor.toggle() } label: { Label("AI Editor", systemImage: "text.magnifyingglass") }
                    .help("Review manuscript and browse editorial history")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { if showsEditor { columnVisibility = .detailOnly } }
        .onChange(of: showsEditor) { visible in
            withAnimation(.easeInOut(duration: 0.2)) { columnVisibility = visible ? .detailOnly : .all }
        }
        .sheet(isPresented: $showsPreferences) {
            ProjectPreferencesView(controller: controller)
        }
        .sheet(isPresented: $showsAppPreferences) {
            AppPreferencesSheet(settings: aiSettings)
        }
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
        .alert("Delete Project?", isPresented: deleteProjectAlertBinding) {
            Button("Cancel", role: .cancel) { projectToDelete = nil }
            Button("Delete", role: .destructive) {
                guard let projectToDelete else { return }
                do {
                    try controller.deleteProject(projectToDelete)
                } catch {
                    controller.report(error)
                }
                self.projectToDelete = nil
            }
        } message: {
            Text("This permanently deletes \(projectTitleToDelete).")
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

    private func editorIsInline(width: CGFloat) -> Bool {
        #if os(macOS)
        true
        #else
        width >= 640
        #endif
    }

    private var projectList: some View {
        List(selection: Binding(
            get: { controller.selectedProjectID },
            set: { if let id = $0 { controller.selectProject(id) } }
        )) {
            ForEach(controller.projects, id: \.id) { project in
                Label {
                    Text(project.title)
                } icon: {
                    Image(systemName: controller.isProjectPinned(project.id) ? "pin.fill" : "book.closed")
                }
                    .tag(project.id)
                    .contextMenu {
                        Button {
                            controller.setProjectPinned(
                                project.id,
                                pinned: !controller.isProjectPinned(project.id)
                            )
                        } label: {
                            Label(
                                controller.isProjectPinned(project.id) ? "Unpin Project" : "Pin Project",
                                systemImage: controller.isProjectPinned(project.id) ? "pin.slash" : "pin"
                            )
                        }

                        Button {
                            controller.setProjectHidden(project.id, hidden: !controller.isProjectHidden(project.id))
                        } label: {
                            Label(
                                controller.isProjectHidden(project.id) ? "Show Project" : "Hide Project",
                                systemImage: controller.isProjectHidden(project.id) ? "eye" : "eye.slash"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            projectToDelete = project.id
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    }
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

                Menu {
                    Button(controller.showsHiddenProjects ? "Hide Hidden Projects" : "Show Hidden Projects") {
                        controller.showsHiddenProjects.toggle()
                        controller.refresh()
                    }
                } label: {
                    Label(
                        controller.showsHiddenProjects ? "Hide Hidden Projects" : "Show Hidden Projects",
                        systemImage: controller.showsHiddenProjects ? "eye.slash" : "eye"
                    )
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showsAppPreferences = true
                } label: {
                    Label("Preferences", systemImage: "gearshape.2")
                }
                .help("Application Preferences")
                #if !os(macOS)
                .keyboardShortcut(",", modifiers: .command)
                #endif
            }
        }
    }

    private var deleteProjectAlertBinding: Binding<Bool> {
        Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )
    }

    private var projectTitleToDelete: String {
        guard let projectToDelete,
              let project = controller.projects.first(where: { $0.id == projectToDelete }) else {
            return "this project"
        }
        return project.title
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
        VStack(spacing: 0) {
            filterBar
            Divider()
            List(selection: $controller.selection) {
                OutlineGroup(controller.displayedBinderItems, children: \.children) { item in
                    BinderRow(item: item, controller: controller)
                        .tag(item.selection)
                }
            }
        }
        .navigationTitle(controller.selectedProject?.title ?? "Binder")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsPreferences = true
                } label: {
                    Label("Project Preferences", systemImage: "gearshape")
                }
                .disabled(controller.selectedProject == nil)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All Statuses") { controller.statusFilter = nil }
                if !controller.sortedStatusDefinitions.isEmpty {
                    Divider()
                }
                ForEach(controller.sortedStatusDefinitions, id: \.sourceIdentifier) { status in
                    Button {
                        controller.statusFilter = status.sourceIdentifier
                    } label: {
                        if controller.statusFilter == status.sourceIdentifier {
                            Label(status.title, systemImage: "checkmark")
                        } else {
                            Text(status.title)
                        }
                    }
                }
            } label: {
                filterChip(
                    title: statusFilterTitle,
                    systemImage: "flag.fill",
                    tint: .secondary,
                    active: controller.statusFilter != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button("All Labels") { controller.labelFilter = nil }
                if !controller.sortedLabelDefinitions.isEmpty {
                    Divider()
                }
                ForEach(controller.sortedLabelDefinitions, id: \.sourceIdentifier) { label in
                    Button {
                        controller.labelFilter = label.sourceIdentifier
                    } label: {
                        if controller.labelFilter == label.sourceIdentifier {
                            Label(label.title, systemImage: "checkmark")
                        } else {
                            Text(label.title)
                        }
                    }
                }
            } label: {
                filterChip(
                    title: labelFilterTitle,
                    systemImage: "tag.fill",
                    tint: labelFilterTint,
                    active: controller.labelFilter != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if controller.statusFilter != nil || controller.labelFilter != nil {
                Button {
                    controller.statusFilter = nil
                    controller.labelFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filters")
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func filterChip(
        title: String,
        systemImage: String,
        tint: Color,
        active: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(active ? tint.opacity(0.18) : Color.secondary.opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(active ? tint.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var statusFilterTitle: String {
        guard let identifier = controller.statusFilter,
              let status = controller.sortedStatusDefinitions.first(where: { $0.sourceIdentifier == identifier }) else {
            return "Status"
        }
        return status.title
    }

    private var labelFilterTitle: String {
        guard let identifier = controller.labelFilter,
              let label = controller.sortedLabelDefinitions.first(where: { $0.sourceIdentifier == identifier }) else {
            return "Label"
        }
        return label.title
    }

    private var labelFilterTint: Color {
        guard let identifier = controller.labelFilter,
              let label = controller.sortedLabelDefinitions.first(where: { $0.sourceIdentifier == identifier }) else {
            return .secondary
        }
        return label.swiftUIColor ?? .secondary
    }
}

private struct RowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 28
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct BinderRow: View {
    let item: BinderItem
    @ObservedObject var controller: WorkspaceController
    @State private var dropPosition: DropPosition?
    @State private var rowHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .opacity(dropPosition == .before ? 1.0 : 0.0)
                .padding(.horizontal, 2)

            HStack(spacing: 6) {
                if let color = item.labelColor {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Label(item.title, systemImage: item.systemImage)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let sectionType = item.sectionTypeTitle {
                    Text(sectionType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let status = item.statusTitle {
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(dropPosition == .inside ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(dropPosition == .inside ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: RowHeightPreferenceKey.self, value: proxy.size.height)
                }
            )

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .opacity(dropPosition == .after ? 1.0 : 0.0)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onPreferenceChange(RowHeightPreferenceKey.self) { height in
            if height > 0 { rowHeight = height }
        }
        .modifier(BinderDragModifier(item: item))
        .modifier(BinderDropModifier(item: item, controller: controller, rowHeight: rowHeight, dropPosition: $dropPosition))
    }
}

private struct BinderDragModifier: ViewModifier {
    let item: BinderItem

    func body(content: Content) -> some View {
        if let documentID = item.documentID {
            content.draggable(documentID.uuidString) {
                HStack(spacing: 6) {
                    if let color = item.labelColor {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }
                    Label(item.title, systemImage: item.systemImage)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else {
            content
        }
    }
}

private struct BinderDropModifier: ViewModifier {
    let item: BinderItem
    @ObservedObject var controller: WorkspaceController
    let rowHeight: CGFloat
    @Binding var dropPosition: DropPosition?

    func body(content: Content) -> some View {
        if let targetID = item.documentID {
            content
                .onDrop(
                    of: [.plainText, .text],
                    delegate: BinderRowDropDelegate(
                        item: item,
                        targetID: targetID,
                        controller: controller,
                        rowHeight: rowHeight,
                        dropPosition: $dropPosition
                    )
                )
        } else {
            content
        }
    }
}

private struct BinderRowDropDelegate: DropDelegate {
    let item: BinderItem
    let targetID: UUID
    let controller: WorkspaceController
    let rowHeight: CGFloat
    @Binding var dropPosition: DropPosition?

    func dropEntered(info: DropInfo) {
        updatePosition(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePosition(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropPosition = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let pos = position(at: info.location)
        dropPosition = nil

        let providers = info.itemProviders(for: [.plainText, .text])
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: String.self) { string, _ in
            guard let string, let draggedID = UUID(uuidString: string) else { return }
            Task { @MainActor in
                do {
                    try controller.moveDocument(draggedID, relativeTo: targetID, position: pos)
                } catch {
                    controller.report(error)
                }
            }
        }
        return true
    }

    private func updatePosition(info: DropInfo) {
        let pos = position(at: info.location)
        if dropPosition != pos {
            dropPosition = pos
        }
    }

    private func position(at location: CGPoint) -> DropPosition {
        let height = rowHeight > 0 ? rowHeight : 28
        if item.isContainer {
            if location.y < height * 0.25 {
                return .before
            } else if location.y > height * 0.75 {
                return .after
            } else {
                return .inside
            }
        } else {
            if location.y < height * 0.5 {
                return .before
            } else {
                return .after
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
            case .gallery:
                GalleryView(controller: controller)
            case .galleryItem:
                GalleryItemEditor(controller: controller)
            case .narrative:
                NarrativeOverview(controller: controller)
            case .characterProfile:
                CharacterDossierView(controller: controller)
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
            .filter {
                category.contains(kind: $0.kind) &&
                    $0.characterProfile?.sourceDocument == nil
            }
            .sorted {
                $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
            }
    }
}

private struct SemanticEntityEditor: View {
    @ObservedObject var controller: WorkspaceController
    @State private var showsImageImporter = false

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
                Section("Images") {
                    let images = entity.galleryItems.sorted {
                        ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
                    }
                    if images.isEmpty {
                        Text("No photos attached.")
                            .foregroundStyle(.secondary)
                    } else {
                        LinkedGalleryItemsView(items: images) { item in
                            controller.selection = .galleryItem(item.id)
                        }
                    }
                    Button {
                        showsImageImporter = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entity.canonicalName)
            .fileImporter(
                isPresented: $showsImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                do {
                    _ = try controller.addGalleryImages(from: result.get(), relatedTo: entity)
                } catch {
                    controller.report(error)
                }
            }
        }
    }
}

private struct DocumentEditor: View {
    @ObservedObject var controller: WorkspaceController
    @State private var showsImageImporter = false

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

                let images = document.sourceGalleryItems.sorted {
                    ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
                }
                if !images.isEmpty {
                    LinkedGalleryItemsView(items: images) { item in
                        controller.selection = .galleryItem(item.id)
                    }
                    .frame(height: 170)
                    .padding(.horizontal)

                    Divider()
                }

                DocumentContentView(document: document, controller: controller)
            }
            .navigationTitle(document.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsImageImporter = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                }
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
            .fileImporter(
                isPresented: $showsImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                do {
                    _ = try controller.addGalleryImages(from: result.get(), to: document)
                } catch {
                    controller.report(error)
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
