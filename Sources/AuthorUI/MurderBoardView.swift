import AuthorData
import SwiftUI

let murderBoardSectionTypeIdentifier = "storyBible.murderBoard"
private let murderBoardSourcePrefix = "native.murderBoard."
private let murderBoardMaximumVisibleNodes = 80

struct MurderBoardBookScopeCacheKey: Hashable {
    let projectID: UUID
    let projectModifiedAt: Date?
    let bookID: UUID
}

struct MurderBoardNodeState: Codable, Equatable, Identifiable {
    var entityID: UUID
    var x: Double
    var y: Double
    var isPinned: Bool = false
    var isHidden: Bool = false

    var id: UUID { entityID }
}

enum MurderBoardConnectedDepth: String, Codable, CaseIterable, Identifiable {
    case allVisible
    case direct
    case twoHops
    case allConnected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allVisible: "All Visible"
        case .direct: "Direct Relationships"
        case .twoHops: "Two Hops"
        case .allConnected: "All Connected"
        }
    }
}

enum MurderBoardLayoutMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }
}

struct MurderBoardViewportState: Codable, Equatable {
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
}

struct MurderBoardState: Codable, Equatable {
    var focusCategory: StoryBibleCategory?
    var destinationCategories: [StoryBibleCategory]?
    var includedEntityIDs: [UUID] = []
    var visibleEntityKinds: [String] = []
    var hiddenRelationshipKinds: [String] = []
    var selectedEntityID: UUID?
    var selectedBookID: UUID?
    var connectedDepth: MurderBoardConnectedDepth = .allVisible
    var includeDisconnectedEntities = true
    var layoutMode: MurderBoardLayoutMode = .automatic
    var viewport = MurderBoardViewportState()
    var nodeStates: [MurderBoardNodeState] = []

    func nodeState(for entityID: UUID) -> MurderBoardNodeState? {
        nodeStates.first { $0.entityID == entityID }
    }

    mutating func updateNodeState(_ entityID: UUID, mutate: (inout MurderBoardNodeState) -> Void) {
        if let index = nodeStates.firstIndex(where: { $0.entityID == entityID }) {
            mutate(&nodeStates[index])
        } else {
            var state = MurderBoardNodeState(entityID: entityID, x: 0, y: 0)
            mutate(&state)
            nodeStates.append(state)
        }
    }
}

struct MurderBoardGraphNode: Identifiable {
    let entity: SemanticEntity
    let position: CGPoint
    let isPinned: Bool
    let isHidden: Bool
    let mentionCount: Int

    var id: UUID { entity.id }
}

enum MurderBoardRelationshipRecord {
    case storyBible(StoryBibleRelationship)
    case character(CharacterRelationship)

    var id: UUID {
        switch self {
        case .storyBible(let relationship): relationship.id
        case .character(let relationship): relationship.id
        }
    }

    var kind: String {
        switch self {
        case .storyBible(let relationship): relationship.kind
        case .character(let relationship): relationship.kind
        }
    }

    var notes: String? {
        switch self {
        case .storyBible(let relationship): relationship.notes
        case .character(let relationship): relationship.notes
        }
    }

    var sourceEntity: SemanticEntity {
        switch self {
        case .storyBible(let relationship): relationship.sourceEntity
        case .character(let relationship): relationship.sourceCharacter.semanticEntity
        }
    }

    var targetEntity: SemanticEntity {
        switch self {
        case .storyBible(let relationship): relationship.targetEntity
        case .character(let relationship): relationship.targetCharacter.semanticEntity
        }
    }

    var sentence: String {
        "\(sourceEntity.canonicalName) \(kind) \(targetEntity.canonicalName)"
    }
}

extension StoryBibleCategory {
    static var murderBoardCategories: [Self] { allCases.filter { $0 != .research } }

    var murderBoardTitle: String { self == .people ? "Characters" : rawValue }
}

struct MurderBoardGraphEdge: Identifiable {
    let relationship: MurderBoardRelationshipRecord
    let sourceID: UUID
    let targetID: UUID
    let sourcePosition: CGPoint
    let targetPosition: CGPoint

    var id: UUID { relationship.id }
    var labelPosition: CGPoint {
        CGPoint(
            x: (sourcePosition.x + targetPosition.x) / 2,
            y: (sourcePosition.y + targetPosition.y) / 2
        )
    }
}

struct MurderBoardGraph {
    let nodes: [MurderBoardGraphNode]
    let edges: [MurderBoardGraphEdge]
    let availableRelationshipKinds: [String]
    let visibleEntityCount: Int
    let totalEntityCount: Int
    let isTruncated: Bool
    var connectionCounts: [StoryBibleCategory: Int] = [:]

    var totalConnectionCount: Int { connectionCounts.values.reduce(0, +) }
    var hiddenConnectionCount: Int { max(0, totalConnectionCount - edges.count) }
}

extension WorkspaceController {
    public var selectedMurderBoard: Document? {
        guard case .murderBoard(let id) = selection else { return nil }
        return try? store.documents.fetch(id: id)
    }

