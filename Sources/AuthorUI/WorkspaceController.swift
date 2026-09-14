import AuthorData
import Combine
import CoreData
import CryptoKit
import Foundation

public enum WorkspaceSelection: Hashable, Sendable {
    case projectDefinition(UUID)
    case storyBible(UUID)
    case storyBibleCategory(projectID: UUID, category: StoryBibleCategory)
    case narrative(UUID)
    case characterProfile(UUID)
    case semanticEntity(UUID)
    case document(UUID)
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

public struct BinderItem: Identifiable {
    public enum Kind {
        case projectDefinition
        case storyBible
        case storyBibleCategory(StoryBibleCategory)
        case narrative
        case characterProfile
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
    case noScrivenerProject(URL)
    case multipleScrivenerProjects(URL)

    public var errorDescription: String? {
        switch self {
        case .missingProject(let id): "Project \(id) no longer exists."
        case .missingDocument(let id): "Document \(id) no longer exists."
        case .invalidMove: "A binder item cannot be moved inside itself or one of its descendants."
        case .noScrivenerProject(let url):
            "No Scrivener project XML and Files folder were found in \(url.path)."
        case .multipleScrivenerProjects(let url):
            "More than one XML file exists in \(url.path). Select a folder containing one Scrivener project."
        }
    }
}

@MainActor
public final class WorkspaceController: ObservableObject {
    public let store: AuthorDataStore
    private var pendingCharacterSave: Task<Void, Never>?

    @Published public private(set) var projects: [WritingProject] = []
    @Published public var selectedProjectID: UUID?
    @Published public var selection: WorkspaceSelection?
    @Published public private(set) var binderItems: [BinderItem] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var importSummary: String?
    @Published public private(set) var isImporting = false

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

    public var selectedCharacterProfile: CharacterProfile? {
        guard case .characterProfile(let id) = selection else { return nil }
        return try? store.characterProfiles.fetch(id: id)
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
    public func importScrivenerProject(from selectedURL: URL) throws -> ScrivenerImportResult {
        isImporting = true
        importSummary = nil
        defer { isImporting = false }

        let source = try scrivenerSource(from: selectedURL)
        let result = try ScrivenerImporter(store: store).importProject(
            xmlURL: source.xml,
            filesURL: source.files
        )
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
        saveAndRefresh(rebuild: false)
        return definition
    }

    public func renameSectionType(_ definition: SectionTypeDefinition, title: String) {
        definition.title = title
        definition.project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
    }

    public func deleteSectionType(_ definition: SectionTypeDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
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
        saveAndRefresh(rebuild: false)
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
        saveAndRefresh(rebuild: false)
    }

    public func deleteLabel(_ definition: LabelDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
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
        saveAndRefresh(rebuild: false)
        return definition
    }

    public func renameStatus(_ definition: StatusDefinition, title: String) {
        definition.title = title
        definition.project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
    }

    public func deleteStatus(_ definition: StatusDefinition) {
        let project = definition.project
        store.context.delete(definition)
        project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
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
        saveAndRefresh(rebuild: false)
        return field
    }

    public func updateCustomMetadataField(_ field: MetadataField, displayName: String, valueType: String) {
        field.displayName = displayName
        field.valueType = valueType
        field.project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
    }

    public func deleteCustomMetadataField(_ field: MetadataField) {
        let project = field.project
        store.context.delete(field)
        project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
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

    public func updateDocumentRichText(rtfData: Data, plainText: String) {
        guard let document = selectedDocument,
              let resource = document.resources.first(where: {
                  $0.role == "content" && $0.mediaType == "application/rtf"
              }) else {
            return
        }
        document.plainText = plainText
        document.modifiedAt = Date()
        document.project.modifiedAt = Date()
        resource.data = rtfData
        resource.textContent = plainText
        resource.byteCount = Int64(rtfData.count)
        resource.sha256 = SHA256.hash(data: rtfData).map { String(format: "%02x", $0) }.joined()
        saveAndRefresh(rebuild: false)
    }

    public func updateSemanticEntity(name: String, summary: String?) {
        guard let entity = selectedSemanticEntity else { return }
        entity.canonicalName = name
        entity.summary = summary?.nilIfBlank
        entity.modifiedAt = Date()
        entity.project.modifiedAt = Date()
        saveAndRefresh(rebuild: false)
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
        profile.modifiedAt = Date()
        profile.project.modifiedAt = Date()
        pendingCharacterSave?.cancel()
        pendingCharacterSave = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                try self.store.save()
                self.refresh()
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

    private func scrivenerSource(from selectedURL: URL) throws -> (xml: URL, files: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory)
        let directory = isDirectory.boolValue
            ? selectedURL
            : selectedURL.deletingLastPathComponent()
        let filesURL = directory.appendingPathComponent("Files", isDirectory: true)

        if !isDirectory.boolValue, selectedURL.pathExtension.lowercased() == "xml" {
            return (selectedURL, filesURL)
        }

        let xmlFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "xml" }

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
            selection = nil
            return
        }

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
        let roots = documents.filter { $0.parent == nil }.sorted(by: documentOrder)
        let storyBibleRoots = Dictionary(grouping: roots.compactMap { document in
            storyBibleCategory(for: document).map { ($0, document) }
        }, by: \.0)
        let narrativeRoots = roots.filter { storyBibleCategory(for: $0) == nil }
        let visibleNarrativeRoots: [Document]
        if narrativeRoots.count == 1,
           let root = narrativeRoots.first,
           root.sourceIdentifier.hasPrefix("native.narrative.") {
            visibleNarrativeRoots = root.orderedChildren
        } else {
            visibleNarrativeRoots = narrativeRoots
        }

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
                        .map(makeDocumentItem)
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
                id: "narrative",
                title: "Narrative",
                systemImage: "text.book.closed",
                selection: .narrative(project.id),
                kind: .narrative,
                children: visibleNarrativeRoots.map(makeDocumentItem)
            )
        ]
    }

    private func makeDocumentItem(_ document: Document) -> BinderItem {
        let profile = document.sourceCharacterProfiles.first
        return BinderItem(
            id: document.id.uuidString,
            title: document.title,
            systemImage: documentSystemImage(document),
            selection: profile.map { .characterProfile($0.id) } ?? .document(document.id),
            kind: profile == nil ? .document : .characterProfile,
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
