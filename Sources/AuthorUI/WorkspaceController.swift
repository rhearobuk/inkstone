import AuthorData
import Combine
import CoreData
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

public enum WorkspaceSelection: Hashable, Sendable {
    case projectDefinition(UUID)
    case storyBible(UUID)
    case storyBibleCategory(projectID: UUID, category: StoryBibleCategory)
    case gallery(UUID)
    case galleryItem(UUID)
    case narrative(UUID)
    case characterProfile(UUID)
    case semanticEntity(UUID)
    case document(UUID)
    case trash(UUID)
}

public enum StoryBibleCategory: String, CaseIterable, Identifiable, Sendable {
    case people = "People"
    case places = "Places"
    case artifacts = "Artifacts"
    case events = "Events, Conflicts & Timelines"
    case worldbuilding = "Worldbuilding"
    case research = "Research"

    public var id: Self { self }

    public var systemImage: String {
        switch self {
        case .people: "person.2"
        case .places: "map"
        case .artifacts: "shippingbox"
        case .events: "point.3.connected.trianglepath.dotted"
        case .worldbuilding: "globe"
        case .research: "books.vertical"
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
        case .research:
            false
        }
    }

    public var defaultEntityKind: SemanticEntityKind {
        switch self {
        case .people: .character
        case .places: .location
        case .artifacts: .object
        case .events: .event
        case .worldbuilding: .concept
        case .research: .concept
        }
    }
}

public enum DropPosition: String, Sendable, Equatable {
    case before
    case inside
    case after
}

public struct ActiveDropTarget: Equatable, Sendable {
    public let documentID: UUID
    public let position: DropPosition

    public init(documentID: UUID, position: DropPosition) {
        self.documentID = documentID
        self.position = position
    }
}

public enum ScrivenerImportDestination: Equatable, Sendable {
    case existing(UUID)
    case newProject(title: String)
}

public struct BinderItem: Identifiable {
    public enum Kind: Equatable, Sendable {
        case projectDefinition
        case storyBible
        case storyBibleCategory(StoryBibleCategory)
        case gallery
        case galleryItem
        case narrative
        case characterProfile
        case semanticEntity
        case document
        case trash
    }

    public let id: String
    public let title: String
    public let systemImage: String
    public let selection: WorkspaceSelection
    public let kind: Kind
    public let documentID: UUID?
    public let isContainer: Bool
    public let isHidden: Bool
    public let isTrashed: Bool
    public let labelIdentifier: String?
    public let statusIdentifier: String?
    public let labelColor: Color?
    public let labelTitle: String?
    public let statusTitle: String?
    public let sectionTypeTitle: String?
    public var children: [BinderItem]?

    public init(
        id: String,
        title: String,
        systemImage: String,
        selection: WorkspaceSelection,
        kind: Kind,
        documentID: UUID? = nil,
        isContainer: Bool = false,
        isHidden: Bool = false,
        isTrashed: Bool = false,
        labelIdentifier: String? = nil,
        statusIdentifier: String? = nil,
        labelColor: Color? = nil,
        labelTitle: String? = nil,
        statusTitle: String? = nil,
        sectionTypeTitle: String? = nil,
        children: [BinderItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.selection = selection
        self.kind = kind
        self.documentID = documentID
        self.isContainer = isContainer
        self.isHidden = isHidden
        self.isTrashed = isTrashed
        self.labelIdentifier = labelIdentifier
        self.statusIdentifier = statusIdentifier
        self.labelColor = labelColor
        self.labelTitle = labelTitle
        self.statusTitle = statusTitle
        self.sectionTypeTitle = sectionTypeTitle
        self.children = children
    }
}

public enum WorkspaceError: LocalizedError {
    case missingProject(UUID)
    case missingDocument(UUID)
    case invalidMove
    case noScrivenerProject(URL)
    case multipleScrivenerProjects(URL)
    case invalidImage(URL)

    public var errorDescription: String? {
        switch self {
        case .missingProject(let id): "Project \(id) no longer exists."
        case .missingDocument(let id): "Document \(id) no longer exists."
        case .invalidMove: "A binder item cannot be moved inside itself or one of its descendants."
        case .noScrivenerProject(let url):
            "No Scrivener project XML and Files folder were found in \(url.path)."
        case .multipleScrivenerProjects(let url):
            "More than one XML file exists in \(url.path). Select a folder containing one Scrivener project."
        case .invalidImage(let url):
            "\(url.lastPathComponent) is not a supported image file."
        }
    }
}

@MainActor
public final class WorkspaceController: ObservableObject {
    public let store: AuthorDataStore
    public let editorialReviews: EditorialReviewController
    @Published public var editorialPassage: EditorialPassage?
    private let projectListPreferences: UserDefaults
    private var pendingCharacterSave: Task<Void, Never>?
    private var labelLookup: [String: LabelDefinition] = [:]
    private var statusLookup: [String: StatusDefinition] = [:]
    private var sectionTypeLookup: [String: SectionTypeDefinition] = [:]

    @Published public private(set) var projects: [WritingProject] = []
    @Published public var showsHiddenProjects = false
    @Published public var showsTrashedProjects = false
    @Published public var showsHiddenDocuments = false
    @Published public var projectToTrash: UUID?
    @Published public var projectToDeletePermanently: UUID?
    @Published public var showsEmptyProjectTrashAlert = false
    @Published public var documentToTrash: UUID?
    @Published public var documentToDeletePermanently: UUID?
    @Published public var showsEmptyTrashAlert = false
    @Published public var selectedProjectID: UUID?
    @Published public var selection: WorkspaceSelection?
    @Published public private(set) var binderItems: [BinderItem] = []
    @Published public var activeDropTarget: ActiveDropTarget?
    @Published public var labelFilter: String?
    @Published public var statusFilter: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var importSummary: String?
    @Published public private(set) var isImporting = false