    public var murderBoards: [Document] {
        cachedMurderBoards
    }

    public var murderBoardBooks: [Document] {
        cachedMurderBoardBooks
    }

    public func isMurderBoardDocument(_ document: Document) -> Bool {
        document.sectionTypeIdentifier == murderBoardSectionTypeIdentifier
    }

    @discardableResult
    public func createMurderBoard(named name: String = "New Relationship Explorer") throws -> Document {
        guard let project = selectedProject else {
            throw WorkspaceError.missingProject(selectedProjectID ?? UUID())
        }
        let now = Date()
        let boardID = UUID()
        let board = store.documents.create {
            $0.id = boardID
            $0.sourceIdentifier = murderBoardSourcePrefix + boardID.uuidString
            $0.title = name.nilIfBlank ?? "New Relationship Explorer"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = (murderBoardDocuments(in: project).map(\.orderIndex).max() ?? -1) + 1
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
            $0.parent = nil
            $0.sectionTypeIdentifier = murderBoardSectionTypeIdentifier
            $0.plainText = encodeMurderBoardState(MurderBoardState())
            $0.synopsis = "Presentation-only relationship graph"
        }
        project.modifiedAt = now
        try store.save()
        selection = .murderBoard(board.id)
        refresh()
        return board
    }

    public func openMurderBoard(_ board: Document) {
        selection = .murderBoard(board.id)
        refresh()
    }

    public func renameMurderBoard(_ board: Document, title: String) {
        let normalized = title.nilIfBlank ?? "Untitled Board"
        guard board.title != normalized else { return }
        let now = Date()
        board.title = normalized
        board.modifiedAt = now
        board.project.modifiedAt = now
        do {
            try store.save()
            refresh()
        } catch {
            report(error)
        }
    }

    public func deleteMurderBoard(_ board: Document) {
        let projectID = board.project.id
        let boardID = board.id
        store.context.delete(board)
        do {
            try store.save()
            if case .murderBoard(let id) = selection, id == boardID {
                selection = .murderBoardOverview(projectID)
            }
            refresh()
        } catch {
            report(error)
        }
    }

    func murderBoardState(for board: Document) -> MurderBoardState {
        guard isMurderBoardDocument(board),
              let data = board.plainText?.data(using: .utf8),
              let state = try? JSONDecoder().decode(MurderBoardState.self, from: data) else {
            return MurderBoardState()
        }
        return state
    }

    func saveMurderBoardState(_ state: MurderBoardState, for board: Document) {
        guard isMurderBoardDocument(board) else { return }
        let encoded = encodeMurderBoardState(state)
        guard board.plainText != encoded else { return }
        let now = Date()
        board.plainText = encoded
        board.modifiedAt = now
        board.project.modifiedAt = now
        do {
            try store.save()
            objectWillChange.send()
        } catch {
            report(error)
        }
    }

