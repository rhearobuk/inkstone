import AuthorData
import SwiftUI

private let murderBoardSectionTypeIdentifier = "storyBible.murderBoard"
private let murderBoardSourcePrefix = "native.murderBoard."
private let murderBoardCanvasPadding: CGFloat = 120
private let murderBoardMaximumVisibleNodes = 80

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

struct MurderBoardGraphEdge: Identifiable {
    let relationship: StoryBibleRelationship
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
}

extension WorkspaceController {
    public var selectedMurderBoard: Document? {
        guard case .murderBoard(let id) = selection else { return nil }
        return try? store.documents.fetch(id: id)
    }

    public var murderBoards: [Document] {
        guard let project = selectedProject else { return [] }
        return murderBoardDocuments(in: project)
    }

    public var murderBoardBooks: [Document] {
        guard let project = selectedProject else { return [] }
        return project.documents
            .filter {
                !$0.isDeleted &&
                    !isDocumentTrashed($0) &&
                    $0.narrativeType == NarrativeType.book.rawValue
            }
            .sorted { ($0.orderIndex, $0.title, $0.id.uuidString) < ($1.orderIndex, $1.title, $1.id.uuidString) }
    }

    public func isMurderBoardDocument(_ document: Document) -> Bool {
        document.parent == nil && document.sectionTypeIdentifier == murderBoardSectionTypeIdentifier
    }

