import AuthorData
import XCTest
@testable import AuthorUI

@MainActor
final class FocusedMurderBoardTests: XCTestCase {
    func testFocusKeepsOnlyDirectConnectionsToDestinationCategories() throws {
        let (controller, board, glinda, wand, city) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.artifacts]
        // Old board filters and hidden positions must not hide the new focus.
        state.visibleEntityKinds = ["location"]
        state.includeDisconnectedEntities = true
        state.hiddenRelationshipKinds = ["owns"]
        state.nodeStates = [.init(entityID: glinda.id, x: 300, y: 200, isHidden: true)]

        let graph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertEqual(Set(graph.nodes.map(\.id)), [glinda.id, wand.id])
        XCTAssertEqual(graph.edges.map(\.relationship.sentence), ["Glinda owns Wand"])
        XCTAssertFalse(graph.nodes.contains { $0.id == city.id })
    }

    func testMultipleCategoriesIncludeIncomingAndOutgoingRelationships() throws {
        let (controller, board, glinda, wand, city) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.artifacts, .places]

        let graph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertEqual(Set(graph.nodes.map(\.id)), [glinda.id, wand.id, city.id])
        XCTAssertEqual(Set(graph.edges.map(\.relationship.sentence)), ["Glinda owns Wand", "Emerald City welcomes Glinda"])
        let incoming = try XCTUnwrap(graph.edges.first { $0.sourceID == city.id })
        XCTAssertEqual(incoming.targetID, glinda.id)
    }

    func testArtifactCanBeFocusWithoutIncludingItsCategoryInDestinations() throws {
        let (controller, board, glinda, wand, _) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .artifacts
        state.selectedEntityID = wand.id
        state.destinationCategories = [.people]

        let graph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertEqual(Set(graph.nodes.map(\.id)), [glinda.id, wand.id])
        XCTAssertEqual(graph.edges.map(\.relationship.sentence), ["Glinda owns Wand"])
    }

    func testSameCategoryIncludesSavedCharacterRelationships() throws {
        let (controller, board, glinda, _, _) = try fixture()
        let witch = try XCTUnwrap(board.project.semanticEntities.first { $0.canonicalName == "Witch" })
        try controller.addCharacterRelationship(
            kind: "knows", notes: nil,
            from: XCTUnwrap(glinda.characterProfile), to: XCTUnwrap(witch.characterProfile)
        )
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.people]

        let graph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertEqual(Set(graph.nodes.map(\.id)), [glinda.id, witch.id])
        XCTAssertEqual(graph.edges.map(\.relationship.sentence), ["Glinda knows Witch"])
    }

    func testEmptyDestinationsAndMissingFocusDoNotShowUnrelatedNodes() throws {
        let (controller, board, glinda, _, _) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = []
        var graph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertEqual(graph.nodes.map(\.id), [glinda.id])
        XCTAssertTrue(graph.edges.isEmpty)

        state.selectedEntityID = UUID()
        graph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertTrue(graph.nodes.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testLegacyBoardMigratesFocusAndPersistsCategorySelections() throws {
        let (controller, board, glinda, _, _) = try fixture()
        var legacy = MurderBoardState()
        legacy.selectedEntityID = glinda.id
        legacy.viewport.zoom = 0.5
        let decoded = try JSONDecoder().decode(MurderBoardState.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.focusCategory)
        XCTAssertNil(decoded.destinationCategories)
        var state = controller.focusedMurderBoardState(decoded, in: board.project)
        XCTAssertEqual(state.focusCategory, .people)
        XCTAssertEqual(state.selectedEntityID, glinda.id)
        XCTAssertEqual(state.destinationCategories, [.places, .artifacts])

        state.destinationCategories = [.artifacts, .places]
        controller.saveMurderBoardState(state, for: board)
        XCTAssertEqual(controller.murderBoardState(for: board), state)
        state.focusCategory = .artifacts
        state = controller.focusedMurderBoardState(state, in: board.project)
        let focus = try XCTUnwrap(board.project.semanticEntities.first { $0.id == state.selectedEntityID })
        XCTAssertEqual(focus.kind, SemanticEntityKind.object.rawValue)
        XCTAssertEqual(state.destinationCategories, [.artifacts, .places])
        state.focusCategory = .organizations
        state = controller.focusedMurderBoardState(state, in: board.project)
        XCTAssertNil(state.selectedEntityID)
    }

    func testWandCountsItsOwnerEvenWhenCharactersAreFilteredOut() throws {
        let (controller, board, _, wand, _) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .artifacts
        state.selectedEntityID = wand.id
        state.destinationCategories = [.artifacts]

        let graph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertTrue(graph.edges.isEmpty)
        XCTAssertEqual(graph.totalConnectionCount, 2)
        XCTAssertEqual(graph.hiddenConnectionCount, 2)
        XCTAssertEqual(graph.connectionCounts[.people], 1)
        XCTAssertEqual(graph.connectionCounts[.places], 1)

        state.destinationCategories = nil
        state = controller.focusedMurderBoardState(state, in: board.project)
        XCTAssertEqual(state.destinationCategories, [.people, .places])
        let revealed = controller.murderBoardGraph(for: board, state: state)
        XCTAssertEqual(revealed.edges.count, 2)
        XCTAssertEqual(revealed.hiddenConnectionCount, 0)
    }

    func testDiagramConnectsEntityBoundariesWithLabelsAndDirectionalArrowheads() throws {
        let (controller, board, glinda, wand, city) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.artifacts, .places, .organizations]
        let graph = controller.murderBoardGraph(for: board, state: state)
        let layout = MurderBoardDiagramLayout(graph: graph, focusID: glinda.id, categories: state.destinationCategories ?? [])

        XCTAssertEqual(layout.positions[glinda.id], .zero)
        XCTAssertEqual(Set(layout.groups.map(\.category)), [.artifacts, .places])
        XCTAssertEqual(layout.links.count, 2)
        XCTAssertLessThan(try XCTUnwrap(layout.positions[wand.id]).x * XCTUnwrap(layout.positions[city.id]).x, 0)
        for link in layout.links {
            let source = try XCTUnwrap(layout.positions[link.edge.sourceID])
            let target = try XCTUnwrap(layout.positions[link.edge.targetID])
            XCTAssertEqual(abs(link.start.x - source.x), MurderBoardDiagramLayout.nodeSize.width / 2)
            XCTAssertEqual(abs(link.end.x - target.x), MurderBoardDiagramLayout.nodeSize.width / 2)
            XCTAssertEqual(link.start.y, source.y)
            XCTAssertEqual(link.end.y, target.y)
            XCTAssertTrue(layout.bounds.contains(link.label))
            XCTAssertFalse(link.arrowhead.isEmpty)
            XCTAssertFalse(link.path.isEmpty)
        }
        let incoming = try XCTUnwrap(layout.links.first { $0.edge.sourceID == city.id })
        XCTAssertEqual(incoming.edge.targetID, glinda.id)
        XCTAssertEqual(abs(incoming.end.x), MurderBoardDiagramLayout.nodeSize.width / 2)
    }

    func testParallelRelationshipsHaveSeparateLabelsButShareOneEntityNode() throws {
        let (controller, board, glinda, wand, _) = try fixture()
        try controller.addStoryBibleRelationship(kind: "protects", notes: nil, from: glinda, to: wand)
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.artifacts]
        let graph = controller.murderBoardGraph(for: board, state: state)
        let layout = MurderBoardDiagramLayout(graph: graph, focusID: glinda.id, categories: [.artifacts])
        XCTAssertEqual(layout.positions.count, 2)
        XCTAssertEqual(layout.links.count, 2)
        XCTAssertGreaterThanOrEqual(abs(layout.links[0].label.y - layout.links[1].label.y), 44)
    }

    func testPlaceRelationshipTargetsAreIndependentOfBoardFiltersAndProjectSelection() throws {
        let (controller, board, glinda, wand, city) = try fixture()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state.destinationCategories = [.artifacts]
        controller.saveMurderBoardState(state, for: board)
        _ = try controller.createProject(title: "Another project")
        _ = try controller.addStoryBibleEntry(named: "Unrelated Place", category: .places)

        XCTAssertEqual(controller.storyBibleRelationshipTargets(from: glinda, category: .places).map(\.id), [city.id])
        XCTAssertEqual(controller.storyBibleRelationshipTargets(from: wand, category: .places).map(\.id), [city.id])
        XCTAssertTrue(controller.storyBibleRelationshipTargets(from: city, category: .places).isEmpty)
        try controller.addStoryBibleRelationship(kind: "visits", notes: nil, from: glinda, to: city)
        state.destinationCategories = [.places]
        let graph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertTrue(graph.edges.contains { $0.relationship.sentence == "Glinda visits Emerald City" })
    }

    func testLegacyCardOwnershipAndPlaceLinksAreBackfilledOnceAndStayEditable() throws {
        let store = try AuthorDataStore(inMemory: true)
        let original = WorkspaceController(store: store)
        _ = try original.createProject(title: "Legacy links")
        let board = try original.createMurderBoard()
        let glinda = try original.addStoryBibleEntry(named: "Glinda", category: .people)
        let wand = try original.addStoryBibleEntry(named: "Wand", category: .artifacts)
        let city = try original.addStoryBibleEntry(named: "Emerald City", category: .places)
        let organization = try original.addStoryBibleEntry(named: "Council", category: .organizations)
        let profile = try XCTUnwrap(glinda.characterProfile)
        let wandCard = try XCTUnwrap(wand.storyBibleCard)
        let placeCard = try XCTUnwrap(city.storyBibleCard)
        let organizationCard = try XCTUnwrap(organization.storyBibleCard)
        wandCard.owners = [profile]
        placeCard.relatedCharacters = [profile]
        organizationCard.linkedCharacters = [profile]
        try store.save()
        XCTAssertTrue(wand.outgoingStoryBibleRelationships.isEmpty)

        let controller = WorkspaceController(store: store)
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(wand.outgoingStoryBibleRelationships.count, 1)
        XCTAssertEqual(city.outgoingStoryBibleRelationships.count, 1)
        XCTAssertEqual(organization.outgoingStoryBibleRelationships.count, 1)
        var state = MurderBoardState()
        state.focusCategory = .artifacts
        state.selectedEntityID = wand.id
        state = controller.focusedMurderBoardState(state, in: board.project)
        let graph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertEqual(graph.edges.map(\.relationship.sentence), ["Wand owned by Glinda"])
        XCTAssertEqual(state.destinationCategories, [.people])

        let repeated = WorkspaceController(store: store)
        XCTAssertNil(repeated.lastError)
        XCTAssertEqual(wand.outgoingStoryBibleRelationships.count, 1)
        let ownership = try XCTUnwrap(wand.outgoingStoryBibleRelationships.first)
        repeated.deleteStoryBibleRelationship(ownership)
        XCTAssertTrue(wandCard.owners.isEmpty)
        let placeLink = try XCTUnwrap(city.outgoingStoryBibleRelationships.first)
        placeLink.kind = "welcomes"
        repeated.saveStoryBibleRelationship(placeLink)
        XCTAssertTrue(placeCard.relatedCharacters.isEmpty)

        let reopened = WorkspaceController(store: store)
        XCTAssertNil(reopened.lastError)
        XCTAssertTrue(wand.outgoingStoryBibleRelationships.isEmpty)
        XCTAssertEqual(city.outgoingStoryBibleRelationships.map(\.kind), ["welcomes"])
        XCTAssertEqual(organization.outgoingStoryBibleRelationships.count, 1)
    }

    func testNewCardOwnerAndPlaceSelectionsAppearInBothDirections() throws {
        let controller = WorkspaceController(store: try AuthorDataStore(inMemory: true))
        _ = try controller.createProject(title: "Card links")
        let board = try controller.createMurderBoard()
        let glinda = try controller.addStoryBibleEntry(named: "Glinda", category: .people)
        let wand = try controller.addStoryBibleEntry(named: "Wand", category: .artifacts)
        let city = try controller.addStoryBibleEntry(named: "Emerald City", category: .places)
        let profile = try XCTUnwrap(glinda.characterProfile)
        controller.setCharacters([profile], for: try XCTUnwrap(wand.storyBibleCard), relationship: .artifact)
        controller.setCharacters([profile], for: try XCTUnwrap(city.storyBibleCard), relationship: .place)
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = glinda.id
        state = controller.focusedMurderBoardState(state, in: board.project)
        let graph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertEqual(Set(graph.edges.map(\.relationship.sentence)), ["Wand owned by Glinda", "Emerald City associated with Glinda"])
        XCTAssertEqual(graph.totalConnectionCount, 2)
    }

    private func fixture() throws -> (WorkspaceController, Document, SemanticEntity, SemanticEntity, SemanticEntity) {
        let controller = WorkspaceController(store: try AuthorDataStore(inMemory: true))
        _ = try controller.createProject(title: "Focused Board")
        let board = try controller.createMurderBoard()
        let glinda = try controller.addStoryBibleEntry(named: "Glinda", category: .people)
        let wand = try controller.addStoryBibleEntry(named: "Wand", category: .artifacts)
        let city = try controller.addStoryBibleEntry(named: "Emerald City", category: .places)
        let witch = try controller.addStoryBibleEntry(named: "Witch", category: .people)
        let broom = try controller.addStoryBibleEntry(named: "Broom", category: .artifacts)
        try controller.addStoryBibleRelationship(kind: "owns", notes: nil, from: glinda, to: wand)
        try controller.addStoryBibleRelationship(kind: "welcomes", notes: nil, from: city, to: glinda)
        try controller.addStoryBibleRelationship(kind: "owns", notes: nil, from: witch, to: broom)
        try controller.addStoryBibleRelationship(kind: "stored in", notes: nil, from: wand, to: city)
        return (controller, board, glinda, wand, city)
    }
}