    public init(store: AuthorDataStore, projectListPreferences: UserDefaults = .standard) {
        self.store = store
        self.editorialReviews = EditorialReviewController(store: store)
        self.projectListPreferences = projectListPreferences
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

    public var selectedCharacterProfile: CharacterProfile? {
        guard case .characterProfile(let id) = selection else { return nil }
        return try? store.characterProfiles.fetch(id: id)
    }

    public var selectedGalleryItem: GalleryItem? {
        guard case .galleryItem(let id) = selection else { return nil }
        return try? store.galleryItems.fetch(id: id)
    }

    public var galleryItems: [GalleryItem] {
        guard let project = selectedProject else { return [] }
        return project.galleryItems.sorted {
            ($0.orderIndex, $0.title, $0.id.uuidString) <
                ($1.orderIndex, $1.title, $1.id.uuidString)
        }
    }

    public func updateGalleryItem(title: String, caption: String?) {
        guard let item = selectedGalleryItem else { return }
        item.title = title
        item.caption = caption?.nilIfBlank
        item.modifiedAt = Date()
        item.source = ProvenanceAgent.human.rawValue
        do {
            try store.save()
            objectWillChange.send()
        } catch {
            report(error)
        }
    }

    @discardableResult
    public func addGalleryImages(
        from urls: [URL],
        to sourceDocument: Document? = nil,
        relatedTo semanticEntity: SemanticEntity? = nil
    ) throws -> [GalleryItem] {
        guard let project = selectedProject else {
            throw WorkspaceError.missingProject(selectedProjectID ?? UUID())
        }
        let images = try urls.map { url -> (url: URL, data: Data, type: UTType) in
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else {
                throw WorkspaceError.invalidImage(url)
            }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !data.isEmpty,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else {
                throw WorkspaceError.invalidImage(url)
            }
            return (url, data, type)
        }

        var orderIndex = (project.galleryItems.map(\.orderIndex).max() ?? -1) + 1
        let now = Date()
        let items = images.map { image in
            let resourceID = UUID()
            let extensionName = image.url.pathExtension.lowercased()
            let digest = SHA256.hash(data: image.data)
                .map { String(format: "%02x", $0) }
                .joined()
            let resource = store.resources.create(id: resourceID) {
                $0.sourcePath = "Native/Gallery/\(resourceID.uuidString).\(extensionName)"
                $0.role = "galleryImage"
                $0.mediaType = image.type.preferredMIMEType ?? "application/octet-stream"
                $0.byteCount = Int64(image.data.count)
                $0.sha256 = digest
                $0.data = image.data
                $0.isSourcePreserved = false
                $0.project = project
                $0.document = sourceDocument
            }
            let item = store.galleryItems.create {
                $0.title = image.url.deletingPathExtension().lastPathComponent
                $0.source = ProvenanceAgent.human.rawValue
                $0.orderIndex = orderIndex
                $0.createdAt = now
                $0.modifiedAt = now
                $0.project = project
                $0.resource = resource
                $0.sourceDocument = sourceDocument
                $0.semanticEntity = semanticEntity
            }
            orderIndex += 1
            return item
        }
        project.modifiedAt = now
        try store.save()
        refresh()
        return items
    }

    public func deleteGalleryItem(_ item: GalleryItem) {
        let projectID = item.project.id
        let sourceDocument = item.sourceDocument
        let relatedEntity = item.semanticEntity
        let resource = item.resource
        store.context.delete(item)
        if resource.role == "galleryImage" {
            store.context.delete(resource)
        }
        do {
            try store.save()
            if let profile = relatedEntity?.characterProfile {
                selection = .characterProfile(profile.id)
            } else if let relatedEntity {
                selection = .semanticEntity(relatedEntity.id)
            } else if let profile = sourceDocument?.sourceCharacterProfiles.first {
                selection = .characterProfile(profile.id)
            } else if let sourceDocument {
                selection = .document(sourceDocument.id)
            } else {
                selection = .gallery(projectID)
            }
            refresh()
        } catch {
            report(error)
        }
    }

    public var otherCharacterProfiles: [CharacterProfile] {
        guard let selectedCharacterProfile, let project = selectedProject else { return [] }
        return project.characterProfiles
            .filter { $0.id != selectedCharacterProfile.id }
            .sorted {
                $0.semanticEntity.canonicalName.localizedCaseInsensitiveCompare(
                    $1.semanticEntity.canonicalName
                ) == .orderedAscending
            }
    }

    public func refresh() {
        do {
            let allProjects = try store.projects.fetchAll(
                sortedBy: [NSSortDescriptor(key: "modifiedAt", ascending: false)]
            )
            projects = allProjects
                .filter {
                    let trashed = isProjectTrashed($0.id)
                    let hidden = isProjectHidden($0.id)
                    if trashed {
                        return showsTrashedProjects
                    }
                    return showsHiddenProjects || !hidden
                }
                .sorted { lhs, rhs in
                    let lhsTrashed = isProjectTrashed(lhs.id)
                    let rhsTrashed = isProjectTrashed(rhs.id)
                    if lhsTrashed != rhsTrashed { return !lhsTrashed }
                    let lhsPinned = isProjectPinned(lhs.id)
                    let rhsPinned = isProjectPinned(rhs.id)
                    if lhsPinned != rhsPinned { return lhsPinned }
                    if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = projects.first(where: { !isProjectTrashed($0.id) })?.id ?? projects.first?.id
            }
            activeDropTarget = nil
            rebuildBinder()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public var trashedProjects: [WritingProject] {
        (try? store.projects.fetchAll(sortedBy: [NSSortDescriptor(key: "modifiedAt", ascending: false)]))?
            .filter { isProjectTrashed($0.id) } ?? []
    }

    public func isProjectPinned(_ projectID: UUID) -> Bool {
        projectListPreferences.stringArray(forKey: "pinnedProjectIDs")?.contains(projectID.uuidString) ?? false
    }

    public func isProjectHidden(_ projectID: UUID) -> Bool {
        projectListPreferences.stringArray(forKey: "hiddenProjectIDs")?.contains(projectID.uuidString) ?? false
    }

    public func isProjectTrashed(_ projectID: UUID) -> Bool {
        projectListPreferences.stringArray(forKey: "trashedProjectIDs")?.contains(projectID.uuidString) ?? false
    }

    public func setProjectPinned(_ projectID: UUID, pinned: Bool) {
        var projectIDs = Set(projectListPreferences.stringArray(forKey: "pinnedProjectIDs") ?? [])
        if pinned {
            projectIDs.insert(projectID.uuidString)
        } else {
            projectIDs.remove(projectID.uuidString)
        }
        projectListPreferences.set(Array(projectIDs), forKey: "pinnedProjectIDs")
        refresh()
    }

    public func setProjectHidden(_ projectID: UUID, hidden: Bool) {
        var projectIDs = Set(projectListPreferences.stringArray(forKey: "hiddenProjectIDs") ?? [])
        if hidden {
            projectIDs.insert(projectID.uuidString)
        } else {
            projectIDs.remove(projectID.uuidString)
        }
        projectListPreferences.set(Array(projectIDs), forKey: "hiddenProjectIDs")
        if hidden && selectedProjectID == projectID {
            selectedProjectID = nil
            selection = nil
        }
        refresh()
    }

    public func trashProject(_ projectID: UUID) {
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedProjectIDs") ?? [])
        trashedIDs.insert(projectID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedProjectIDs")
        if selectedProjectID == projectID {
            selectedProjectID = nil
            selection = nil
        }
        refresh()
    }

    public func restoreProject(_ projectID: UUID) {
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedProjectIDs") ?? [])
        trashedIDs.remove(projectID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedProjectIDs")
        selectedProjectID = projectID
        selection = .projectDefinition(projectID)
        refresh()
    }

    public func deleteProjectPermanently(_ projectID: UUID) throws {
        guard let project = try store.projects.fetch(id: projectID) else {
            throw WorkspaceError.missingProject(projectID)
        }
        store.context.delete(project)
        setProjectPinned(projectID, pinned: false)
        setProjectHidden(projectID, hidden: false)
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedProjectIDs") ?? [])
        trashedIDs.remove(projectID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedProjectIDs")
        if selectedProjectID == projectID {
            selectedProjectID = nil
            selection = nil
        }
        try store.save()
        refresh()
    }

    public func emptyProjectTrash() throws {
        let projects = trashedProjects
        let projectIDs = projects.map(\.id)
        for project in projects {
            store.context.delete(project)
        }
        for id in projectIDs {
            setProjectPinned(id, pinned: false)
            setProjectHidden(id, hidden: false)
        }
        try store.save()
        projectListPreferences.set([String](), forKey: "trashedProjectIDs")
        refresh()
    }

    public func deleteProject(_ projectID: UUID) throws {
        trashProject(projectID)
    }

    public func isDocumentTrashed(_ document: Document) -> Bool {
        guard !document.isDeleted else { return false }
        let trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        if trashedIDs.contains(document.id.uuidString) { return true }
        var curr = document.parent
        while let p = curr, !p.isDeleted {
            if trashedIDs.contains(p.id.uuidString) { return true }
            curr = p.parent
        }
        return false
    }

    public func isDocumentTrashed(_ documentID: UUID) -> Bool {
        let trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        if trashedIDs.contains(documentID.uuidString) { return true }
        if let doc = try? store.documents.fetch(id: documentID), !doc.isDeleted {
            return isDocumentTrashed(doc)
        }
        return false
    }

    public func isDocumentDirectlyTrashed(_ documentID: UUID) -> Bool {
        let trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        return trashedIDs.contains(documentID.uuidString)
    }

    public func isDocumentHidden(_ document: Document) -> Bool {
        guard !document.isDeleted else { return false }
        let hiddenIDs = Set(projectListPreferences.stringArray(forKey: "hiddenDocumentIDs") ?? [])
        if hiddenIDs.contains(document.id.uuidString) { return true }
        var curr = document.parent
        while let p = curr, !p.isDeleted {
            if hiddenIDs.contains(p.id.uuidString) { return true }
            curr = p.parent
        }
        return false
    }

    public func isDocumentHidden(_ documentID: UUID) -> Bool {
        let hiddenIDs = Set(projectListPreferences.stringArray(forKey: "hiddenDocumentIDs") ?? [])
        if hiddenIDs.contains(documentID.uuidString) { return true }
        if let doc = try? store.documents.fetch(id: documentID), !doc.isDeleted {
            return isDocumentHidden(doc)
        }
        return false
    }

    public func setDocumentHidden(_ documentID: UUID, hidden: Bool) {
        var hiddenIDs = Set(projectListPreferences.stringArray(forKey: "hiddenDocumentIDs") ?? [])
        if hidden {
            hiddenIDs.insert(documentID.uuidString)
        } else {
            hiddenIDs.remove(documentID.uuidString)
        }
        projectListPreferences.set(Array(hiddenIDs), forKey: "hiddenDocumentIDs")
        refresh()
    }

    public func trashDocument(_ documentID: UUID) {
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        trashedIDs.insert(documentID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedDocumentIDs")
        if let doc = try? store.documents.fetch(id: documentID), !doc.isDeleted {
            doc.modifiedAt = Date()
            doc.project.modifiedAt = Date()
            try? store.save()
        }
        refresh()
    }

    public func restoreDocument(_ documentID: UUID) {
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        trashedIDs.remove(documentID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedDocumentIDs")
        if let doc = try? store.documents.fetch(id: documentID), !doc.isDeleted {
            if let parent = doc.parent, !parent.isDeleted, isDocumentTrashed(parent) {
                let narrative = doc.project.documents.first { $0.title == "Narrative" && $0.parent == nil && !$0.isDeleted }
                doc.parent = narrative
            }
            doc.modifiedAt = Date()
            doc.project.modifiedAt = Date()
            try? store.save()
        }
        selection = .document(documentID)
        refresh()
    }

    public func deleteDocument(_ documentID: UUID) {
        trashDocument(documentID)
    }

    public func documentTitle(for id: UUID) -> String {
        (try? store.documents.fetch(id: id))?.title ?? "this scene"
    }

    public func projectTitle(for id: UUID) -> String {
        projects.first(where: { $0.id == id })?.title ??
            (try? store.projects.fetch(id: id))?.title ?? "this project"
    }

    public func deleteDocumentPermanently(_ documentID: UUID) throws {
        guard let document = try store.documents.fetch(id: documentID) else {
            throw WorkspaceError.missingDocument(documentID)
        }
        let project = document.project
        WordCountService.removeSubtree(document, from: document.parent)
        document.parent = nil
        store.context.delete(document)
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        trashedIDs.remove(documentID.uuidString)
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedDocumentIDs")
        var hiddenIDs = Set(projectListPreferences.stringArray(forKey: "hiddenDocumentIDs") ?? [])
        hiddenIDs.remove(documentID.uuidString)
        projectListPreferences.set(Array(hiddenIDs), forKey: "hiddenDocumentIDs")
        if case .document(let id) = selection, id == documentID {
            selection = .trash(project.id)
        }
        project.modifiedAt = Date()
        try store.save()
        refresh()
    }

    public func emptyTrash(for projectID: UUID) throws {
        guard let project = try store.projects.fetch(id: projectID) else {
            throw WorkspaceError.missingProject(projectID)
        }
        let trashed = trashedDocuments(in: project)
        let docIDs = trashed.map(\.id)
        let trashedDocIDSet = Set(docIDs)
        var trashedIDs = Set(projectListPreferences.stringArray(forKey: "trashedDocumentIDs") ?? [])
        var hiddenIDs = Set(projectListPreferences.stringArray(forKey: "hiddenDocumentIDs") ?? [])
        for doc in trashed {
            // Only adjust rollups from documents whose parent survives this batch; descendants
            // whose ancestor is also being deleted are already accounted for via that ancestor.
            if !doc.ancestors.contains(where: { trashedDocIDSet.contains($0.id) }) {
                WordCountService.removeSubtree(doc, from: doc.parent)
            }
            doc.parent = nil
            store.context.delete(doc)
        }
        for docID in docIDs {
            trashedIDs.remove(docID.uuidString)
            hiddenIDs.remove(docID.uuidString)
        }
        projectListPreferences.set(Array(trashedIDs), forKey: "trashedDocumentIDs")
        projectListPreferences.set(Array(hiddenIDs), forKey: "hiddenDocumentIDs")
        if case .document = selection {
            selection = .trash(project.id)
        }
        project.modifiedAt = Date()
        try store.save()
        refresh()
    }

    public func trashedDocuments(in project: WritingProject) -> [Document] {
        documents(in: project)
            .filter { !($0.isDeleted) && isDocumentDirectlyTrashed($0.id) }
            .sorted(by: documentOrder)
    }

    @discardableResult
    public func importScrivenerProject(
        from selectedURL: URL,
        destination: ScrivenerImportDestination
    ) throws -> ScrivenerImportResult {
        isImporting = true
        importSummary = nil
        defer { isImporting = false }

        let source = try scrivenerSource(from: selectedURL)
        let targetProject: WritingProject
        let createdProject: WritingProject?
        switch destination {
        case .existing(let projectID):
            targetProject = try store.projects.require(id: projectID)
            createdProject = nil
        case .newProject(let title):
            targetProject = try createProject(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                createStarterContent: false
            )
            createdProject = targetProject
        }

        let result: ScrivenerImportResult
        do {
            result = try ScrivenerImporter(store: store).importProject(
                xmlURL: source.xml,
                filesURL: source.files,
                targetProjectID: targetProject.id
            )
        } catch {
            if let createdProject {
                store.context.delete(createdProject)
                try? store.save()
                refresh()
            }
            throw error
        }
        selectedProjectID = result.projectID
        selection = .projectDefinition(result.projectID)
        refresh()
        importSummary = """
        Imported \(result.documentCount) binder items and \(result.resourceCount) resources \
        with \(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s").
        """
        return result
    }

    @discardableResult
    public func createProject(
        title: String,
        author: String? = nil,
        createStarterContent: Bool = true
    ) throws -> WritingProject {
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
        guard createStarterContent else {
            try store.save()
            selectedProjectID = project.id
            selection = .projectDefinition(project.id)
            refresh()
            return project
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
            $0.narrativeType = NarrativeType.scene.rawValue
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
            $0.narrativeType = kind == .text ? NarrativeType.scene.rawValue : nil
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
        if category == .people {
            let nameComponents = name.split(whereSeparator: \.isWhitespace).map(String.init)
            let profile = store.characterProfiles.create {
                $0.firstName = nameComponents.first ?? name
                $0.middleName = nameComponents.count > 2
                    ? nameComponents.dropFirst().dropLast().joined(separator: " ")
                    : nil
                $0.lastName = nameComponents.count > 1 ? nameComponents.last : nil
                $0.source = ProvenanceAgent.human.rawValue
                $0.createdAt = now
                $0.modifiedAt = now
                $0.project = project
                $0.semanticEntity = entity
            }
            selection = .characterProfile(profile.id)
        } else {
            selection = .semanticEntity(entity.id)
        }
        project.modifiedAt = now
        try store.save()
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

    // MARK: - Project Preferences (Section Types, Labels, Statuses, Custom Metadata)

    public var sortedSectionTypeDefinitions: [SectionTypeDefinition] {
        guard let project = selectedProject else { return [] }
        return project.sectionTypeDefinitions.sorted {
            ($0.orderIndex, $0.title) < ($1.orderIndex, $1.title)
        }
    }

    public var sortedLabelDefinitions: [LabelDefinition] {
        guard let project = selectedProject else { return [] }
        return project.labelDefinitions.sorted {
            ($0.orderIndex, $0.title) < ($1.orderIndex, $1.title)
        }
    }

    public var sortedStatusDefinitions: [StatusDefinition] {
        guard let project = selectedProject else { return [] }
        return project.statusDefinitions.sorted {
            ($0.orderIndex, $0.title) < ($1.orderIndex, $1.title)
        }
    }

    public var sortedCustomMetadataFields: [MetadataField] {
        guard let project = selectedProject else { return [] }
        return project.metadataFields
            .filter { $0.sourceIdentifier != nil || !$0.isSourceDefined }
            .sorted { ($0.orderIndex, $0.displayName) < ($1.orderIndex, $1.displayName) }
    }

    @discardableResult
    public func addSectionType(title: String) -> SectionTypeDefinition? {
        guard let project = selectedProject else { return nil }
        let maxOrder = project.sectionTypeDefinitions.map(\.orderIndex).max() ?? -1
        let definition = store.sectionTypeDefinitions.create {
            $0.sourceIdentifier = "native.\(UUID().uuidString)"
            $0.title = title
            $0.orderIndex = maxOrder + 1
            $0.project = project
        }
        project.modifiedAt = Date()
        saveAndRefresh()
        return definition
    }

    public func renameSectionType(_ definition: SectionTypeDefinition, title: String) {
        definition.title = title
        definition.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func deleteSectionType(_ definition: SectionTypeDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh()
    }

    @discardableResult
    public func addLabel(title: String, color: (red: Double, green: Double, blue: Double)? = nil) -> LabelDefinition? {
        guard let project = selectedProject else { return nil }
        let maxOrder = project.labelDefinitions.map(\.orderIndex).max() ?? -1
        let definition = store.labelDefinitions.create {
            $0.sourceIdentifier = "native.\(UUID().uuidString)"
            $0.title = title
            $0.colorRed = color.map { NSNumber(value: $0.red) }
            $0.colorGreen = color.map { NSNumber(value: $0.green) }
            $0.colorBlue = color.map { NSNumber(value: $0.blue) }
            $0.orderIndex = maxOrder + 1
            $0.project = project
        }
        project.modifiedAt = Date()
        saveAndRefresh()
        return definition
    }

    public func updateLabel(
        _ definition: LabelDefinition,
        title: String,
        color: (red: Double, green: Double, blue: Double)?
    ) {
        definition.title = title
        definition.colorRed = color.map { NSNumber(value: $0.red) }
        definition.colorGreen = color.map { NSNumber(value: $0.green) }
        definition.colorBlue = color.map { NSNumber(value: $0.blue) }
        definition.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func deleteLabel(_ definition: LabelDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh()
    }

    @discardableResult
    public func addStatus(title: String) -> StatusDefinition? {
        guard let project = selectedProject else { return nil }
        let maxOrder = project.statusDefinitions.map(\.orderIndex).max() ?? -1
        let definition = store.statusDefinitions.create {
            $0.sourceIdentifier = "native.\(UUID().uuidString)"
            $0.title = title
            $0.orderIndex = maxOrder + 1
            $0.project = project
        }
        project.modifiedAt = Date()
        saveAndRefresh()
        return definition
    }

    public func renameStatus(_ definition: StatusDefinition, title: String) {
        definition.title = title
        definition.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func deleteStatus(_ definition: StatusDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh()
    }

    @discardableResult
    public func addCustomMetadataField(displayName: String, valueType: String = "text") -> MetadataField? {
        guard let project = selectedProject else { return nil }
        let maxOrder = project.metadataFields.map(\.orderIndex).max() ?? -1
        let key = "custom.\(UUID().uuidString)"
        let field = store.metadataFields.create {
            $0.key = key
            $0.displayName = displayName
            $0.valueType = valueType
            $0.isSourceDefined = false
            $0.orderIndex = maxOrder + 1
            $0.project = project
        }
        project.modifiedAt = Date()
        saveAndRefresh()
        return field
    }

    public func updateCustomMetadataField(_ field: MetadataField, displayName: String, valueType: String) {
        field.displayName = displayName
        field.valueType = valueType
        field.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func deleteCustomMetadataField(_ field: MetadataField) {
        let project = field.project
        store.context.delete(field)
        project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func updateDocument(title: String, synopsis: String?, plainText: String?) {
        guard let document = selectedDocument else { return }
        document.title = title
        document.synopsis = synopsis?.nilIfBlank
        document.plainText = plainText
        WordCountService.recomputeOwnWordCount(for: document)
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func updateDocumentRichText(rtfData: Data, plainText: String) {
        guard let document = selectedDocument else {
            return
        }
        let resource = document.resources.first {
            $0.role == "content" && $0.mediaType == "application/rtf"
        } ?? store.resources.create {
            $0.sourcePath = "Native/Documents/\(document.id.uuidString)/content.rtf"
            $0.role = "content"
            $0.mediaType = "application/rtf"
            $0.byteCount = 0
            $0.sha256 = ""
            $0.isSourcePreserved = false
            $0.project = document.project
            $0.document = document
        }
        document.plainText = plainText
        WordCountService.recomputeOwnWordCount(for: document)
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        resource.data = rtfData
        resource.textContent = plainText
        resource.byteCount = Int64(rtfData.count)
        resource.sha256 = SHA256.hash(data: rtfData).map { String(format: "%02x", $0) }.joined()
        saveAndRefresh()
    }

    // MARK: - Narrative Metadata (Book/Section/Chapter/Scene)

    /// Sets or clears a folder's narrative role. Text documents are always `.scene` and cannot be
    /// changed (set at creation time in `addDocument`).
    public func setNarrativeType(_ document: Document, to type: NarrativeType?) {
        document.narrativeType = type?.rawValue
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        saveAndRefresh()
    }

    /// Sets this document's own "Do Not Publish" flag. Does not affect inherited exclusion from
    /// ancestors; see `Document.isPublishingExcluded`.
    public func setDoNotPublish(_ document: Document, _ value: Bool) {
        document.includeInCompile = NSNumber(value: !value)
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func narrativeFields(for document: Document) -> [NarrativeFieldDescriptor] {
        guard let type = document.narrativeType.flatMap(NarrativeType.init(rawValue:)) else { return [] }
        return NarrativeMetadataSchema.fields(for: type)
    }

    public func narrativeFieldValue(_ descriptor: NarrativeFieldDescriptor, on document: Document) -> String {
        NarrativeMetadataStore.stringValue(for: descriptor, on: document)
    }

    public func setNarrativeFieldValue(_ rawValue: String, for descriptor: NarrativeFieldDescriptor, on document: Document) {
        NarrativeMetadataStore.setValue(rawValue, for: descriptor, on: document, store: store)
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        saveAndRefresh()
    }

    /// The document's position among same-typed siblings (Chapter or Section) counted in
    /// depth-first tree order within the nearest ancestor Book (or the narrative root, if the
    /// item isn't nested under a Book). Returns nil for Book/Scene, which aren't numbered this way.
    public func computedNarrativeNumber(for document: Document) -> Int? {
        guard let type = document.narrativeType.flatMap(NarrativeType.init(rawValue:)),
              type == .chapter || type == .section else { return nil }
        let scopeRoot = document.ancestors.first { $0.narrativeType == NarrativeType.book.rawValue }
            ?? document.ancestors.last
        guard let scopeRoot else { return nil }

        var counter = 0
        var result: Int?
        func visit(_ node: Document) {
            if node.narrativeType == type.rawValue {
                counter += 1
                if node.id == document.id { result = counter }
            }
            for child in node.orderedChildren { visit(child) }
        }
        for child in scopeRoot.orderedChildren { visit(child) }
        return result
    }

    public func updateSemanticEntity(name: String, summary: String?) {
        guard let entity = selectedSemanticEntity else { return }
        entity.canonicalName = name
        entity.summary = summary?.nilIfBlank
        entity.modifiedAt = Date()
        entity.project.modifiedAt = Date()
        saveAndRefresh()
    }

    public func saveCharacterProfile(_ profile: CharacterProfile) {
        profile.semanticEntity.canonicalName = [
            profile.firstName, profile.middleName, profile.lastName
        ].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        let normalizedAge = profile.ageText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedAge, let age = Int(normalizedAge) {
            profile.age = NSNumber(value: age)
        } else {
            profile.age = nil
        }
        profile.semanticEntity.modifiedAt = Date()
        profile.semanticEntity.source = ProvenanceAgent.human.rawValue
        profile.modifiedAt = Date()
        profile.source = ProvenanceAgent.human.rawValue
        profile.project.modifiedAt = Date()
        scheduleCharacterSave()
    }

    public func saveAlias(_ alias: EntityAlias, for profile: CharacterProfile) {
        alias.normalizedName = alias.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        markCharacterEdited(profile)
        scheduleCharacterSave()
    }

    public func saveMeasurement(_ measurement: CharacterMeasurement) {
        markCharacterEdited(measurement.characterProfile)
        scheduleCharacterSave()
    }

    public func saveCharacterNote(_ note: CharacterNote) {
        note.source = ProvenanceAgent.human.rawValue
        note.modifiedAt = Date()
        markCharacterEdited(note.characterProfile)
        scheduleCharacterSave()
    }

    public func saveCharacterRelationship(_ relationship: CharacterRelationship) {
        relationship.source = ProvenanceAgent.human.rawValue
        relationship.modifiedAt = Date()
        markCharacterEdited(relationship.sourceCharacter)
        scheduleCharacterSave()
    }

    public func saveCharacterConflict(_ conflict: CharacterConflict) {
        conflict.source = ProvenanceAgent.human.rawValue
        conflict.modifiedAt = Date()
        markCharacterEdited(conflict.characterProfile)
        scheduleCharacterSave()
    }

    public func deleteAlias(_ alias: EntityAlias) {
        store.context.delete(alias)
        saveAndRefresh()
    }

    public func deleteMeasurement(_ measurement: CharacterMeasurement) {
        store.context.delete(measurement)
        saveAndRefresh()
    }

    public func deleteCharacterNote(_ note: CharacterNote) {
        store.context.delete(note)
        saveAndRefresh()
    }

    public func deleteCharacterRelationship(_ relationship: CharacterRelationship) {
        store.context.delete(relationship)
        saveAndRefresh()
    }

    public func deleteCharacterConflict(_ conflict: CharacterConflict) {
        store.context.delete(conflict)
        saveAndRefresh()
    }

    private func markCharacterEdited(_ profile: CharacterProfile) {
        profile.source = ProvenanceAgent.human.rawValue
        profile.semanticEntity.source = ProvenanceAgent.human.rawValue
        profile.modifiedAt = Date()
        profile.semanticEntity.modifiedAt = Date()
        profile.project.modifiedAt = Date()
    }

    private func scheduleCharacterSave() {
        pendingCharacterSave?.cancel()
        pendingCharacterSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                try self.store.save()
            } catch is CancellationError {
                return
            } catch {
                self?.report(error)
            }
        }
    }

    public func addAlias(_ name: String, to profile: CharacterProfile) throws {
        let normalized = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty,
              !profile.semanticEntity.aliases.contains(where: { $0.normalizedName == normalized }) else {
            return
        }
        store.entityAliases.create {
            $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.normalizedName = normalized
            $0.semanticEntity = profile.semanticEntity
        }
        try store.save()
        refresh()
    }

    public func addMeasurement(
        name: String,
        value: String,
        unit: String?,
        to profile: CharacterProfile
    ) throws {
        store.characterMeasurements.create {
            $0.name = name
            $0.value = value
            $0.unit = unit?.nilIfBlank
            $0.orderIndex = Int64(profile.measurements.count)
            $0.characterProfile = profile
        }
        try store.save()
        refresh()
    }

    public func addCharacterNote(
        title: String?,
        body: String,
        to profile: CharacterProfile
    ) throws {
        let now = Date()
        store.characterNotes.create {
            $0.title = title?.nilIfBlank
            $0.body = body
            $0.kind = "general"
            $0.source = ProvenanceAgent.human.rawValue
            $0.orderIndex = Int64(profile.notes.count)
            $0.createdAt = now
            $0.modifiedAt = now
            $0.characterProfile = profile
        }
        try store.save()
        refresh()
    }

    public func addCharacterRelationship(
        kind: String,
        notes: String?,
        from source: CharacterProfile,
        to target: CharacterProfile
    ) throws {
        let now = Date()
        store.characterRelationships.create {
            $0.kind = kind.nilIfBlank ?? "other"
            $0.notes = notes?.nilIfBlank
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.sourceCharacter = source
            $0.targetCharacter = target
        }
        try store.save()
        refresh()
    }

    public func addCharacterConflict(
        title: String,
        summary: String?,
        kind: String,
        relatedCharacter: CharacterProfile?,
        to profile: CharacterProfile
    ) throws {
        let now = Date()
        store.characterConflicts.create {
            $0.title = title
            $0.summary = summary?.nilIfBlank
            $0.kind = kind
            $0.status = "active"
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.characterProfile = profile
            $0.relatedCharacters = relatedCharacter.map { Set([$0]) } ?? []
        }
        try store.save()
        refresh()
    }

    public func moveDocument(
        _ documentID: UUID,
        relativeTo targetID: UUID,
        position: DropPosition = .inside
    ) throws {
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

        let newParent: Document?
        let insertionIndex: Int

        switch position {
        case .inside:
            if targetIsContainer {
                newParent = target
                insertionIndex = Int.max
            } else {
                newParent = target.parent
                let siblings = documents(in: document.project)
                    .filter { $0.parent?.id == newParent?.id && $0.id != document.id }
                    .sorted(by: documentOrder)
                let targetIdx = siblings.firstIndex(where: { $0.id == target.id }) ?? (siblings.count - 1)
                insertionIndex = targetIdx + 1
            }
        case .before:
            newParent = target.parent
            let siblings = documents(in: document.project)
                .filter { $0.parent?.id == newParent?.id && $0.id != document.id }
                .sorted(by: documentOrder)
            let targetIdx = siblings.firstIndex(where: { $0.id == target.id }) ?? 0
            insertionIndex = targetIdx
        case .after:
            newParent = target.parent
            let siblings = documents(in: document.project)
                .filter { $0.parent?.id == newParent?.id && $0.id != document.id }
                .sorted(by: documentOrder)
            let targetIdx = siblings.firstIndex(where: { $0.id == target.id }) ?? (siblings.count - 1)
            insertionIndex = targetIdx + 1
        }

        if oldParent?.id != newParent?.id {
            WordCountService.removeSubtree(document, from: oldParent)
        }
        document.parent = newParent
        if oldParent?.id != newParent?.id {
            WordCountService.addSubtree(document, to: newParent)
        }
        let newSiblings = documents(in: document.project)
            .filter { $0.parent?.id == newParent?.id && $0.id != document.id }
            .sorted(by: documentOrder)
        let safeIndex = max(0, min(insertionIndex, newSiblings.count))
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

    public func moveDocument(_ documentID: UUID, onto targetID: UUID) throws {
        try moveDocument(documentID, relativeTo: targetID, position: .inside)
    }

    public func selectProject(_ projectID: UUID) {
        selectedProjectID = projectID
        selection = .projectDefinition(projectID)
        labelFilter = nil
        statusFilter = nil
        activeDropTarget = nil
        rebuildBinder()
    }

    /// The binder tree narrowed to `labelFilter`/`statusFilter`, if either is set. Organizational
    /// nodes (Project Definition, Story Bible, Gallery, Narrative, and their categories) always
    /// remain visible so the tree stays navigable; only actual binder documents (folders and
    /// scenes) are matched against the active filters, with ancestors of a match kept so context
    /// is preserved.
    public var displayedBinderItems: [BinderItem] {
        guard labelFilter != nil || statusFilter != nil else { return binderItems }
        return binderItems.compactMap(filteredBinderItem)
    }

    private func filteredBinderItem(_ item: BinderItem) -> BinderItem? {
        var item = item
        let filteredChildren = item.children?.compactMap(filteredBinderItem)
        item.children = filteredChildren
        let matchesSelf: Bool
        if item.documentID != nil {
            let labelOK = labelFilter == nil || item.labelIdentifier == labelFilter
            let statusOK = statusFilter == nil || item.statusIdentifier == statusFilter
            matchesSelf = labelOK && statusOK
        } else {
            matchesSelf = true
        }
        let hasMatchingChildren = !(filteredChildren?.isEmpty ?? true)
        return (matchesSelf || hasMatchingChildren) ? item : nil
    }

    public func storyBibleDocuments(in category: StoryBibleCategory) -> [Document] {
        guard let project = selectedProject else { return [] }
        return documents(in: project)
            .filter { $0.parent == nil && storyBibleCategory(for: $0) == category }
            .sorted(by: documentOrder)
    }

    public func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    public func clearImportSummary() {
        importSummary = nil
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

    func scrivenerSource(from selectedURL: URL) throws -> (xml: URL, files: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory)
        let directory = isDirectory.boolValue
            ? selectedURL
            : selectedURL.deletingLastPathComponent()
        let filesURL = directory.appendingPathComponent("Files", isDirectory: true)

        if !isDirectory.boolValue,
           ["xml", "scrivx"].contains(selectedURL.pathExtension.lowercased()) {
            return (selectedURL, filesURL)
        }

        let xmlFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { ["scrivx", "xml"].contains($0.pathExtension.lowercased()) }

        guard !xmlFiles.isEmpty else {
            throw WorkspaceError.noScrivenerProject(directory)
        }
        guard xmlFiles.count == 1 else {
            throw WorkspaceError.multipleScrivenerProjects(directory)
        }
        return (xmlFiles[0], filesURL)
    }

    private func rebuildBinder() {
        guard let project = selectedProject else {
            binderItems = []
            labelLookup = [:]
            statusLookup = [:]
            sectionTypeLookup = [:]
            selection = nil
            return
        }

        labelLookup = Dictionary(
            uniqueKeysWithValues: project.labelDefinitions.map { ($0.sourceIdentifier, $0) }
        )
        statusLookup = Dictionary(
            uniqueKeysWithValues: project.statusDefinitions.map { ($0.sourceIdentifier, $0) }
        )
        sectionTypeLookup = Dictionary(
            uniqueKeysWithValues: project.sectionTypeDefinitions.map { ($0.sourceIdentifier, $0) }
        )

        let entities = project.semanticEntities.filter {
            $0.characterProfile?.sourceDocument == nil
        }.sorted {
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
                        selection: entity.characterProfile.map {
                            .characterProfile($0.id)
                        } ?? .semanticEntity(entity.id),
                        kind: entity.characterProfile == nil ? .semanticEntity : .characterProfile
                    )
                }
            )
        }
        let documents = documents(in: project)
        let activeDocuments = documents.filter { !isDocumentTrashed($0) }
        let binderDocuments = showsHiddenDocuments ? activeDocuments : activeDocuments.filter { !isDocumentHidden($0) }
        let roots = binderDocuments.filter { $0.parent == nil }.sorted(by: documentOrder)
        let storyBibleRoots = Dictionary(grouping: roots.compactMap { document in
            storyBibleCategory(for: document).map { ($0, document) }
        }, by: \.0)
        let narrativeRoots = roots.filter { storyBibleCategory(for: $0) == nil }
        let visibleNarrativeRoots: [Document]
        let narrativeDocumentID: UUID?
        if narrativeRoots.count == 1,
           let root = narrativeRoots.first,
           root.sourceIdentifier.hasPrefix("native.narrative.") {
            visibleNarrativeRoots = root.orderedChildren.filter { !isDocumentTrashed($0) && (showsHiddenDocuments || !isDocumentHidden($0)) }
            narrativeDocumentID = root.id
        } else {
            visibleNarrativeRoots = narrativeRoots
            narrativeDocumentID = narrativeRoots.first?.id
        }

        let trashedDocs = trashedDocuments(in: project)
        let trashItem = BinderItem(
            id: "trash",
            title: trashedDocs.isEmpty ? "Trash" : "Trash (\(trashedDocs.count))",
            systemImage: trashedDocs.isEmpty ? "trash" : "trash.fill",
            selection: .trash(project.id),
            kind: .trash,
            isContainer: true,
            isTrashed: true,
            children: trashedDocs.isEmpty ? nil : trashedDocs.map { makeDocumentItem($0, isTrashed: true) }
        )

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
                children: StoryBibleCategory.allCases.map { category in
                    let documentItems = (storyBibleRoots[category] ?? [])
                        .map(\.1)
                        .sorted(by: documentOrder)
                        .map { makeDocumentItem($0) }
                    let semanticItems = categories.first {
                        $0.id == "story-bible.\(category.id)"
                    }?.children ?? []
                    return BinderItem(
                        id: "story-bible.\(category.id)",
                        title: category.rawValue,
                        systemImage: category.systemImage,
                        selection: .storyBibleCategory(projectID: project.id, category: category),
                        kind: .storyBibleCategory(category),
                        children: semanticItems + documentItems
                    )
                }
            ),
            BinderItem(
                id: "gallery",
                title: "Gallery",
                systemImage: "photo.on.rectangle.angled",
                selection: .gallery(project.id),
                kind: .gallery,
                children: galleryItems.map { item in
                    BinderItem(
                        id: item.id.uuidString,
                        title: item.title,
                        systemImage: "photo",
                        selection: .galleryItem(item.id),
                        kind: .galleryItem
                    )
                }
            ),
            BinderItem(
                id: "narrative",
                title: "Narrative",
                systemImage: "text.book.closed",
                selection: .narrative(project.id),
                kind: .narrative,
                documentID: narrativeDocumentID,
                isContainer: true,
                children: visibleNarrativeRoots.map { makeDocumentItem($0) }
            ),
            trashItem
        ]
    }

    private func makeDocumentItem(_ document: Document, isTrashed: Bool = false) -> BinderItem {
        let profile = document.sourceCharacterProfiles.first
        let label = document.labelIdentifier.flatMap { labelLookup[$0] }
        let status = document.statusIdentifier.flatMap { statusLookup[$0] }
        let sectionType = document.sectionTypeIdentifier.flatMap { sectionTypeLookup[$0] }
        let isContainer = document.kind == DocumentKind.folder.rawValue ||
            document.kind == DocumentKind.draftFolder.rawValue
        let isHidden = isDocumentHidden(document)
        let validChildren = document.orderedChildren.filter {
            if isTrashed { return true }
            return !isDocumentTrashed($0) && (showsHiddenDocuments || !isDocumentHidden($0))
        }
        return BinderItem(
            id: document.id.uuidString,
            title: document.title,
            systemImage: documentSystemImage(document),
            selection: profile.map { .characterProfile($0.id) } ?? .document(document.id),
            kind: profile == nil ? .document : .characterProfile,
            documentID: document.id,
            isContainer: isContainer,
            isHidden: isHidden,
            isTrashed: isTrashed,
            labelIdentifier: document.labelIdentifier,
            statusIdentifier: document.statusIdentifier,
            labelColor: label?.swiftUIColor,
            labelTitle: label?.title,
            statusTitle: status?.title,
            sectionTypeTitle: sectionType?.title,
            children: validChildren.isEmpty
                ? nil
                : validChildren.map { makeDocumentItem($0, isTrashed: isTrashed) }
        )
    }

    private func documents(in project: WritingProject) -> [Document] {
        project.documents.filter { !$0.isDeleted }
    }

    private func isDescendant(_ candidate: Document, of ancestor: Document) -> Bool {
        var parent = candidate.parent
        while let current = parent {
            if current.id == ancestor.id { return true }
            parent = current.parent
        }
        return false
    }

    private func storyBibleCategory(for document: Document) -> StoryBibleCategory? {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch title {
        case "characters", "character":
            return .people
        case "places", "locations", "settings":
            return .places
        case "artifacts", "objects", "items":
            return .artifacts
        case "conflicts", "timelines", "timeline":
            return .events
        case "research", "template sheets", "templates":
            return .research
        default:
            return document.kind == "ResearchFolder" ? .research : nil
        }
    }

    /// Whether `document` lives under the Narrative tree (as opposed to Story Bible, Gallery, or
    /// Project Definition), based on its root ancestor's classification.
    public func isNarrativeDocument(_ document: Document) -> Bool {
        let root = document.ancestors.last ?? document
        return storyBibleCategory(for: root) == nil
    }

    private func reindex(_ documents: [Document]) {
        for (index, document) in documents.enumerated() {
            document.orderIndex = Int64(index)
        }
    }

    private func documentOrder(_ lhs: Document, _ rhs: Document) -> Bool {
        guard !lhs.isDeleted, !rhs.isDeleted else { return false }
        return (lhs.orderIndex, lhs.id.uuidString) < (rhs.orderIndex, rhs.id.uuidString)
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
