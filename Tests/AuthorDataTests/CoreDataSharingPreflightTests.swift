import CoreData
import XCTest
@testable import AuthorData

@MainActor
final class CoreDataSharingPreflightTests: XCTestCase {
    func testSceneShareTraversesIntoPrivateProjectAndSiblingScene() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Private project title"
            $0.sourceIdentifier = "project"
            $0.sourceFormat = "native"
            $0.createdAt = Date()
            $0.modifiedAt = Date()
        }
        let sharedScene = makeDocument(
            in: store,
            project: project,
            title: "Reviewer scene",
            sourceIdentifier: "reviewer-scene"
        )
        let privateScene = makeDocument(
            in: store,
            project: project,
            title: "Unpublished ending",
            sourceIdentifier: "private-scene"
        )
        privateScene.includeInCompile = false
        privateScene.plainText = "The private ending."
        try store.save()

        let report = CoreDataSharingPreflight.audit(
            root: sharedScene,
            allowedObjectIDs: [sharedScene.objectID]
        )

        XCTAssertFalse(report.isObjectGraphSafe)
        XCTAssertTrue(report.exposures.contains { $0.entityName == WritingProject.entityName })
        XCTAssertTrue(report.exposures.contains {
            $0.entityName == Document.entityName && $0.objectID == privateScene.objectID.uriRepresentation()
        })
    }

    func testDisconnectedCanonicalRecordPassesObjectGraphPreflight() throws {
        let store = try AuthorDataStore(inMemory: true)
        let scene = store.documents.create {
            $0.sourceIdentifier = "isolated-scene"
            $0.title = "Isolated scene"
            $0.kind = DocumentKind.text.rawValue
            $0.narrativeType = NarrativeType.scene.rawValue
            $0.orderIndex = 0
            $0.plainText = "Canonical text"
        }
        try store.save()

        let report = CoreDataSharingPreflight.audit(
            root: scene,
            allowedObjectIDs: [scene.objectID]
        )

        XCTAssertTrue(report.isObjectGraphSafe)
        XCTAssertEqual(report.visitedObjectCount, 1)
    }

    private func makeDocument(
        in store: AuthorDataStore,
        project: WritingProject,
        title: String,
        sourceIdentifier: String
    ) -> Document {
        store.documents.create {
            $0.sourceIdentifier = sourceIdentifier
            $0.title = title
            $0.kind = DocumentKind.text.rawValue
            $0.narrativeType = NarrativeType.scene.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.plainText = title
        }
    }
}