    @discardableResult
    public func createMurderBoard(named name: String = "New Murder Board") throws -> Document {
        guard let project = selectedProject else {
            throw WorkspaceError.missingProject(selectedProjectID ?? UUID())
        }
        let now = Date()
        let boardID = UUID()
        let board = store.documents.create {
            $0.id = boardID
            $0.sourceIdentifier = murderBoardSourcePrefix + boardID.uuidString
            $0.title = name.nilIfBlank ?? "New Murder Board"
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
        board.title = normalized
        board.modifiedAt = Date()
        board.project.modifiedAt = board.modifiedAt ?? Date()
        do {
            try store.save()
            refresh()
        } catch {
            report(error)
        }
    }

    public func deleteMurderBoard(_ board: Document) {
        let projectID = board.project.id
        store.context.delete(board)
        do {
            try store.save()
            if case .murderBoard(let id) = selection, id == board.id {
                selection = .murderBoardOverview(projectID)
            }
            refresh()
        } catch {
            report(error)
        }
    }

    public func murderBoardState(for board: Document) -> MurderBoardState {
        guard isMurderBoardDocument(board),
              let data = board.plainText?.data(using: .utf8),
              let state = try? JSONDecoder().decode(MurderBoardState.self, from: data) else {
            return MurderBoardState()
        }
        return state
    }

    public func saveMurderBoardState(_ state: MurderBoardState, for board: Document) {
        guard isMurderBoardDocument(board) else { return }
        let encoded = encodeMurderBoardState(state)
        if board.plainText != encoded {
            board.plainText = encoded
            board.modifiedAt = Date()
            board.project.modifiedAt = board.modifiedAt ?? Date()
        }
        do {
            try store.save()
            objectWillChange.send()
            lastError = nil
        } catch {
            report(error)
        }
    }

    public func murderBoardGraph(for board: Document, state: MurderBoardState) -> MurderBoardGraph {
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
            .filter { !$0.isDeleted }
            .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
        let visibleKinds = state.visibleEntityKinds.isEmpty
            ? Set(SemanticEntityKind.allCases.map(\.rawValue))
            : Set(state.visibleEntityKinds)
        let includedEntityIDs = state.includedEntityIDs.isEmpty ? nil : Set(state.includedEntityIDs)
        let hiddenEntityIDs = Set(state.nodeStates.filter(\.isHidden).map(\.entityID))
        let selectedBook = state.selectedBookID.flatMap { id in project.documents.first { !$0.isDeleted && $0.id == id } }
        let bookScopedEntityIDs = selectedBook.map { murderBoardEntityIDs(in: $0, project: project) }

        var entities = allEntities.filter { entity in
            visibleKinds.contains(entity.kind) &&
                !hiddenEntityIDs.contains(entity.id) &&
                (includedEntityIDs?.contains(entity.id) ?? true) &&
                (bookScopedEntityIDs?.contains(entity.id) ?? true)
        }

        let allRelationships = uniqueRelationships(in: project)
        let availableRelationshipKinds = Array(Set(allRelationships.map(\.kind))).sorted()
        let hiddenRelationshipKinds = Set(state.hiddenRelationshipKinds)
        var relationships = allRelationships.filter { relationship in
            !hiddenRelationshipKinds.contains(relationship.kind)
        }
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

        let visibleEntityIDs = scopedEntityIDs ?? Set(entities.map(\.id))
        relationships = relationships.filter {
            visibleEntityIDs.contains($0.sourceEntity.id) && visibleEntityIDs.contains($0.targetEntity.id)
        }

        if !state.includeDisconnectedEntities {
            let connectedIDs = Set(relationships.flatMap { [$0.sourceEntity.id, $0.targetEntity.id] })
                .union(state.selectedEntityID.map { [$0] } ?? [])
            let allowedConnectedIDs = connectedIDs.intersection(visibleEntityIDs)
            entities = entities.filter { allowedConnectedIDs.contains($0.id) }
        }

        var isTruncated = false
        if state.connectedDepth == .allVisible,
           state.selectedBookID == nil,
           entities.count > murderBoardMaximumVisibleNodes {
            let prioritizedIDs = uniqueEntityIDs(from: relationships)
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
                mentionCount: murderBoardSceneMentionCount(for: entity)
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

    private func uniqueRelationships(in project: WritingProject) -> [StoryBibleRelationship] {
        var seen = Set<UUID>()
        return project.semanticEntities
            .flatMap(\.outgoingStoryBibleRelationships)
            .filter {
                !$0.isDeleted &&
                    !$0.sourceEntity.isDeleted &&
                    !$0.targetEntity.isDeleted &&
                    seen.insert($0.id).inserted
            }
            .sorted {
                ($0.kind, $0.sourceEntity.canonicalName, $0.targetEntity.canonicalName, $0.id.uuidString) <
                    ($1.kind, $1.sourceEntity.canonicalName, $1.targetEntity.canonicalName, $1.id.uuidString)
            }
    }

    private func murderBoardSceneMentionCount(for entity: SemanticEntity) -> Int {
        entity.mentions.filter {
            !$0.isDeleted &&
                !$0.document.isDeleted &&
                !isDocumentTrashed($0.document) &&
                $0.document.narrativeType == NarrativeType.scene.rawValue &&
            $0.source.hasPrefix("storyBible.entityReference.")
        }.count
    }

    private func murderBoardEntityIDs(in book: Document, project: WritingProject) -> Set<UUID> {
        let mentionedEntityIDs = Set(project.semanticEntities.compactMap { entity in
            entity.mentions.contains { mention in
                !mention.document.isDeleted &&
                    !isDocumentTrashed(mention.document) &&
                    mention.document.narrativeType == NarrativeType.scene.rawValue &&
                    mention.source.hasPrefix("storyBible.entityReference.") &&
                    murderBoardContains(mention.document, in: book)
            } ? entity.id : nil
        })
        let relationshipEntityIDs = Set(uniqueRelationships(in: project).flatMap { relationship in
            let endpointIDs = [relationship.sourceEntity.id, relationship.targetEntity.id]
            return endpointIDs.contains(where: mentionedEntityIDs.contains) ? endpointIDs : []
        })
        return mentionedEntityIDs.union(relationshipEntityIDs)
    }

    private func murderBoardContains(_ document: Document, in book: Document) -> Bool {
        document.id == book.id || document.ancestors.contains(where: { $0.id == book.id })
    }

    private func murderBoardVisibleEntityIDs(
        selectedEntityID: UUID,
        entities: [SemanticEntity],
        relationships: [StoryBibleRelationship],
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

    private func uniqueEntityIDs(from relationships: [StoryBibleRelationship]) -> [UUID] {
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
                Text("The Murder Board is a visual relationship map over your Story Bible entities and canonical Story Bible relationships.")
                    .foregroundStyle(.secondary)
                Button {
                    showsNewBoard = true
                } label: {
                    Label("New Murder Board", systemImage: "plus.circle")
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
        .navigationTitle("Murder Board")
        .sheet(isPresented: $showsNewBoard) {
            NavigationStack {
                Form {
                    TextField("Board name", text: $newBoardName)
                }
                .navigationTitle("New Murder Board")
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
                                let name = newBoardName.nilIfBlank ?? "New Murder Board"
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
    @State private var showsNewRelationship = false
    @State private var newRelationshipTargetID: UUID?
    @State private var newRelationshipKind = "related to"
    @State private var newRelationshipNotes = ""
    @State private var relationshipKindDraft = ""
    @State private var relationshipNotesDraft = ""
    @State private var panOrigin: CGSize?
    @State private var zoomOrigin: Double?
    @State private var dragOrigins: [UUID: CGPoint] = [:]
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var pendingRelationshipSaveTask: Task<Void, Never>?
    @State private var loadedBoardID: UUID?

    var body: some View {
        if let board = controller.selectedMurderBoard {
            GeometryReader { proxy in
                let graph = controller.murderBoardGraph(for: board, state: state)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        controls(board: board, graph: graph, size: boardViewportSize(from: proxy.size))
                        Divider()
                        canvas(board: board, graph: graph)
                    }
                    Divider()
                    inspector(board: board, graph: graph, size: boardViewportSize(from: proxy.size))
                        .frame(width: 320)
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
                    persistRelationshipDraftImmediately()
                    persistState(for: board)
                }
            }
            .navigationTitle(board.title)
            .sheet(isPresented: $showsNewRelationship) {
                relationshipSheet
            }
        } else {
            Text("Select a Murder Board.")
                .foregroundStyle(.secondary)
        }
    }

    private func controls(board: Document, graph: MurderBoardGraph, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(
                    "Board Name",
                    text: Binding(
                        get: { board.title },
                        set: { controller.renameMurderBoard(board, title: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Button {
                    showsNewRelationship = true
                    newRelationshipTargetID = selectedNode.flatMap { node in
                        controller.storyBibleRelationshipTargets.first(where: { $0.id != node.id })?.id
                    }
                } label: {
                    Label("Add Relationship", systemImage: "link.badge.plus")
                }
                .disabled(selectedNode == nil)
            }

            HStack {
                Picker("Start From", selection: Binding(
                    get: { state.selectedEntityID },
                    set: {
                        state.selectedEntityID = $0
                        selectedRelationshipID = nil
                        if $0 != nil, state.connectedDepth == .allVisible {
                            state.connectedDepth = .direct
                        }
                        schedulePersist(for: board)
                    }
                )) {
                    Text("All Story Bible Elements").tag(Optional<UUID>.none)
                    ForEach(startingEntities, id: \.id) { entity in
                        Text(startingEntityTitle(for: entity)).tag(Optional(entity.id))
                    }
                }
                .frame(maxWidth: 320)

                Picker("Book", selection: Binding(
                    get: { state.selectedBookID },
                    set: {
                        state.selectedBookID = $0
                        schedulePersist(for: board)
                    }
                )) {
                    Text("All Books").tag(Optional<UUID>.none)
                    ForEach(controller.murderBoardBooks, id: \.id) { book in
                        Text(book.title).tag(Optional(book.id))
                    }
                }
                .frame(maxWidth: 240)

                Picker("Depth", selection: Binding(
                    get: { state.connectedDepth },
                    set: {
                        state.connectedDepth = $0
                        schedulePersist(for: board)
                    }
                )) {
                    ForEach(MurderBoardConnectedDepth.allCases) { depth in
                        Text(depth.title).tag(depth)
                    }
                }
                .frame(maxWidth: 220)
                .disabled(state.selectedEntityID == nil)

                Toggle("Show disconnected", isOn: Binding(
                    get: { state.includeDisconnectedEntities },
                    set: {
                        state.includeDisconnectedEntities = $0
                        schedulePersist(for: board)
                    }
                ))
                    .toggleStyle(.switch)
            }

            HStack {
                Menu("Entity Types") {
                    ForEach(SemanticEntityKind.allCases, id: \.rawValue) { kind in
                        let isVisible = state.visibleEntityKinds.isEmpty || state.visibleEntityKinds.contains(kind.rawValue)
                        Button {
                            toggleEntityKind(kind.rawValue, board: board)
                        } label: {
                            Label(kind.rawValue.capitalized, systemImage: isVisible ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }

                Menu("Relationship Types") {
                    ForEach(graph.availableRelationshipKinds, id: \.self) { kind in
                        let isVisible = !state.hiddenRelationshipKinds.contains(kind)
                        Button {
                            toggleRelationshipKind(kind, board: board)
                        } label: {
                            Label(kind, systemImage: isVisible ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }

                Spacer()

                HStack {
                    Text("Zoom")
                    Slider(
                        value: Binding(
                            get: { state.viewport.zoom },
                            set: { state.viewport.zoom = max(0.4, min($0, 2.5)) }
                        ),
                        in: 0.4...2.5,
                        onEditingChanged: { editing in
                            if !editing { schedulePersist(for: board) }
                        }
                    )
                        .frame(width: 120)
                    Button("Fit") {
                        fitVisible(graph: graph, size: size)
                        schedulePersist(for: board)
                    }
                    Button("Auto Layout") {
                        applyAutomaticLayout(for: graph)
                        schedulePersist(for: board)
                    }
                }
            }

            if graph.isTruncated {
                Text("Showing the first \(graph.visibleEntityCount) of \(graph.totalEntityCount) entities. Apply filters to explore more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func canvas(board: Document, graph: MurderBoardGraph) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.secondary.opacity(0.06)
                    .ignoresSafeArea()

                Canvas { context, _ in
                    for edge in graph.edges {
                        let source = screenPoint(for: edge.sourcePosition, in: size)
                        let target = screenPoint(for: edge.targetPosition, in: size)
                        var path = Path()
                        path.move(to: source)
                        path.addLine(to: target)
                        context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: selectedRelationshipID == edge.id ? 3 : 1.5)
                    }
                }

                if graph.edges.count <= 60 {
                    ForEach(graph.edges) { edge in
                        Button {
                            selectedRelationshipID = edge.id
                            state.selectedEntityID = nil
                            schedulePersist(for: board)
                        } label: {
                            Text(edge.relationship.kind)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .position(screenPoint(for: edge.labelPosition, in: size))
                    }
                }

                ForEach(graph.nodes) { node in
                    MurderBoardNodeView(
                        node: node,
                        isSelected: state.selectedEntityID == node.id,
                        open: { controller.openStoryBibleCard(for: node.entity) }
                    )
                    .position(screenPoint(for: node.position, in: size))
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        controller.openStoryBibleCard(for: node.entity)
                    })
                    .simultaneousGesture(TapGesture().onEnded {
                        state.selectedEntityID = node.id
                        selectedRelationshipID = nil
                        schedulePersist(for: board)
                    })
                    .highPriorityGesture(nodeDragGesture(for: node, board: board))
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasPanGesture(board: board))
            .simultaneousGesture(canvasZoomGesture(board: board))
            .clipped()
        }
    }

    private func inspector(board: Document, graph: MurderBoardGraph, size: CGSize) -> some View {
        Form {
            Section("Board") {
                LabeledContent("Visible entities", value: "\(graph.visibleEntityCount)")
                LabeledContent("Relationships", value: "\(graph.edges.count)")
                if let selectedBook = state.selectedBookID.flatMap({ id in controller.murderBoardBooks.first(where: { $0.id == id }) }) {
                    LabeledContent("Book scope", value: selectedBook.title)
                }
            }

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
                        controller.deleteStoryBibleRelationship(relationship)
                        selectedRelationshipID = nil
                        relationshipKindDraft = ""
                        relationshipNotesDraft = ""
                    }
                }
            } else if let node = selectedNode {
                Section("Selected Entity") {
                    LabeledContent("Name", value: node.entity.canonicalName)
                    LabeledContent("Type", value: node.entity.kind.capitalized)
                    LabeledContent("Scene links", value: "\(controller.linkedScenes(for: node.entity).count)")
                    if let summary = node.entity.summary?.nilIfBlank {
                        Text(summary)
                    }
                    Toggle("Pinned", isOn: Binding(
                        get: { state.nodeState(for: node.id)?.isPinned ?? false },
                        set: { value in
                            state.updateNodeState(node.id) {
                                $0.x = node.position.x
                                $0.y = node.position.y
                                $0.isPinned = value
                            }
                            schedulePersist(for: board)
                        }
                    ))
                    Toggle("Hidden on this board", isOn: Binding(
                        get: { state.nodeState(for: node.id)?.isHidden ?? false },
                        set: { value in
                            state.updateNodeState(node.id) {
                                $0.x = node.position.x
                                $0.y = node.position.y
                                $0.isHidden = value
                            }
                            schedulePersist(for: board)
                        }
                    ))
                    Button("Open Story Bible Entry") {
                        controller.openStoryBibleCard(for: node.entity)
                    }
                    Button("Center & Fit") {
                        state.selectedEntityID = node.id
                        fitVisible(graph: graph, size: size)
                        schedulePersist(for: board)
                    }
                }

                Section("Relationships") {
                    if relatedEdges(for: node, graph: graph).isEmpty {
                        Text("No visible relationships.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(relatedEdges(for: node, graph: graph)) { edge in
                            Button {
                                selectedRelationshipID = edge.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(edge.relationship.kind)
                                    Text(otherEntityName(for: edge, selectedID: node.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Section("Selection") {
                    Text("Select a node or relationship to inspect and edit it.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var relationshipSheet: some View {
        NavigationStack {
            Form {
                if let node = selectedNode {
                    LabeledContent("Source", value: node.entity.canonicalName)
                }
                Picker("Target", selection: $newRelationshipTargetID) {
                    ForEach(relationshipTargets, id: \.id) { target in
                        Text(target.canonicalName).tag(Optional(target.id))
                    }
                }
                TextField("Relationship", text: $newRelationshipKind)
                TextField("Notes", text: $newRelationshipNotes, axis: .vertical)
            }
            .navigationTitle("New Relationship")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { resetRelationshipComposer() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let node = selectedNode,
                              let target = relationshipTargets.first(where: { $0.id == newRelationshipTargetID }) else {
                            return
                        }
                        do {
                            try controller.addStoryBibleRelationship(
                                kind: newRelationshipKind,
                                notes: newRelationshipNotes,
                                from: node.entity,
                                to: target
                            )
                            resetRelationshipComposer()
                        } catch {
                            controller.report(error)
                        }
                    }
                    .disabled(selectedNode == nil || newRelationshipTargetID == nil || newRelationshipKind.nilIfBlank == nil)
                }
            }
        }
    }

    private var selectedNode: MurderBoardGraphNode? {
        guard let board = controller.selectedMurderBoard else { return nil }
        let graph = controller.murderBoardGraph(for: board, state: state)
        return graph.nodes.first { $0.id == state.selectedEntityID }
    }

    private var relationshipTargets: [SemanticEntity] {
        guard let selectedNode else { return [] }
        return controller.storyBibleRelationshipTargets.filter { $0.id != selectedNode.id }
    }

    private var startingEntities: [SemanticEntity] {
        controller.storyBibleRelationshipTargets.filter { !$0.isDeleted }
    }

    private func selectedRelationship(graph: MurderBoardGraph) -> StoryBibleRelationship? {
        graph.edges.first { $0.id == selectedRelationshipID }?.relationship
    }

    private func relatedEdges(for node: MurderBoardGraphNode, graph: MurderBoardGraph) -> [MurderBoardGraphEdge] {
        graph.edges.filter { $0.sourceID == node.id || $0.targetID == node.id }
    }

    private func otherEntityName(for edge: MurderBoardGraphEdge, selectedID: UUID) -> String {
        selectedID == edge.sourceID ? edge.relationship.targetEntity.canonicalName : edge.relationship.sourceEntity.canonicalName
    }

    private func startingEntityTitle(for entity: SemanticEntity) -> String {
        "\(entity.canonicalName) (\(entity.kind.capitalized))"
    }

    private func loadState(from board: Document) {
        persistRelationshipDraftImmediately()
        pendingSaveTask?.cancel()
        state = controller.murderBoardState(for: board)
        selectedRelationshipID = nil
        relationshipKindDraft = ""
        relationshipNotesDraft = ""
        loadedBoardID = board.id
    }

    private func toggleEntityKind(_ kind: String, board: Document) {
        var visible = state.visibleEntityKinds.isEmpty ? Set(SemanticEntityKind.allCases.map(\.rawValue)) : Set(state.visibleEntityKinds)
        if visible.contains(kind), visible.count > 1 {
            visible.remove(kind)
        } else {
            visible.insert(kind)
        }
        state.visibleEntityKinds = visible.count == SemanticEntityKind.allCases.count ? [] : Array(visible).sorted()
        schedulePersist(for: board)
    }

    private func toggleRelationshipKind(_ kind: String, board: Document) {
        var hidden = Set(state.hiddenRelationshipKinds)
        if hidden.contains(kind) {
            hidden.remove(kind)
        } else {
            hidden.insert(kind)
        }
        state.hiddenRelationshipKinds = Array(hidden).sorted()
        schedulePersist(for: board)
    }

    private func applyAutomaticLayout(for graph: MurderBoardGraph) {
        let positions = murderBoardAutomaticPositions(for: graph.nodes.map(\.id))
        for node in graph.nodes {
            guard let position = positions[node.id] else { continue }
            state.updateNodeState(node.id) {
                if !$0.isPinned {
                    $0.x = position.x
                    $0.y = position.y
                }
            }
        }
        state.layoutMode = .automatic
    }

    private func fitVisible(graph: MurderBoardGraph, size: CGSize) {
        guard let first = graph.nodes.first else { return }
        var minX = first.position.x
        var maxX = first.position.x
        var minY = first.position.y
        var maxY = first.position.y
        for node in graph.nodes.dropFirst() {
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
        }
        let width = max(maxX - minX, 220)
        let height = max(maxY - minY, 220)
        let zoom = min(
            2.5,
            max(
                0.4,
                min((size.width - murderBoardCanvasPadding) / width, (size.height - murderBoardCanvasPadding) / height)
            )
        )
        state.viewport.zoom = zoom
        state.viewport.offsetX = -(minX + maxX) / 2 * zoom
        state.viewport.offsetY = -(minY + maxY) / 2 * zoom
    }

    private func screenPoint(for world: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + state.viewport.offsetX + world.x * state.viewport.zoom,
            y: size.height / 2 + state.viewport.offsetY + world.y * state.viewport.zoom
        )
    }

    private func canvasPanGesture(board: Document) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if panOrigin == nil {
                    panOrigin = CGSize(width: state.viewport.offsetX, height: state.viewport.offsetY)
                }
                let origin = panOrigin ?? .zero
                state.viewport.offsetX = origin.width + value.translation.width
                state.viewport.offsetY = origin.height + value.translation.height
            }
            .onEnded { _ in
                panOrigin = nil
                schedulePersist(for: board)
            }
    }

    private func canvasZoomGesture(board: Document) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomOrigin == nil {
                    zoomOrigin = state.viewport.zoom
                }
                let origin = zoomOrigin ?? state.viewport.zoom
                state.viewport.zoom = max(0.4, min(origin * value, 2.5))
            }
            .onEnded { _ in
                zoomOrigin = nil
                schedulePersist(for: board)
            }
    }

    private func nodeDragGesture(for node: MurderBoardGraphNode, board: Document) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigins[node.id] == nil {
                    dragOrigins[node.id] = node.position
                }
                let origin = dragOrigins[node.id] ?? node.position
                let zoom = max(state.viewport.zoom, 0.01)
                state.updateNodeState(node.id) {
                    $0.x = origin.x + value.translation.width / zoom
                    $0.y = origin.y + value.translation.height / zoom
                }
                state.layoutMode = .manual
            }
            .onEnded { _ in
                dragOrigins[node.id] = nil
                schedulePersist(for: board)
            }
    }

    private func resetRelationshipComposer() {
        newRelationshipTargetID = nil
        newRelationshipKind = "related to"
        newRelationshipNotes = ""
        showsNewRelationship = false
    }

    private func boardViewportSize(from totalSize: CGSize) -> CGSize {
        CGSize(width: max(400, totalSize.width - 320), height: totalSize.height)
    }

    private func switchBoard(to board: Document) {
        if let loadedBoardID,
           loadedBoardID != board.id,
           let previousBoard = try? controller.store.documents.fetch(id: loadedBoardID) {
            persistState(for: previousBoard)
        }
        loadState(from: board)
    }

    private func schedulePersist(for board: Document) {
        pendingSaveTask?.cancel()
        let boardID = board.id
        pendingSaveTask = Task { @MainActor in
            defer { pendingSaveTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let persistedBoard = try? controller.store.documents.fetch(id: boardID) else { return }
            guard !Task.isCancelled, loadedBoardID == boardID else { return }
            controller.saveMurderBoardState(state, for: persistedBoard)
        }
    }

    private func persistState(for board: Document) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard let persistedBoard = try? controller.store.documents.fetch(id: board.id) else { return }
        controller.saveMurderBoardState(state, for: persistedBoard)
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
        guard let relationshipID = selectedRelationshipID else { return }
        let kind = relationshipKindDraft
        let notes = relationshipNotesDraft.nilIfBlank
        pendingRelationshipSaveTask = Task { @MainActor in
            defer { pendingRelationshipSaveTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let relationship = try? controller.store.storyBibleRelationships.fetch(id: relationshipID) else { return }
            guard let normalizedKind = kind.nilIfBlank else {
                relationshipKindDraft = relationship.kind
                relationshipNotesDraft = relationship.notes ?? ""
                return
            }
            relationship.kind = normalizedKind
            relationship.notes = notes
            controller.saveStoryBibleRelationship(relationship)
        }
    }

    private func persistRelationshipDraftImmediately() {
        pendingRelationshipSaveTask?.cancel()
        pendingRelationshipSaveTask = nil
        guard let relationshipID = selectedRelationshipID,
              let relationship = try? controller.store.storyBibleRelationships.fetch(id: relationshipID) else {
            return
        }
        guard let normalizedKind = relationshipKindDraft.nilIfBlank else {
            relationshipKindDraft = relationship.kind
            relationshipNotesDraft = relationship.notes ?? ""
            return
        }
        relationship.kind = normalizedKind
        relationship.notes = relationshipNotesDraft.nilIfBlank
        controller.saveStoryBibleRelationship(relationship)
    }
}

private struct MurderBoardNodeView: View {
    let node: MurderBoardGraphNode
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.entity.canonicalName)
                .font(.headline)
                .lineLimit(2)
            Text(node.entity.kind.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            if node.mentionCount > 0 {
                Text("\(node.mentionCount) scene links")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 160, alignment: .leading)
        .background(fillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .contextMenu {
            Button("Open Story Bible Entry", action: open)
        }
    }

    private var fillColor: Color {
        switch node.entity.kind {
        case SemanticEntityKind.character.rawValue: Color.blue.opacity(0.12)
        case SemanticEntityKind.location.rawValue: Color.green.opacity(0.12)
        case SemanticEntityKind.organization.rawValue: Color.orange.opacity(0.12)
        case SemanticEntityKind.object.rawValue: Color.purple.opacity(0.12)
        case SemanticEntityKind.event.rawValue: Color.red.opacity(0.12)
        default: Color.gray.opacity(0.12)
        }
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

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
