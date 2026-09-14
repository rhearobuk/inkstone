import AuthorData
import Combine
import CoreData
import Foundation

public enum WorkspaceSelection: Hashable, Sendable {
    case projectDefinition(UUID)
    case storyBible(UUID)
    case storyBibleCategory(projectID: UUID, category: StoryBibleCategory)
    case semanticEntity(UUID)
    case document(UUID)
}

public enum StoryBibleCategory: String, CaseIterable, Identifiable, Sendable {
    case people = "People"
    case places = "Places"
    case artifacts = "Artifacts"
    case events = "Events, Conflicts & Timelines"
    case worldbuilding = "Worldbuilding"

    public var id: Self { self }

    public var systemImage: String {
        switch self {
        case .people: "person.2"
        case .places: "map"
        case .artifacts: "shippingbox"
        case .events: "point.3.connected.trianglepath.dotted"
        case .worldbuilding: "globe"
        }
    }

    public func contains(kind: String) -> Bool {
        switch self {
        case .people:
            kind == SemanticEntityKind.character.rawValue ||
                kind == SemanticEntityKind.organization.rawValue
        case .places:
            kind == SemanticEntityKind.location.rawValue
        case .artifacts:
            kind == SemanticEntityKind.object.rawValue
        case .events:
            kind == SemanticEntityKind.event.rawValue ||
                kind == SemanticEntityKind.relationship.rawValue ||
                kind == SemanticEntityKind.timeline.rawValue
        case .worldbuilding:
            kind == SemanticEntityKind.concept.rawValue ||
                kind == SemanticEntityKind.theme.rawValue ||
                kind == SemanticEntityKind.other.rawValue
        }
    }

    public var defaultEntityKind: SemanticEntityKind {
        switch self {
        case .people: .character
        case .places: .location
        case .artifacts: .object
        case .events: .event
        case .worldbuilding: .concept
        }
    }
}

public struct BinderItem: Identifiable {
    public enum Kind {
        case projectDefinition
        case storyBible
        case storyBibleCategory(StoryBibleCategory)
        case semanticEntity
        case document
    }

    public let id: String
    public let title: String
    public let systemImage: String
    public let selection: WorkspaceSelection
    public let kind: Kind
    public let documentID: UUID?
    public var children: [BinderItem]?

    public init(
        id: String,
        title: String,
        systemImage: String,
        selection: WorkspaceSelection,
        kind: Kind,
        documentID: UUID? = nil,
        children: [BinderItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.selection = selection
        self.kind = kind
        self.documentID = documentID
        self.children = children
    }
}

public enum WorkspaceError: LocalizedError {
    case missingProject(UUID)
    case missingDocument(UUID)
    case invalidMove

    public var errorDescription: String? {
        switch self {
        case .missingProject(let id): "Project \(id) no longer exists."
        case .missingDocument(let id): "Document \(id) no longer exists."
        case .invalidMove: "A binder item cannot be moved inside itself or one of its descendants."
        }
    }
}

@MainActor
public final class WorkspaceController: ObservableObject {
    public let store: AuthorDataStore

    @Published public private(set) var projects: [WritingProject] = []
    @Published public var selectedProjectID: UUID?
    @Published public var selection: WorkspaceSelection?
    @Published public private(set) var binderItems: [BinderItem] = []
    @Published public private(set) var lastError: String?

    public init(store: AuthorDataStore) {
        self.store = store
        refresh()
    }

    public var selectedProject: WritingProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    public var selectedDocument: Document? {
        guard case .document(let id) = selection else { return nil }
        return try? store.documents.fetch(id: id)
    }

    public var selectedSemanticEntity: SemanticEntity? {
        guard case .semanticEntity(let id) = selection else { return nil }
        return try? store.semanticEntities.fetch(id: id)
    }