    func murderBoardGraph(for board: Document, state: MurderBoardState) -> MurderBoardGraph {
        guard isMurderBoardDocument(board) else {
            return MurderBoardGraph(
                nodes: [],
                edges: [],
                availableRelationshipKinds: [],
                visibleEntityCount: 0,
                totalEntityCount: 0,
                isTruncated: false
            )
        }
        let project = board.project
        let allEntities = project.semanticEntities
            .filter { isStoryBibleEntityAvailable($0) }
            .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
        if let category = state.focusCategory {
            return focusedMurderBoardGraph(in: project, entities: allEntities, category: category, state: state)
        }
        let availableEntityKindValues = Set(allEntities.map(\.kind))
        let visibleKinds = state.visibleEntityKinds.isEmpty
            ? availableEntityKindValues
            : Set(state.visibleEntityKinds)
        let hiddenEntityIDs = Set(state.nodeStates.filter(\.isHidden).map(\.entityID))
        let selectedBook = state.selectedBookID.flatMap { id in project.documents.first { !$0.isDeleted && $0.id == id } }
        let bookScopedEntityIDs = selectedBook.map { cachedMurderBoardEntityIDs(in: $0, project: project) }

        var entities = allEntities.filter { entity in
            visibleKinds.contains(entity.kind) &&
                !hiddenEntityIDs.contains(entity.id) &&
                (bookScopedEntityIDs?.contains(entity.id) ?? true)
        }
        let baseVisibleEntityIDs = Set(entities.map(\.id))

        let allRelationships = graphRelationships(in: project)
        let availableRelationshipKinds = Array(Set(allRelationships.map(\.kind))).sorted()
        let hiddenRelationshipKinds = Set(state.hiddenRelationshipKinds)
        var relationships = allRelationships.filter { relationship in
            !hiddenRelationshipKinds.contains(relationship.kind) &&
                baseVisibleEntityIDs.contains(relationship.sourceEntity.id) &&
                baseVisibleEntityIDs.contains(relationship.targetEntity.id)
        }
        let globallyConnectedEntityIDs = Set(relationships.flatMap { [$0.sourceEntity.id, $0.targetEntity.id] })
        let scopedEntityIDs: Set<UUID>?

        if let selectedEntityID = state.selectedEntityID,
           state.connectedDepth != .allVisible {
            scopedEntityIDs = murderBoardVisibleEntityIDs(
                selectedEntityID: selectedEntityID,
                entities: entities,
                relationships: relationships,
                depth: state.connectedDepth
            )
        } else {
            scopedEntityIDs = nil
        }

        if let scopedEntityIDs {
            relationships = relationships.filter {
                scopedEntityIDs.contains($0.sourceEntity.id) && scopedEntityIDs.contains($0.targetEntity.id)
            }
            let disconnectedEntityIDs = baseVisibleEntityIDs.subtracting(globallyConnectedEntityIDs)
            let visibleEntityIDs = state.includeDisconnectedEntities
                ? scopedEntityIDs.union(disconnectedEntityIDs)
                : scopedEntityIDs
            entities = entities.filter { visibleEntityIDs.contains($0.id) }
        } else if !state.includeDisconnectedEntities {
            let connectedIDs = globallyConnectedEntityIDs
                .union(state.selectedEntityID.map { [$0] } ?? [])
            entities = entities.filter { connectedIDs.contains($0.id) }
        }

        var isTruncated = false
        if state.connectedDepth == .allVisible,
           state.selectedBookID == nil,
           entities.count > murderBoardMaximumVisibleNodes {
            var prioritizedIDs = uniqueEntityIDs(from: relationships)
            if let selectedEntityID = state.selectedEntityID {
                prioritizedIDs.removeAll { $0 == selectedEntityID }
                prioritizedIDs.insert(selectedEntityID, at: 0)
            }
            let remainingIDs = entities.map(\.id).filter { !prioritizedIDs.contains($0) }
            let keptIDs = Array((prioritizedIDs + remainingIDs).prefix(murderBoardMaximumVisibleNodes))
            let keptIDSet = Set(keptIDs)
            entities = entities.filter { keptIDSet.contains($0.id) }
            isTruncated = true
        }

        let finalEntityIDs = Set(entities.map(\.id))
        relationships = relationships.filter {
            finalEntityIDs.contains($0.sourceEntity.id) && finalEntityIDs.contains($0.targetEntity.id)
        }

        let defaultPositions = murderBoardAutomaticPositions(for: entities.map(\.id))
        let mentionCounts = murderBoardSceneMentionCounts(in: project)
        let nodes = entities.map { entity in
            let saved = state.nodeState(for: entity.id)
            return MurderBoardGraphNode(
                entity: entity,
                position: CGPoint(
                    x: saved?.x ?? defaultPositions[entity.id]?.x ?? 0,
                    y: saved?.y ?? defaultPositions[entity.id]?.y ?? 0
                ),
                isPinned: saved?.isPinned ?? false,
                isHidden: saved?.isHidden ?? false,
                mentionCount: mentionCounts[entity.id, default: 0]
            )
        }
        let positionLookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let edges = relationships.compactMap { relationship -> MurderBoardGraphEdge? in
            guard let sourcePosition = positionLookup[relationship.sourceEntity.id],
                  let targetPosition = positionLookup[relationship.targetEntity.id] else {
                return nil
            }
            return MurderBoardGraphEdge(
                relationship: relationship,
                sourceID: relationship.sourceEntity.id,
                targetID: relationship.targetEntity.id,
                sourcePosition: sourcePosition,
                targetPosition: targetPosition
            )
        }

        return MurderBoardGraph(
            nodes: nodes,
            edges: edges,
            availableRelationshipKinds: availableRelationshipKinds,
            visibleEntityCount: nodes.count,
            totalEntityCount: allEntities.count,
            isTruncated: isTruncated
        )
    }

    func focusedMurderBoardState(_ saved: MurderBoardState, in project: WritingProject) -> MurderBoardState {
        var state = saved
        let entities = project.semanticEntities.filter { isStoryBibleEntityAvailable($0) }
            .sorted { ($0.canonicalName, $0.id.uuidString) < ($1.canonicalName, $1.id.uuidString) }
        let selected = entities.first { $0.id == state.selectedEntityID }
        let category = state.focusCategory
            ?? selected.flatMap { entity in StoryBibleCategory.murderBoardCategories.first { $0.contains(kind: entity.kind) } }
            ?? .people
        state.focusCategory = category
        if selected == nil || !category.contains(kind: selected?.kind ?? "") {
            state.selectedEntityID = entities.first { category.contains(kind: $0.kind) }?.id
        }
        if state.destinationCategories == nil {
            let legacyCategories = StoryBibleCategory.murderBoardCategories.filter { category in
                state.visibleEntityKinds.contains { category.contains(kind: $0) }
            }
            let connections = state.selectedEntityID.map { murderBoardConnections(for: $0, in: project) } ?? []
            let connectedCategories = StoryBibleCategory.murderBoardCategories.filter { category in
                connections.contains { relationship in
                    let other = relationship.sourceEntity.id == state.selectedEntityID
                        ? relationship.targetEntity : relationship.sourceEntity
                    return category.contains(kind: other.kind)
                }
            }
            state.destinationCategories = !legacyCategories.isEmpty ? legacyCategories
                : !connectedCategories.isEmpty ? connectedCategories
                : category == .people ? [.artifacts, .places] : [.people]
        }
        return state
    }

