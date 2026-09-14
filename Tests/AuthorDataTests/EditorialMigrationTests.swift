import XCTest
import CoreData
@testable import AuthorData

@MainActor
final class EditorialMigrationTests: XCTestCase {
    func testPopulatedV4StoreMigratesToV5AndReviewHistoryReopens() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: root.appendingPathComponent("Sources/AuthorData/Resources/AuthorData.momd/AuthorDataV4.mom")))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.sqlite")
        let old = NSPersistentContainer(name: "AuthorData", managedObjectModel: model)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var error: Error?; old.loadPersistentStores { _, e in error = e }; XCTAssertNil(error)
        let id = UUID()
        let project = NSEntityDescription.insertNewObject(forEntityName: "WritingProject", into: old.viewContext) as! WritingProject
        project.id = id; project.title = "Legacy"; project.sourceIdentifier = id.uuidString; project.sourceFormat = "native"; project.createdAt = Date(); project.modifiedAt = Date()
        let doc = NSEntityDescription.insertNewObject(forEntityName: "Document", into: old.viewContext) as! Document
        doc.id = UUID(); doc.sourceIdentifier = doc.id.uuidString; doc.title = "Scene"; doc.kind = "Text"; doc.orderIndex = 0; doc.plainText = "Original manuscript"; doc.project = project
        try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(store) }
        let migrated = try AuthorDataStore(storeURL: url)
        XCTAssertEqual(try migrated.projects.require(id: id).title, "Legacy")
        XCTAssertEqual(try migrated.documents.fetchAll().first?.plainText, "Original manuscript")
        XCTAssertEqual(try migrated.editorialReviews.count(), 0)
        try EditorPersonaLibrary.seed(in: migrated)
        XCTAssertEqual(try migrated.editorPersonas.count(), 6)
        let migratedProject = try migrated.projects.require(id: id)
        let migratedDoc = try XCTUnwrap(migrated.documents.fetchAll().first)
        let review = migrated.editorialReviews.create {
            $0.project = migratedProject; $0.target = migratedDoc; $0.targetID = migratedDoc.id; $0.targetTitle = migratedDoc.title
            $0.scope = "document"; $0.personaName = "Technical"; $0.personaInstructions = "Critique"; $0.personaVersion = 1
            $0.providerID = "appleIntelligence"; $0.modelID = "apple-system-on-device"; $0.promptVersion = "1"; $0.schemaVersion = "1"
            $0.parameters = "test"; $0.environment = "test"; $0.summary = "Saved review"; $0.status = "completed"; $0.createdAt = Date()
        }
        migrated.editorialInputs.create {
            $0.review = review; $0.document = migratedDoc; $0.documentID = migratedDoc.id; $0.title = migratedDoc.title
            $0.path = "Scene"; $0.orderIndex = 0; $0.plainText = migratedDoc.plainText!; $0.contentHash = ReviewInputSnapshot.hash($0.plainText); $0.role = "manuscript"
        }
        try migrated.save()
        for store in migrated.container.persistentStoreCoordinator.persistentStores { try migrated.container.persistentStoreCoordinator.remove(store) }
        let reopened = try AuthorDataStore(storeURL: url)
        XCTAssertEqual(try reopened.editorPersonas.count(), 6)
        XCTAssertEqual(try reopened.editorialReviews.fetchAll().first?.inputs.first?.plainText, "Original manuscript")
        XCTAssertEqual(try reopened.editorialReviews.fetchAll().first?.summary, "Saved review")
        XCTAssertEqual(try reopened.documents.fetchAll().first?.plainText, "Original manuscript")
    }

    func testPopulatedV5StoreMigratesToV6WithNarrativeFieldsDefaultingCleanly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: root.appendingPathComponent("Sources/AuthorData/Resources/AuthorData.momd/AuthorDataV5.mom")))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.sqlite")
        let old = NSPersistentContainer(name: "AuthorData", managedObjectModel: model)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var error: Error?; old.loadPersistentStores { _, e in error = e }; XCTAssertNil(error)
        let id = UUID()
        let project = NSEntityDescription.insertNewObject(forEntityName: "WritingProject", into: old.viewContext) as! WritingProject
        project.id = id; project.title = "Legacy"; project.sourceIdentifier = id.uuidString; project.sourceFormat = "native"; project.createdAt = Date(); project.modifiedAt = Date()
        let docID = UUID()
        let doc = NSEntityDescription.insertNewObject(forEntityName: "Document", into: old.viewContext) as! Document
        doc.id = docID; doc.sourceIdentifier = docID.uuidString; doc.title = "Scene"; doc.kind = "Text"; doc.orderIndex = 0
        doc.plainText = "one two three"; doc.project = project
        try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(store) }

        let migrated = try AuthorDataStore(storeURL: url)
        let migratedDoc = try migrated.documents.require(id: docID)
        XCTAssertEqual(migratedDoc.plainText, "one two three")
        XCTAssertNil(migratedDoc.narrativeType)
        XCTAssertEqual(migratedDoc.ownWordCount, 0)
        XCTAssertEqual(migratedDoc.actualWordCount, 0)

        migratedDoc.narrativeType = NarrativeType.scene.rawValue
        WordCountService.recomputeOwnWordCount(for: migratedDoc)
        try migrated.save()
        XCTAssertEqual(migratedDoc.actualWordCount, 3)
    }
}