    public func refresh() {
        do {
            projects = try store.projects.fetchAll(
                sortedBy: [NSSortDescriptor(key: "modifiedAt", ascending: false)]
            )
            if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = projects.first?.id
            }
            rebuildBinder()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    public func createProject(title: String, author: String? = nil) throws -> WritingProject {
        let now = Date()
        let projectID = UUID()
        let project = store.projects.create(id: projectID) {
            $0.title = title
            $0.author = author
            $0.sourceIdentifier = "native.project.\(projectID.uuidString)"
            $0.sourceFormat = "native"
            $0.createdAt = now
            $0.modifiedAt = now
        }
        let narrative = store.documents.create {
            $0.sourceIdentifier = "native.narrative.\($0.id.uuidString)"
            $0.title = "Narrative"
            $0.kind = DocumentKind.draftFolder.rawValue
            $0.orderIndex = 0
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
        }
        let script = store.documents.create {
            $0.sourceIdentifier = "native.script.\($0.id.uuidString)"
            $0.title = "Untitled Novel"
            $0.kind = DocumentKind.folder.rawValue
            $0.orderIndex = 0
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
            $0.parent = narrative
        }
        store.documents.create {
            $0.sourceIdentifier = "native.scene.\($0.id.uuidString)"
            $0.title = "Opening Scene"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.createdAt = now
            $0.modifiedAt = now
            $0.plainText = ""
            $0.project = project
            $0.parent = script
        }
        try store.save()
        selectedProjectID = projectID
        selection = .projectDefinition(projectID)
        refresh()
        return project
    }

    @discardableResult
    public func addDocument(
        title: String,
        kind: DocumentKind,
        parentID: UUID?
    ) throws -> Document {
        guard let project = selectedProject else {
            throw WorkspaceError.missingProject(selectedProjectID ?? UUID())
        }
        let parent = try parentID.map { id in
            guard let document = try store.documents.fetch(id: id) else {
                throw WorkspaceError.missingDocument(id)
            }
            return document
        }
        let siblings = documents(in: project).filter { $0.parent?.id == parent?.id }
        let now = Date()
        let document = store.documents.create {
            $0.sourceIdentifier = "native.document.\($0.id.uuidString)"
            $0.title = title
            $0.kind = kind.rawValue
            $0.orderIndex = (siblings.map(\.orderIndex).max() ?? -1) + 1
            $0.createdAt = now
            $0.modifiedAt = now
            $0.plainText = kind == .text ? "" : nil
            $0.project = project
            $0.parent = parent
        }
        project.modifiedAt = now
        try store.save()
        selection = .document(document.id)
        refresh()
        return document
    }

    @discardableResult
    public func addStoryBibleEntry(
        named name: String,
        category: StoryBibleCategory
    ) throws -> SemanticEntity {
        guard let project = selectedProject else {
            throw WorkspaceError.missingProject(selectedProjectID ?? UUID())
        }
        let now = Date()
        let entity = store.semanticEntities.create {
            $0.canonicalName = name
            $0.kind = category.defaultEntityKind.rawValue
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
        }
        project.modifiedAt = now
        try store.save()
        selection = .semanticEntity(entity.id)
        refresh()
        return entity
    }

    public func updateProject(title: String, author: String?) {
        guard let project = selectedProject else { return }
        project.title = title
        project.author = author?.nilIfBlank
        project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func updateDocument(title: String, synopsis: String?, plainText: String?) {
        guard let document = selectedDocument else { return }
        document.title = title
        document.synopsis = synopsis?.nilIfBlank
        document.plainText = plainText
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
    }

    public func updateSemanticEntity(name: String, summary: String?) {
        guard let entity = selectedSemanticEntity else { return }
        entity.canonicalName = name
        entity.summary = summary?.nilIfBlank
        entity.modifiedAt = Date()
        entity.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func moveDocument(_ documentID: UUID, onto targetID: UUID) throws {
        guard let document = try store.documents.fetch(id: documentID) else {
            throw WorkspaceError.missingDocument(documentID)
        }
        guard let target = try store.documents.fetch(id: targetID) else {
            throw WorkspaceError.missingDocument(targetID)
        }
        guard document.project.id == target.project.id,
              document.id != target.id,
              !isDescendant(target, of: document) else {
            throw WorkspaceError.invalidMove
        }

        let oldParent = document.parent
        let targetIsContainer = target.kind == DocumentKind.folder.rawValue ||
            target.kind == DocumentKind.draftFolder.rawValue
        let newParent = targetIsContainer ? target : target.parent
        let insertionIndex = targetIsContainer ? Int.max : Int(target.orderIndex)

        document.parent = newParent
        let newSiblings = documents(in: document.project)
            .filter { $0.parent?.id == newParent?.id && $0.id != document.id }
            .sorted(by: documentOrder)
        let safeIndex = min(insertionIndex, newSiblings.count)
        var ordered = newSiblings
        ordered.insert(document, at: safeIndex)
        reindex(ordered)

        if oldParent?.id != newParent?.id {
            reindex(
                documents(in: document.project)
                    .filter { $0.parent?.id == oldParent?.id && $0.id != document.id }
                    .sorted(by: documentOrder)
            )
        }
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        try store.save()
        refresh()
    }

    public func selectProject(_ projectID: UUID) {
        selectedProjectID = projectID
        selection = .projectDefinition(projectID)
        rebuildBinder()
    }

    public func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    private func saveAndRefresh(rebuild: Bool = true) {
        do {
            try store.save()
            if rebuild { refresh() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func rebuildBinder() {
        guard let project = selectedProject else {
            binderItems = []
            selection = nil
            return
        }

        let entities = project.semanticEntities.sorted {
            $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
        }
        let categories = StoryBibleCategory.allCases.map { category in
            BinderItem(
                id: "story-bible.\(category.id)",
                title: category.rawValue,
                systemImage: category.systemImage,
                selection: .storyBibleCategory(projectID: project.id, category: category),
                kind: .storyBibleCategory(category),
                children: entities.filter { category.contains(kind: $0.kind) }.map { entity in
                    BinderItem(
                        id: entity.id.uuidString,
                        title: entity.canonicalName,
                        systemImage: category.systemImage,
                        selection: .semanticEntity(entity.id),
                        kind: .semanticEntity
                    )
                }
            )
        }
        let documents = documents(in: project)
        let roots = documents.filter { $0.parent == nil }.sorted(by: documentOrder)

        binderItems = [
            BinderItem(
                id: "project-definition",
                title: "Project Definition",
                systemImage: "doc.text.magnifyingglass",
                selection: .projectDefinition(project.id),
                kind: .projectDefinition
            ),
            BinderItem(
                id: "story-bible",
                title: "Story Bible",
                systemImage: "books.vertical",
                selection: .storyBible(project.id),
                kind: .storyBible,
                children: categories
            )
        ] + roots.map(makeDocumentItem)
    }

    private func makeDocumentItem(_ document: Document) -> BinderItem {
        BinderItem(
            id: document.id.uuidString,
            title: document.title,
            systemImage: documentSystemImage(document),
            selection: .document(document.id),
            kind: .document,
            documentID: document.id,
            children: document.orderedChildren.isEmpty
                ? nil
                : document.orderedChildren.map(makeDocumentItem)
        )
    }

    private func documents(in project: WritingProject) -> [Document] {
        project.documents.map { $0 }
    }

    private func isDescendant(_ candidate: Document, of ancestor: Document) -> Bool {
        var parent = candidate.parent
        while let current = parent {
            if current.id == ancestor.id { return true }
            parent = current.parent
        }
        return false
    }

    private func reindex(_ documents: [Document]) {
        for (index, document) in documents.enumerated() {
            document.orderIndex = Int64(index)
        }
    }

    private func documentOrder(_ lhs: Document, _ rhs: Document) -> Bool {
        (lhs.orderIndex, lhs.id.uuidString) < (rhs.orderIndex, rhs.id.uuidString)
    }

    private func documentSystemImage(_ document: Document) -> String {
        switch DocumentKind(rawValue: document.kind) {
        case .draftFolder: "text.book.closed"
        case .folder: "folder"
        case .text: "doc.plaintext"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .webArchive: "globe"
        case .unknown, .none: "doc"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