    private func focusedMurderBoardGraph(
        in project: WritingProject,
        entities: [SemanticEntity],
        category: StoryBibleCategory,
        state: MurderBoardState
    ) -> MurderBoardGraph {
        let focus = entities.first { $0.id == state.selectedEntityID && category.contains(kind: $0.kind) }
        let destinations = state.destinationCategories ?? [.artifacts]
        let connections = focus.map { murderBoardConnections(for: $0.id, in: project) } ?? []
        var connectionCounts: [StoryBibleCategory: Int] = [:]
        let relationships = connections.filter { relationship in
            let other = relationship.sourceEntity.id == focus?.id ? relationship.targetEntity : relationship.sourceEntity
            if let category = StoryBibleCategory.murderBoardCategories.first(where: { $0.contains(kind: other.kind) }) {
                connectionCounts[category, default: 0] += 1
            }
            return destinations.contains { $0.contains(kind: other.kind) }
        }
        let visibleIDs = Set(relationships.flatMap { [$0.sourceEntity.id, $0.targetEntity.id] })
            .union(focus.map { [$0.id] } ?? [])
        let nodes = entities.filter { visibleIDs.contains($0.id) }.map {
            MurderBoardGraphNode(entity: $0, position: .zero, isPinned: false, isHidden: false, mentionCount: 0)
        }
        let edges = relationships.map {
            MurderBoardGraphEdge(
                relationship: $0,
                sourceID: $0.sourceEntity.id,
                targetID: $0.targetEntity.id,
                sourcePosition: .zero,
                targetPosition: .zero
            )
        }
        return MurderBoardGraph(
            nodes: nodes,
            edges: edges,
            availableRelationshipKinds: Array(Set(relationships.map(\.kind))).sorted(),
            visibleEntityCount: nodes.count,
            totalEntityCount: entities.count,
            isTruncated: false,
            connectionCounts: connectionCounts
        )
    }

    private func murderBoardConnections(for entityID: UUID, in project: WritingProject) -> [MurderBoardRelationshipRecord] {
        graphRelationships(in: project).filter {
            ($0.sourceEntity.id == entityID || $0.targetEntity.id == entityID)
                && $0.sourceEntity.id != $0.targetEntity.id
        }
    }

    private func murderBoardDocuments(in project: WritingProject) -> [Document] {
        project.documents
            .filter { !$0.isDeleted && !isDocumentTrashed($0) && isMurderBoardDocument($0) }
            .sorted { ($0.orderIndex, $0.title, $0.id.uuidString) < ($1.orderIndex, $1.title, $1.id.uuidString) }
    }

