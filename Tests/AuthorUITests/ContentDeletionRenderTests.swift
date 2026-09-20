import AuthorData
import SwiftUI
import XCTest
@testable import AuthorUI

@MainActor
final class ContentDeletionRenderTests: XCTestCase {
    func testRetainedRelationshipAndSceneViewsCanRenderAfterEntityDeletion() throws {
        let controller = WorkspaceController(store: try AuthorDataStore(inMemory: true))
        let project = try controller.createProject(title: "Deletion rendering")
        let entity = try controller.addStoryBibleEntry(named: "Harbor Guild", category: .organizations)
        let other = try controller.addStoryBibleEntry(named: "Moon Port", category: .places)
        try controller.addStoryBibleRelationship(kind: "based in", notes: nil, from: entity, to: other)
        controller.selection = .storyBibleCard(try XCTUnwrap(entity.storyBibleCard).id)
        let relationships = StoryBibleRelationshipsSection(entity: entity, controller: controller)
        let scenes = StoryBibleLinkedScenesSection(entity: entity, controller: controller)

        try controller.deleteSemanticEntity(entity.id)

        XCTAssertEqual(controller.selection, .storyBibleCategory(projectID: project.id, category: .organizations))
        XCTAssertTrue(controller.linkedScenes(for: entity).isEmpty)
        _ = relationships.body
        _ = scenes.body
    }
}
