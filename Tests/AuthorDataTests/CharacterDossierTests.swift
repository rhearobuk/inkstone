import CoreData
import XCTest
@testable import AuthorData

@MainActor
final class CharacterDossierTests: XCTestCase {
    func testCharacterDossierCRUDAndInverses() throws {
        let store = try AuthorDataStore(inMemory: true)
        let now = Date()
        let project = store.projects.create {
            $0.title = "Novel"
            $0.sourceIdentifier = "native-\($0.id)"
            $0.sourceFormat = "native"
            $0.createdAt = now
            $0.modifiedAt = now
        }
        let sourceDocument = store.documents.create {
            $0.sourceIdentifier = "document-\($0.id)"
            $0.title = "Imported character sheet"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
        }
        let protagonistEntity = store.semanticEntities.create {
            $0.canonicalName = "Aidan Vale"
            $0.kind = SemanticEntityKind.character.rawValue
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
        }
        let rivalEntity = store.semanticEntities.create {
            $0.canonicalName = "Mara Voss"
            $0.kind = SemanticEntityKind.character.rawValue
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
        }
        _ = store.entityAliases.create {
            $0.name = "Aid"
            $0.normalizedName = "aid"
            $0.semanticEntity = protagonistEntity
        }
        _ = store.entityAliases.create {
            $0.name = "The Envoy"
            $0.normalizedName = "the envoy"
            $0.semanticEntity = protagonistEntity
        }

        let protagonistID = UUID()
        let protagonist = store.characterProfiles.create(id: protagonistID) {
            $0.firstName = "Aidan"
            $0.lastName = "Vale"
            $0.age = 31
            $0.ageText = "early thirties"
            $0.location = "Lume"
            $0.height = "183"
            $0.weight = "78"
            $0.physicalDescription = "Dark hair"
            $0.biography = "Guild envoy"
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
            $0.semanticEntity = protagonistEntity
            $0.sourceDocument = sourceDocument
        }
        let rival = store.characterProfiles.create {
            $0.firstName = "Mara"
            $0.lastName = "Voss"
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
            $0.semanticEntity = rivalEntity
        }
        let measurementID = UUID()
        _ = store.characterMeasurements.create(id: measurementID) {
            $0.name = "Reach"
            $0.value = "190"
            $0.unit = "cm"
            $0.orderIndex = 0
            $0.characterProfile = protagonist
        }
        let noteID = UUID()
        _ = store.characterNotes.create(id: noteID) {
            $0.title = "Voice"
            $0.body = "Avoids contractions."
            $0.kind = "craft"
            $0.source = ProvenanceAgent.human.rawValue
            $0.orderIndex = 0
            $0.createdAt = now
            $0.modifiedAt = now
            $0.characterProfile = protagonist
        }
        let relationshipID = UUID()
        _ = store.characterRelationships.create(id: relationshipID) {
            $0.kind = "rival"
            $0.label = "Political rivals"
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.sourceCharacter = protagonist
            $0.targetCharacter = rival
        }
        let conflictID = UUID()
        let conflict = store.characterConflicts.create(id: conflictID) {
            $0.title = "Duty or family"
            $0.kind = CharacterConflictKind.internal.rawValue
            $0.status = "active"
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.characterProfile = protagonist
        }
        conflict.relatedCharacters = [rival]
        try store.save()

        XCTAssertEqual(try store.characterProfiles.require(id: protagonistID).age, 31)
        XCTAssertEqual(try store.characterMeasurements.count(), 1)
        XCTAssertEqual(try store.characterNotes.count(), 1)
        XCTAssertEqual(try store.characterRelationships.count(), 1)
        XCTAssertEqual(try store.characterConflicts.count(), 1)
        XCTAssertEqual(protagonistEntity.aliases.count, 2)
        XCTAssertEqual(protagonistEntity.characterProfile, protagonist)
        XCTAssertTrue(project.characterProfiles.contains(protagonist))
        XCTAssertTrue(sourceDocument.sourceCharacterProfiles.contains(protagonist))
        XCTAssertTrue(protagonist.outgoingRelationships.contains { $0.id == relationshipID })
        XCTAssertTrue(rival.incomingRelationships.contains { $0.id == relationshipID })
        XCTAssertTrue(protagonist.conflicts.contains { $0.id == conflictID })
        XCTAssertTrue(rival.conflictsInvolving.contains { $0.id == conflictID })

        try store.characterProfiles.delete(id: rival.id)
        try store.save()
        XCTAssertNil(try store.characterRelationships.fetch(id: relationshipID))
        XCTAssertNotNil(try store.characterConflicts.fetch(id: conflictID))
        XCTAssertTrue(try store.characterConflicts.require(id: conflictID).relatedCharacters.isEmpty)

        try store.characterProfiles.delete(id: protagonistID)
        try store.save()
        XCTAssertNil(try store.characterMeasurements.fetch(id: measurementID))
        XCTAssertNil(try store.characterNotes.fetch(id: noteID))
        XCTAssertNil(try store.characterConflicts.fetch(id: conflictID))
    }

    func testV1StoreMigratesToV2() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelDirectory = root.appendingPathComponent(
            "Sources/AuthorData/Resources/AuthorData.momd"
        )
        let v1URL = modelDirectory.appendingPathComponent("AuthorDataV1.mom")
        let v2URL = modelDirectory.appendingPathComponent("AuthorDataV2.mom")
        XCTAssertNotNil(NSManagedObjectModel(contentsOf: v2URL))
        let v1Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v1URL))

        let storeDirectory = root.appendingPathComponent(".build/CharacterDossierTests")
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = storeDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
        }

        let oldContainer = NSPersistentContainer(name: "AuthorData", managedObjectModel: v1Model)
        let description = NSPersistentStoreDescription(url: storeURL)
        oldContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let project = NSEntityDescription.insertNewObject(
            forEntityName: WritingProject.entityName,
            into: oldContainer.viewContext
        ) as! WritingProject
        project.id = UUID()
        project.title = "Legacy"
        project.sourceIdentifier = "legacy-project"
        project.sourceFormat = "native"
        project.createdAt = Date()
        project.modifiedAt = Date()
        try oldContainer.viewContext.save()
        for persistentStore in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(persistentStore)
        }

        let migratedStore = try AuthorDataStore(storeURL: storeURL)
        XCTAssertEqual(try migratedStore.projects.count(), 1)
        XCTAssertEqual(try migratedStore.characterProfiles.count(), 0)
    }
}