    private func encodeMurderBoardState(_ state: MurderBoardState) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = (try? encoder.encode(state)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func graphRelationships(in project: WritingProject) -> [MurderBoardRelationshipRecord] {
        var storyBibleSeen = Set<UUID>()
        let storyBibleRelationships = project.semanticEntities
            .flatMap(\.outgoingStoryBibleRelationships)
            .filter {
                !$0.isDeleted &&
                    isStoryBibleEntityAvailable($0.sourceEntity) &&
                    isStoryBibleEntityAvailable($0.targetEntity) &&
                    storyBibleSeen.insert($0.id).inserted
            }
            .map(MurderBoardRelationshipRecord.storyBible)

        var characterSeen = Set<UUID>()
        let characterRelationships = project.characterProfiles
            .flatMap(\.outgoingRelationships)
            .filter {
                !$0.isDeleted &&
                    !$0.sourceCharacter.isDeleted &&
                    !$0.targetCharacter.isDeleted &&
                    !$0.sourceCharacter.semanticEntity.isDeleted &&
                    !$0.targetCharacter.semanticEntity.isDeleted &&
                    characterSeen.insert($0.id).inserted
            }
            .map(MurderBoardRelationshipRecord.character)

        return (storyBibleRelationships + characterRelationships).sorted {
            ($0.kind, $0.sourceEntity.canonicalName, $0.targetEntity.canonicalName, $0.id.uuidString) <
                ($1.kind, $1.sourceEntity.canonicalName, $1.targetEntity.canonicalName, $1.id.uuidString)
        }
    }

    private func murderBoardSceneMentionCounts(in project: WritingProject) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: project.semanticEntities.map { entity in
                let count = entity.mentions.filter {
                    !$0.isDeleted &&
                        !$0.document.isDeleted &&
                        $0.document.project.id == entity.project.id &&
                        !isDocumentTrashed($0.document) &&
                        $0.document.narrativeType == NarrativeType.scene.rawValue &&
                        $0.source.hasPrefix("storyBible.entityReference.")
                }.count
                return (entity.id, count)
            }
        )
    }

    private func murderBoardEntityIDs(in book: Document, project: WritingProject) -> Set<UUID> {
        let sceneDocuments: [Document] = Array(project.documents).compactMap { document -> Document? in
            guard !document.isDeleted,
                  !isDocumentTrashed(document),
                  document.narrativeType == NarrativeType.scene.rawValue,
                  murderBoardContains(document, in: book) else {
                return nil
            }
            return document
        }
        let mentionedEntityIDs: Set<UUID> = Set(sceneDocuments.flatMap { document in
            document.mentions.compactMap { mention in
                guard !mention.isDeleted,
                      mention.source.hasPrefix("storyBible.entityReference."),
                      !mention.semanticEntity.isDeleted else {
                    return nil
                }
                return mention.semanticEntity.id
            }
        })
        let sourceBackedEntityIDs: Set<UUID> = Set(Array(project.characterProfiles).compactMap { profile in
            guard !profile.isDeleted,
                  !profile.semanticEntity.isDeleted,
                  let sourceDocument = profile.sourceDocument,
                  !sourceDocument.isDeleted,
                  !isDocumentTrashed(sourceDocument),
                  murderBoardContains(sourceDocument, in: book) else {
                return nil
            }
            return profile.semanticEntity.id
        })
        let scopedEntitySeeds = mentionedEntityIDs.union(sourceBackedEntityIDs)
        let relationshipEntityIDs = Set(graphRelationships(in: project).flatMap { relationship in
            let endpointIDs = [relationship.sourceEntity.id, relationship.targetEntity.id]
            return endpointIDs.contains(where: scopedEntitySeeds.contains) ? endpointIDs : []
        })
        return scopedEntitySeeds.union(relationshipEntityIDs)
    }

    private func cachedMurderBoardEntityIDs(in book: Document, project: WritingProject) -> Set<UUID> {
        let key = MurderBoardBookScopeCacheKey(
            projectID: project.id,
            projectModifiedAt: project.modifiedAt,
            bookID: book.id
        )
        if let cached = murderBoardBookScopedEntityCache[key] {
            return cached
        }
        let entityIDs = murderBoardEntityIDs(in: book, project: project)
        murderBoardBookScopedEntityCache[key] = entityIDs
        return entityIDs
    }

    private func murderBoardContains(_ document: Document, in book: Document) -> Bool {
        document.id == book.id || document.ancestors.contains(where: { $0.id == book.id })
    }

    private func murderBoardVisibleEntityIDs(
        selectedEntityID: UUID,
        entities: [SemanticEntity],
        relationships: [MurderBoardRelationshipRecord],
        depth: MurderBoardConnectedDepth
    ) -> Set<UUID> {
        let allowedIDs = Set(entities.map(\.id))
        guard allowedIDs.contains(selectedEntityID) else { return allowedIDs }
        var adjacency: [UUID: Set<UUID>] = [:]
        for relationship in relationships {
            adjacency[relationship.sourceEntity.id, default: []].insert(relationship.targetEntity.id)
            adjacency[relationship.targetEntity.id, default: []].insert(relationship.sourceEntity.id)
        }
        switch depth {
        case .allVisible:
            return allowedIDs
        case .direct:
            return adjacency[selectedEntityID, default: []].union([selectedEntityID])
        case .twoHops:
            var visited: Set<UUID> = [selectedEntityID]
            var frontier: Set<UUID> = [selectedEntityID]
            for _ in 0..<2 {
                let next = frontier.flatMap { adjacency[$0] ?? [] }
                frontier = Set(next).subtracting(visited)
                visited.formUnion(frontier)
            }
            return visited
        case .allConnected:
            var visited: Set<UUID> = [selectedEntityID]
            var frontier: Set<UUID> = [selectedEntityID]
            while !frontier.isEmpty {
                let next = Set(frontier.flatMap { adjacency[$0] ?? [] }).subtracting(visited)
                visited.formUnion(next)
                frontier = next
            }
            return visited
        }
    }

    private func uniqueEntityIDs(from relationships: [MurderBoardRelationshipRecord]) -> [UUID] {
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for relationship in relationships {
            for id in [relationship.sourceEntity.id, relationship.targetEntity.id] where seen.insert(id).inserted {
                ids.append(id)
            }
        }
        return ids
    }
}

