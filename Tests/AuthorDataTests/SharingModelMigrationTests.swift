import CoreData
import Foundation
import Testing
@testable import AuthorData

@Suite("Sharing model migration", .serialized)
@MainActor
struct SharingModelMigrationTests {
    @Test("V11 libraries migrate privately to V12 without changing canonical content")
    func v11MigratesPrivately() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.sqlite")
        let oldModel = try #require(NSManagedObjectModel(contentsOf: modelURL(version: 11)))
        let oldContainer = NSPersistentContainer(name: "AuthorData", managedObjectModel: oldModel)
        let oldDescription = NSPersistentStoreDescription(url: storeURL)
        oldDescription.shouldAddStoreAsynchronously = false
        oldContainer.persistentStoreDescriptions = [oldDescription]
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let projectID = UUID()
        let documentID = UUID()
        let project = NSEntityDescription.insertNewObject(
            forEntityName: WritingProject.entityName,
            into: oldContainer.viewContext
        ) as! WritingProject
        project.id = projectID
        project.title = "Private existing project"
        project.sourceIdentifier = "migration.project"
        project.sourceFormat = "native"
        project.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        project.modifiedAt = project.createdAt
        let document = NSEntityDescription.insertNewObject(
            forEntityName: Document.entityName,
            into: oldContainer.viewContext
        ) as! Document
        document.id = documentID
        document.sourceIdentifier = "migration.scene"
        document.title = "Existing private scene"
        document.kind = DocumentKind.text.rawValue
        document.orderIndex = 0
        document.plainText = "Preserve this canonical text."
        document.project = project
        try oldContainer.viewContext.save()
        try close(oldContainer)

        let migrated = try AuthorDataStore(storeURL: storeURL)
        #expect(migrated.container.managedObjectModel.versionIdentifiers == ["12"])
        let migratedDocument = try #require(try migrated.documents.fetch(id: documentID))
        #expect(migratedDocument.id == documentID)
        #expect(migratedDocument.plainText == "Preserve this canonical text.")
        #expect(migratedDocument.project.id == projectID)
        #expect(migratedDocument.projectID == projectID)
        #expect(migratedDocument.parentID == nil)
        #expect(migratedDocument.sharingGroupID == nil)
        #expect(try migrated.sharingGroups.count() == 0)
        #expect(try migrated.shareParticipants.count() == 0)
        try close(migrated.container)
    }

    @Test("V12 persists group metadata without Core Data relationships")
    func groupMetadataRoundTrips() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("latest.sqlite")
        let groupID = UUID()
        let projectID = UUID()
        let rootID = UUID()
        let participantID = UUID()

        let store = try AuthorDataStore(storeURL: storeURL)
        let group = store.sharingGroups.create(id: groupID) {
            $0.projectID = projectID
            $0.scopeRootID = rootID
            $0.domain = SharingGroupDomain.manuscript.rawValue
            $0.state = "private"
            $0.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        _ = store.shareParticipants.create(id: participantID) {
            $0.sharingGroupID = group.id
            $0.inkstoneRole = "reviewer"
            $0.cloudKitPermission = "readOnly"
            $0.invitationState = "pending"
            $0.createdAt = Date(timeIntervalSince1970: 1_700_000_001)
        }
        try store.save()
        try close(store.container)

        let reopened = try AuthorDataStore(storeURL: storeURL)
        let reopenedGroup = try reopened.sharingGroups.require(id: groupID)
        let participant = try reopened.shareParticipants.require(id: participantID)
        #expect(reopenedGroup.projectID == projectID)
        #expect(reopenedGroup.scopeRootID == rootID)
        #expect(reopenedGroup.domain == SharingGroupDomain.manuscript.rawValue)
        #expect(reopenedGroup.state == "private")
        #expect(participant.sharingGroupID == groupID)
        #expect(participant.cloudKitPermission == "readOnly")
        try close(reopened.container)
    }

    private func modelURL(version: Int) -> URL {
        projectRoot.appendingPathComponent(
            "Sources/AuthorData/Resources/AuthorData.momd/AuthorDataV\(version).mom"
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeStoreDirectory() throws -> URL {
        let directory = projectRoot.appendingPathComponent(
            ".build/sharing-model-migration-tests/\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func close(_ container: NSPersistentContainer) throws {
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
