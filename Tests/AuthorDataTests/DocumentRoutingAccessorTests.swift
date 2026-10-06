import CoreData
import XCTest
@testable import AuthorData

/// Regression coverage for the ID-backed `Document.project` / `Document.parent` accessors.
/// They replace Core Data's generated setters, so they must maintain the inverse sets
/// themselves; otherwise newly imported documents are invisible until the app relaunches.
@MainActor
final class DocumentRoutingAccessorTests: XCTestCase {
    func testSettingProjectAndParentUpdatesInverseSetsBeforeSave() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = makeProject(in: store)
        let book = makeDocument(in: store, project: project, title: "Book")
        let chapter = makeDocument(in: store, project: project, title: "Chapter", parent: book)

        XCTAssertEqual(Set(project.documents.map(\.id)), [book.id, chapter.id])
        XCTAssertEqual(book.children.map(\.id), [chapter.id])
        XCTAssertEqual(chapter.projectID, project.id)
        XCTAssertEqual(chapter.parentID, book.id)
    }

    func testReparentingMovesChildBetweenInverseSetsAndClearsRoutingID() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = makeProject(in: store)
        let first = makeDocument(in: store, project: project, title: "First")
        let second = makeDocument(in: store, project: project, title: "Second")
        let scene = makeDocument(in: store, project: project, title: "Scene", parent: first)
        try store.save()

        scene.parent = second
        XCTAssertTrue(first.children.isEmpty)
        XCTAssertEqual(second.children.map(\.id), [scene.id])

        scene.parent = nil
        try store.save()
        XCTAssertTrue(second.children.isEmpty)
        XCTAssertNil(scene.parentID)
        XCTAssertNil(scene.parent)
    }

    func testRelationshipChangesSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("routing.sqlite")

        let projectID: UUID
        let bookID: UUID
        do {
            let store = try AuthorDataStore(storeURL: url)
            let project = makeProject(in: store)
            let book = makeDocument(in: store, project: project, title: "Book")
            _ = makeDocument(in: store, project: project, title: "Chapter", parent: book)
            try store.save()
            projectID = project.id
            bookID = book.id
            for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
                try store.container.persistentStoreCoordinator.remove(persistentStore)
            }
        }

        let reopened = try AuthorDataStore(storeURL: url)
        let project = try reopened.projects.require(id: projectID)
        let book = try reopened.documents.require(id: bookID)
        XCTAssertEqual(project.documents.count, 2)
        XCTAssertEqual(book.children.map(\.title), ["Chapter"])
        XCTAssertEqual(book.project.id, projectID)
    }

    func testIDOnlyParentResolvesRepeatedlyAndReturnsNilAfterDeletion() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = makeProject(in: store)
        let book = makeDocument(in: store, project: project, title: "Book")
        let scene = makeDocument(in: store, project: project, title: "Scene", parent: book)
        try store.save()

        // Mirror a shared document: the relationship is cleared, only the UUID route remains.
        scene.sharingGroupID = UUID()
        scene.willChangeValue(forKey: "parent")
        scene.setPrimitiveValue(nil, forKey: "parent")
        scene.didChangeValue(forKey: "parent")
        book.mutableSetValue(forKey: "children").remove(scene)
        scene.parentID = book.id
        try store.save()
        XCTAssertEqual(scene.parentID, book.id)

        XCTAssertEqual(scene.parent?.objectID, book.objectID)
        XCTAssertEqual(scene.parent?.objectID, book.objectID)

        store.context.delete(book)
        try store.save()
        XCTAssertNil(scene.parent)
    }

    private func makeProject(in store: AuthorDataStore) -> WritingProject {
        store.projects.create {
            $0.title = "Project"
            $0.sourceIdentifier = "project"
            $0.sourceFormat = "native"
            $0.createdAt = Date()
            $0.modifiedAt = Date()
        }
    }

    private func makeDocument(
        in store: AuthorDataStore,
        project: WritingProject,
        title: String,
        parent: Document? = nil
    ) -> Document {
        store.documents.create {
            $0.sourceIdentifier = title
            $0.title = title
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.parent = parent
        }
    }
}