struct MurderBoardOverviewView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var showsNewBoard = false
    @State private var newBoardName = ""

    var body: some View {
        List {
            Section {
                Text("Choose a Story Bible category and an entity to focus on, then explore its saved connections to other categories.")
                    .foregroundStyle(.secondary)
                Button {
                    showsNewBoard = true
                } label: {
                    Label("New Relationship Explorer", systemImage: "plus.circle")
                }
            }

            Section("Saved Boards") {
                if controller.murderBoards.isEmpty {
                    Text("No boards yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.murderBoards, id: \.id) { board in
                        HStack {
                            Button {
                                controller.openMurderBoard(board)
                            } label: {
                                Label(board.title, systemImage: "circle.hexagongrid")
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) {
                                controller.deleteMurderBoard(board)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete board")
                        }
                    }
                }
            }
        }
        .navigationTitle("Relationship Explorer")
        .sheet(isPresented: $showsNewBoard) {
            NavigationStack {
                Form {
                    TextField("Board name", text: $newBoardName)
                }
                .navigationTitle("New Relationship Explorer")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            newBoardName = ""
                            showsNewBoard = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            do {
                                let name = newBoardName.nilIfBlank ?? "New Relationship Explorer"
                                _ = try controller.createMurderBoard(named: name)
                                newBoardName = ""
                                showsNewBoard = false
                            } catch {
                                controller.report(error)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MurderBoardView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var state = MurderBoardState()
    @State private var selectedRelationshipID: UUID?
    @State private var showsRelationshipInspector = false
    @State private var showsNewRelationship = false
    @State private var relationshipKindDraft = ""
    @State private var relationshipNotesDraft = ""
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var pendingRelationshipSaveTask: Task<Void, Never>?
    @State private var pendingTitleSaveTask: Task<Void, Never>?
    @State private var loadedBoardID: UUID?
    @State private var boardTitleDraft = ""

    var body: some View {
        if let board = controller.selectedMurderBoard {
            let graph = controller.murderBoardGraph(for: board, state: state)
            VStack(spacing: 0) {
                controls(board: board, graph: graph)
                Divider()
                focusedConnections(board: board, graph: graph)
            }
                .onAppear {
                    switchBoard(to: board)
                }
                .onChange(of: board.id) { _, _ in
                    switchBoard(to: board)
                }
                .onChange(of: selectedRelationshipID) { _, _ in
                    syncRelationshipDrafts(graph: graph)
                }
                .onDisappear {
                    if !board.isDeleted, board.managedObjectContext != nil {
                        persistTitleImmediately(for: board)
                        persistState(for: board)
                    }
                }
            .navigationTitle(board.title)
            .sheet(isPresented: $showsNewRelationship) {
                if let node = selectedNode {
                    StoryBibleRelationshipComposer(controller: controller, source: node.entity) { target in
                        if let category = StoryBibleCategory.murderBoardCategories.first(where: { $0.contains(kind: target.kind) }),
                           !destinationCategories.contains(category) {
                            state.destinationCategories = destinationCategories + [category]
                        }
                        schedulePersist(for: board)
                    }
                }
            }
            .sheet(isPresented: $showsRelationshipInspector, onDismiss: {
                persistRelationshipDraftImmediately()
                selectedRelationshipID = nil
            }) {
                NavigationStack {
                    inspector(graph: graph)
                        .formStyle(.grouped)
                        .navigationTitle("Relationship")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    persistRelationshipDraftImmediately()
                                    showsRelationshipInspector = false
                                }
                            }
                        }
                }
                .frame(minWidth: 360, minHeight: 360)
            }
        } else {
            Text("Select a Relationship Explorer.")
                .foregroundStyle(.secondary)
        }
    }

    private func controls(board: Document, graph: MurderBoardGraph) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField(
                    "Board Name",
                    text: $boardTitleDraft
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: boardTitleDraft) { _, _ in
                    scheduleTitlePersist(for: board)
                }
                .onSubmit {
                    persistTitleImmediately(for: board)
                }

                Button {
                    showsNewRelationship = true
                } label: {
                    Label("Add Relationship", systemImage: "link.badge.plus")
                }
                .disabled(selectedNode == nil)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    focusCategoryPicker(board: board)
                    focusEntityPicker(board: board)
                }
                VStack(alignment: .leading, spacing: 12) {
                    focusCategoryPicker(board: board)
                    focusEntityPicker(board: board)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Show connections to")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StoryBibleCategory.murderBoardCategories) { category in
                            let isSelected = destinationCategories.contains(category)
                            Button {
                                toggleDestinationCategory(category, board: board)
                            } label: {
                                Label("\(category.murderBoardTitle) (\(graph.connectionCounts[category, default: 0]))", systemImage: category.systemImage)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07),
                                        in: Capsule()
                                    )
                                    .overlay(Capsule().stroke(
                                        isSelected ? Color.accentColor : Color.clear, lineWidth: 1
                                    ))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func focusCategoryPicker(board: Document) -> some View {
        Picker("Start with", selection: Binding(
            get: { state.focusCategory ?? .people },
            set: { category in
                persistRelationshipDraftImmediately()
                state.focusCategory = category
                state.selectedEntityID = nil
                state.destinationCategories = nil
                state.visibleEntityKinds = []
                state = controller.focusedMurderBoardState(state, in: board.project)
                selectedRelationshipID = nil
                schedulePersist(for: board)
            }
        )) {
            ForEach(StoryBibleCategory.murderBoardCategories) { category in
                Text(category.murderBoardTitle).tag(category)
            }
        }
        .frame(maxWidth: 300)
    }

    private func focusEntityPicker(board: Document) -> some View {
        Picker("Focus on", selection: Binding(
            get: { state.selectedEntityID },
            set: {
                persistRelationshipDraftImmediately()
                state.selectedEntityID = $0
                if $0 != nil {
                    state.destinationCategories = nil
                    state.visibleEntityKinds = []
                    state = controller.focusedMurderBoardState(state, in: board.project)
                }
                selectedRelationshipID = nil
                schedulePersist(for: board)
            }
        )) {
            Text("Choose an entry").tag(Optional<UUID>.none)
            ForEach(startingEntities(in: board.project), id: \.id) { entity in
                Text(entity.canonicalName).tag(Optional(entity.id))
            }
        }
        .frame(maxWidth: 360)
    }

    private var destinationCategories: [StoryBibleCategory] {
        let selected = state.destinationCategories ?? [.artifacts]
        return StoryBibleCategory.murderBoardCategories.filter { selected.contains($0) }
    }

    private func focusedConnections(board: Document, graph: MurderBoardGraph) -> some View {
        VStack(spacing: 0) {
            if let focusID = state.selectedEntityID, graph.nodes.contains(where: { $0.id == focusID }) {
                HStack(spacing: 12) {
                    Text("Showing \(graph.edges.count) of \(graph.totalConnectionCount) saved connections")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if graph.hiddenConnectionCount > 0 {
                        Button("Show all \(graph.totalConnectionCount) connections") {
                            state.destinationCategories = StoryBibleCategory.murderBoardCategories.filter {
                                graph.connectionCounts[$0, default: 0] > 0
                            }
                            schedulePersist(for: board)
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                MurderBoardDiagram(
                    graph: graph,
                    focusID: focusID,
                    categories: destinationCategories,
                    selectRelationship: { edge in
                        persistRelationshipDraftImmediately()
                        selectedRelationshipID = edge.id
                        syncRelationshipDrafts(graph: graph)
                        showsRelationshipInspector = true
                    },
                    openEntity: { controller.openStoryBibleCard(for: $0) },
                    focusEntity: { entity in
                        persistRelationshipDraftImmediately()
                        state.focusCategory = StoryBibleCategory.murderBoardCategories.first { $0.contains(kind: entity.kind) }
                        state.selectedEntityID = entity.id
                        state.destinationCategories = nil
                        state.visibleEntityKinds = []
                        state = controller.focusedMurderBoardState(state, in: board.project)
                        selectedRelationshipID = nil
                        schedulePersist(for: board)
                    }
                )
            } else {
                ContentUnavailableView(
                    "Choose your focus",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(
                        startingEntities(in: board.project).isEmpty
                            ? "There are no entries in this category yet. Add one in the Story Bible or choose another category."
                            : "Choose a Story Bible entry above to explore its saved relationships."
                    )
                )
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.04))
    }

    private func inspector(graph: MurderBoardGraph) -> some View {
        Form {
            if let relationship = selectedRelationship(graph: graph) {
                Section("Selected Relationship") {
                    LabeledContent("Source", value: relationship.sourceEntity.canonicalName)
                    LabeledContent("Target", value: relationship.targetEntity.canonicalName)
                    TextField(
                        "Relationship",
                        text: Binding(
                            get: { relationshipKindDraft },
                            set: {
                                relationshipKindDraft = $0
                                scheduleRelationshipPersist()
                            }
                        )
                    )
                    TextField(
                        "Notes",
                        text: Binding(
                            get: { relationshipNotesDraft },
                            set: {
                                relationshipNotesDraft = $0
                                scheduleRelationshipPersist()
                            }
                        ),
                        axis: .vertical
                    )
                    Button("Open Source") {
                        controller.openStoryBibleCard(for: relationship.sourceEntity)
                    }
                    Button("Open Target") {
                        controller.openStoryBibleCard(for: relationship.targetEntity)
                    }
                    Button("Delete Relationship", role: .destructive) {
                        pendingRelationshipSaveTask?.cancel()
                        switch relationship {
                        case .storyBible(let storyBibleRelationship):
                            controller.deleteStoryBibleRelationship(storyBibleRelationship)
                        case .character(let characterRelationship):
                            controller.deleteCharacterRelationship(characterRelationship)
                        }
                        selectedRelationshipID = nil
                        relationshipKindDraft = ""
                        relationshipNotesDraft = ""
                        showsRelationshipInspector = false
                    }
                }
            } else {
                Text("This relationship is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedNode: MurderBoardGraphNode? {
        guard let board = controller.selectedMurderBoard else { return nil }
        let graph = controller.murderBoardGraph(for: board, state: state)
        return graph.nodes.first { $0.id == state.selectedEntityID }
    }

    private func storyBibleEntities(in project: WritingProject) -> [SemanticEntity] {
        project.semanticEntities
            .filter { controller.isStoryBibleEntityAvailable($0) }
            .sorted {
                $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
            }
    }

    private func startingEntities(in project: WritingProject) -> [SemanticEntity] {
        storyBibleEntities(in: project).filter { (state.focusCategory ?? .people).contains(kind: $0.kind) }
    }

    private func selectedRelationship(graph: MurderBoardGraph) -> MurderBoardRelationshipRecord? {
        graph.edges.first { $0.id == selectedRelationshipID }?.relationship
    }

    private func loadState(from board: Document) {
        pendingTitleSaveTask?.cancel()
        persistRelationshipDraftImmediately()
        pendingSaveTask?.cancel()
        state = controller.focusedMurderBoardState(controller.murderBoardState(for: board), in: board.project)
        selectedRelationshipID = nil
        relationshipKindDraft = ""
        relationshipNotesDraft = ""
        loadedBoardID = board.id
        boardTitleDraft = board.title
        controller.saveMurderBoardState(state, for: board)
    }

    private func toggleDestinationCategory(_ category: StoryBibleCategory, board: Document) {
        var categories = destinationCategories
        if categories.contains(category) {
            categories.removeAll { $0 == category }
        } else {
            categories.append(category)
        }
        state.destinationCategories = categories
        schedulePersist(for: board)
    }

    private func switchBoard(to board: Document) {
        if let loadedBoardID,
           loadedBoardID != board.id,
           let previousBoard = try? controller.store.documents.fetch(id: loadedBoardID) {
            persistTitleImmediately(for: previousBoard)
            persistState(for: previousBoard)
        }
        loadState(from: board)
    }

    private func schedulePersist(for board: Document) {
        pendingSaveTask?.cancel()
        let boardID = board.id
        let stateSnapshot = state
        pendingSaveTask = Task { @MainActor in
            defer { pendingSaveTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let persistedBoard = try? controller.store.documents.fetch(id: boardID) else { return }
            guard !Task.isCancelled, loadedBoardID == boardID else { return }
            persistRelationshipDraftImmediately()
            controller.saveMurderBoardState(stateSnapshot, for: persistedBoard)
        }
    }

    private func persistState(for board: Document) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        persistRelationshipDraftImmediately()
        guard let persistedBoard = try? controller.store.documents.fetch(id: board.id) else { return }
        controller.saveMurderBoardState(state, for: persistedBoard)
    }

    private func scheduleTitlePersist(for board: Document) {
        pendingTitleSaveTask?.cancel()
        let boardID = board.id
        let title = boardTitleDraft
        pendingTitleSaveTask = Task { @MainActor in
            defer { pendingTitleSaveTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, loadedBoardID == boardID else { return }
            guard let persistedBoard = try? controller.store.documents.fetch(id: boardID) else { return }
            controller.renameMurderBoard(persistedBoard, title: title)
        }
    }

    private func persistTitleImmediately(for board: Document) {
        pendingTitleSaveTask?.cancel()
        pendingTitleSaveTask = nil
        guard let persistedBoard = try? controller.store.documents.fetch(id: board.id) else { return }
        controller.renameMurderBoard(persistedBoard, title: boardTitleDraft)
    }

    private func syncRelationshipDrafts(graph: MurderBoardGraph) {
        guard let relationship = selectedRelationship(graph: graph) else {
            relationshipKindDraft = ""
            relationshipNotesDraft = ""
            return
        }
        relationshipKindDraft = relationship.kind
        relationshipNotesDraft = relationship.notes ?? ""
    }

    private func scheduleRelationshipPersist() {
        pendingRelationshipSaveTask?.cancel()
        guard let relationshipID = selectedRelationshipID,
              let boardID = loadedBoardID else { return }
        let kind = relationshipKindDraft
        let notes = relationshipNotesDraft.nilIfBlank
        pendingRelationshipSaveTask = Task { @MainActor in
            defer { pendingRelationshipSaveTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard loadedBoardID == boardID, selectedRelationshipID == relationshipID else { return }
            persistRelationshipDraft(id: relationshipID, kind: kind, notes: notes)
        }
    }

    private func persistRelationshipDraftImmediately() {
        pendingRelationshipSaveTask?.cancel()
        pendingRelationshipSaveTask = nil
        guard let relationshipID = selectedRelationshipID else { return }
        persistRelationshipDraft(id: relationshipID, kind: relationshipKindDraft, notes: relationshipNotesDraft.nilIfBlank)
    }

    private func persistRelationshipDraft(id: UUID, kind: String, notes: String?) {
        if let relationship = try? controller.store.storyBibleRelationships.fetch(id: id) {
            guard let normalizedKind = kind.nilIfBlank else {
                relationshipKindDraft = relationship.kind
                relationshipNotesDraft = relationship.notes ?? ""
                return
            }
            relationship.kind = normalizedKind
            relationship.notes = notes
            controller.saveStoryBibleRelationship(relationship)
            return
        }
        guard let relationship = try? controller.store.characterRelationships.fetch(id: id) else { return }
        guard let normalizedKind = kind.nilIfBlank else {
            relationshipKindDraft = relationship.kind
            relationshipNotesDraft = relationship.notes ?? ""
            return
        }
        relationship.kind = normalizedKind
        relationship.notes = notes
        controller.saveCharacterRelationship(relationship)
    }
}

private func murderBoardAutomaticPositions(for entityIDs: [UUID]) -> [UUID: CGPoint] {
    guard !entityIDs.isEmpty else { return [:] }
    if entityIDs.count == 1, let id = entityIDs.first {
        return [id: .zero]
    }
    let radius = max(180.0, Double(entityIDs.count) * 24.0)
    return Dictionary(uniqueKeysWithValues: entityIDs.enumerated().map { index, id in
        let angle = Double(index) / Double(entityIDs.count) * Double.pi * 2
        let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        return (id, point)
    })
}
