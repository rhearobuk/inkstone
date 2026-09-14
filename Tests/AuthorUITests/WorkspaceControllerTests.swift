import AuthorData
import XCTest
@testable import AuthorUI

@MainActor
final class WorkspaceControllerTests: XCTestCase {
    func testCreatesStarterProjectWithWorkspaceRootsAndNarrative() throws {
        let controller = try makeController()

        let project = try controller.createProject(title: "The Long Road", author: "Ada")

        XCTAssertEqual(project.title, "The Long Road")
        XCTAssertEqual(project.author, "Ada")
        XCTAssertEqual(controller.binderItems.map(\.title), [
            "Project Definition", "Story Bible", "Gallery", "Narrative"
        ])
        XCTAssertEqual(project.documents.count, 3)
        XCTAssertEqual(
            project.documents.first(where: { $0.title == "Narrative" })?
                .orderedChildren.first?.title,
            "Untitled Novel"
        )
    }

    func testGroupsStoryBibleEntriesUsingContractOntology() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")

        let character = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        let artifact = try controller.addStoryBibleEntry(named: "The Key", category: .artifacts)

        XCTAssertEqual(character.kind, SemanticEntityKind.character.rawValue)
        XCTAssertEqual(artifact.kind, SemanticEntityKind.object.rawValue)
        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let people = try XCTUnwrap(storyBible.children?.first { $0.title == "People" })
        let artifacts = try XCTUnwrap(storyBible.children?.first { $0.title == "Artifacts" })
        XCTAssertEqual(people.children?.map(\.title), ["Mara"])
        XCTAssertEqual(artifacts.children?.map(\.title), ["The Key"])
    }

    func testMovesDocumentIntoFolderAndRejectsHierarchyCycle() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Binder")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(script.orderedChildren.first)
        controller.selection = .document(script.id)
        let chapter = try controller.addDocument(
            title: "Chapter One",
            kind: .folder,
            parentID: script.id
        )

        try controller.moveDocument(scene.id, onto: chapter.id)

        XCTAssertEqual(scene.parent?.id, chapter.id)
        XCTAssertThrowsError(try controller.moveDocument(script.id, onto: scene.id)) { error in
            XCTAssertEqual(error.localizedDescription, WorkspaceError.invalidMove.localizedDescription)
        }
    }

    func testUpdatesDocumentTextThroughPersistenceContract() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        controller.selection = .document(scene.id)

        controller.updateDocument(
            title: "Arrival",
            synopsis: "The protagonist arrives.",
            plainText: "Rain covered the station."
        )

        let persisted = try controller.store.documents.require(id: scene.id)
        XCTAssertEqual(persisted.title, "Arrival")
        XCTAssertEqual(persisted.synopsis, "The protagonist arrives.")
        XCTAssertEqual(persisted.plainText, "Rain covered the station.")
    }

    func testAddsAndDeletesNativeGalleryImageForStoryBibleEntry() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")
        let place = try controller.addStoryBibleEntry(named: "Moon Harbor", category: .places)
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let item = try XCTUnwrap(
            controller.addGalleryImages(from: [imageURL], relatedTo: place).first
        )

        XCTAssertEqual(item.semanticEntity?.id, place.id)
        XCTAssertEqual(item.resource.data, imageData)
        XCTAssertEqual(item.resource.role, "galleryImage")
        XCTAssertTrue(place.galleryItems.contains(item))
        XCTAssertEqual(controller.galleryItems.count, 1)

        controller.deleteGalleryItem(item)

        XCTAssertEqual(try controller.store.galleryItems.count(), 0)
        XCTAssertEqual(try controller.store.resources.count(), 0)
        XCTAssertEqual(controller.selection, .semanticEntity(place.id))
    }

    func testSeparatesImportedStoryBibleRootsFromNarrative() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Imported")
        let existing = Array(project.documents)
        for document in existing {
            controller.store.context.delete(document)
        }
        let characters = controller.store.documents.create {
            $0.sourceIdentifier = "characters"
            $0.title = "Characters"
            $0.kind = DocumentKind.folder.rawValue
            $0.orderIndex = 1
            $0.project = project
        }
        controller.store.documents.create {
            $0.sourceIdentifier = "character"
            $0.title = "Mara"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.parent = characters
        }
        controller.store.documents.create {
            $0.sourceIdentifier = "draft"
            $0.title = "Novel"
            $0.kind = DocumentKind.draftFolder.rawValue
            $0.orderIndex = 0
            $0.project = project
        }
        try controller.store.save()
        controller.refresh()

        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let people = try XCTUnwrap(storyBible.children?.first { $0.title == "People" })
        let narrative = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        XCTAssertEqual(people.children?.map(\.title), ["Characters"])
        XCTAssertEqual(narrative.children?.map(\.title), ["Novel"])
    }

    private func makeController() throws -> WorkspaceController {
        WorkspaceController(store: try AuthorDataStore(inMemory: true))
    }
}
