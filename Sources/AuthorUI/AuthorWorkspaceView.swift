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
    @State private var showsNewProject = false
    @State private var showsImporter = false
    @State private var showsPreferences = false
    @State private var showsAppPreferences = false
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
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    WorkspaceDetailView(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsEditor && editorIsInline(width: geometry.size.width) {
                        Divider()
                        EditorPanelView(
                            workspace: controller,
                            editor: controller.editorialReviews,
                            settings: aiSettings
                        )
                        .frame(width: min(420, max(350, geometry.size.width * 0.43)))
                    }
                }
                .sheet(
                    isPresented: Binding(
                        get: { showsEditor && !editorIsInline(width: geometry.size.width) },
                        set: { if !$0 { showsEditor = false } }
                    )
                ) {
                    VStack {
                        HStack {
                            Spacer()
                            Button("Done") { showsEditor = false }
                        }
                        .padding()
                        EditorPanelView(
                            workspace: controller,
                            editor: controller.editorialReviews,
                            settings: aiSettings
                        )
                    }
                    .frame(minWidth: 340, minHeight: 480)
                }
            }
            .toolbar {
                Button { showsEditor.toggle() } label: {
                    Label("AI Editor", systemImage: "text.magnifyingglass")
                }
                .help("Review manuscript and browse editorial history")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showsPreferences) {
            ProjectPreferencesView(controller: controller)
        }
        .sheet(isPresented: $showsAppPreferences) {
            AppPreferencesSheet(settings: aiSettings)
        }
        .sheet(isPresented: $showsImporter) {
            ScrivenerImportView(controller: controller)
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
        .alert("Move Project to Trash?", isPresented: Binding(
            get: { controller.projectToTrash != nil },
            set: { if !$0 { controller.projectToTrash = nil } }
        )) {
            Button("Cancel", role: .cancel) { controller.projectToTrash = nil }
            Button("Move to Trash", role: .destructive) {
                if let id = controller.projectToTrash {
                    controller.trashProject(id)
                    controller.projectToTrash = nil
                }
            }
        } message: {
            if let id = controller.projectToTrash {
                Text("Are you sure you want to move '\(controller.projectTitle(for: id))' to the Trash? You can restore it later.")
            }
        }
        .alert("Delete Project Permanently?", isPresented: Binding(
            get: { controller.projectToDeletePermanently != nil },
            set: { if !$0 { controller.projectToDeletePermanently = nil } }
        )) {
            Button("Cancel", role: .cancel) { controller.projectToDeletePermanently = nil }
            Button("Delete Permanently", role: .destructive) {
                if let id = controller.projectToDeletePermanently {
                    do {
                        try controller.deleteProjectPermanently(id)
                    } catch {
                        controller.report(error)
                    }
                    controller.projectToDeletePermanently = nil
                }
            }
        } message: {
            if let id = controller.projectToDeletePermanently {
                Text("This permanently deletes '\(controller.projectTitle(for: id))'. This action cannot be undone.")
            }
        }
        .alert("Empty Project Trash?", isPresented: $controller.showsEmptyProjectTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                do {
                    try controller.emptyProjectTrash()
                } catch {
                    controller.report(error)
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete all projects in the trash? This action cannot be undone.")
        }
        .alert("Move to Trash?", isPresented: Binding(
            get: { controller.documentToTrash != nil },
            set: { if !$0 { controller.documentToTrash = nil } }
        )) {
            Button("Cancel", role: .cancel) { controller.documentToTrash = nil }
            Button("Move to Trash", role: .destructive) {
                if let id = controller.documentToTrash {
                    controller.trashDocument(id)
                    controller.documentToTrash = nil
                }
            }
        } message: {
            if let id = controller.documentToTrash {
                Text("Are you sure you want to move '\(controller.documentTitle(for: id))' to the Trash? You can restore it to its exact location later.")
            }
        }
        .alert("Delete Permanently?", isPresented: Binding(
            get: { controller.documentToDeletePermanently != nil },
            set: { if !$0 { controller.documentToDeletePermanently = nil } }
        )) {
            Button("Cancel", role: .cancel) { controller.documentToDeletePermanently = nil }
            Button("Delete Permanently", role: .destructive) {
                if let id = controller.documentToDeletePermanently {
                    do {
                        try controller.deleteDocumentPermanently(id)
                    } catch {
                        controller.report(error)
                    }
                    controller.documentToDeletePermanently = nil
                }
            }
        } message: {
            if let id = controller.documentToDeletePermanently {
                Text("This permanently deletes '\(controller.documentTitle(for: id))'. This action cannot be undone.")
            }
        }
        .alert("Empty Trash?", isPresented: $controller.showsEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                if let projectID = controller.selectedProjectID {
                    do {
                        try controller.emptyTrash(for: projectID)
                    } catch {
                        controller.report(error)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete all items in the Trash? This action cannot be undone.")
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
            let activeProjects = controller.projects.filter { !controller.isProjectTrashed($0.id) }
            let trashedProjects = controller.trashedProjects

            Section("Projects") {
                ForEach(activeProjects, id: \.id) { project in
                    Label {
                        HStack {
                            Text(project.title)
                            if controller.isProjectHidden(project.id) {
                                Spacer()
                                Image(systemName: "eye.slash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                            controller.projectToTrash = project.id
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                }
            }

            if controller.showsTrashedProjects || !trashedProjects.isEmpty {
                Section("Trashed Projects") {
                    ForEach(trashedProjects, id: \.id) { project in
                        Label {
                            Text(project.title)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .tag(project.id)
                        .contextMenu {
                            Button {
                                controller.restoreProject(project.id)
                            } label: {
                                Label("Restore Project", systemImage: "arrow.uturn.backward")
                            }

                            Divider()

                            Button(role: .destructive) {
                                controller.projectToDeletePermanently = project.id
                            } label: {
                                Label("Delete Permanently", systemImage: "trash.slash")
                            }
                        }
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
                    Button(controller.showsTrashedProjects ? "Hide Trashed Projects" : "Show Trashed Projects") {
                        controller.showsTrashedProjects.toggle()
                        controller.refresh()
                    }
                    if !controller.trashedProjects.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            controller.showsEmptyProjectTrashAlert = true
                        } label: {
                            Label("Empty Project Trash...", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Project Options", systemImage: "ellipsis.circle")
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
                Menu {
                    Button(controller.showsHiddenDocuments ? "Hide Hidden Scenes" : "Show Hidden Scenes") {
                        controller.showsHiddenDocuments.toggle()
                        controller.refresh()
                    }
                    if let project = controller.selectedProject, !controller.trashedDocuments(in: project).isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            controller.showsEmptyTrashAlert = true
                        } label: {
                            Label("Empty Trash...", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Binder Options", systemImage: "ellipsis.circle")
                }

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
        .contextMenu {
            contextMenuContent
        }
        .onPreferenceChange(RowHeightPreferenceKey.self) { height in
            if height > 0 { rowHeight = height }
        }
        .modifier(BinderDragModifier(item: item))
        .modifier(BinderDropModifier(item: item, controller: controller, rowHeight: rowHeight, dropPosition: $dropPosition))
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if item.kind == .trash {
            let hasTrashed = controller.selectedProject.map { !controller.trashedDocuments(in: $0).isEmpty } ?? false
            Button(role: .destructive) {
                controller.showsEmptyTrashAlert = true
            } label: {
                Label("Empty Trash...", systemImage: "trash")
            }
            .disabled(!hasTrashed)
        } else if item.isTrashed, let documentID = item.documentID {
            Button {
                controller.restoreDocument(documentID)
            } label: {
                Label("Restore to Original Location", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button(role: .destructive) {
                controller.documentToDeletePermanently = documentID
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        } else if let documentID = item.documentID {
            Button {
                controller.setDocumentHidden(documentID, hidden: !item.isHidden)
            } label: {
                Label(
                    item.isHidden ? "Show Scene" : "Hide Scene",
                    systemImage: item.isHidden ? "eye" : "eye.slash"
                )
            }

            Divider()

            Button(role: .destructive) {
                controller.documentToTrash = documentID
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
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
            case .trash:
                TrashOverview(controller: controller)
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

private struct TrashOverview: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        VStack(spacing: 0) {
            let trashedDocs = controller.selectedProject.map { controller.trashedDocuments(in: $0) } ?? []

            if trashedDocs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Trash is Empty")
                        .font(.title2)
                    Text("Deleted scenes and folders are moved here before being permanently removed.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(trashedDocs.count) item\(trashedDocs.count == 1 ? "" : "s") in Trash")
                                    .font(.headline)
                                Text("Items can be restored to their original location or permanently deleted.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                controller.showsEmptyTrashAlert = true
                            } label: {
                                Label("Empty Trash", systemImage: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Deleted Items") {
                        ForEach(trashedDocs, id: \.id) { doc in
                            HStack(spacing: 12) {
                                Image(systemName: doc.kind == DocumentKind.folder.rawValue || doc.kind == DocumentKind.draftFolder.rawValue ? "folder" : "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title)
                                        .font(.body)
                                    if let parent = doc.parent {
                                        Text("Original location: \(parent.title)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Original location: Narrative Root")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Restore") {
                                    controller.restoreDocument(doc.id)
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    controller.documentToDeletePermanently = doc.id
                                } label: {
                                    Image(systemName: "trash.slash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete Permanently")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trash")
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
            let isTrashed = controller.isDocumentTrashed(document.id)
            VStack(spacing: 0) {
                if isTrashed {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                        Text("This item is in the Trash.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore Item") {
                            controller.restoreDocument(document.id)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .destructive) {
                            controller.documentToDeletePermanently = document.id
                        } label: {
                            Text("Delete Permanently")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))

                    Divider()
                }

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
