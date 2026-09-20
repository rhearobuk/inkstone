import CoreData
import XCTest
@testable import AuthorData

@MainActor
final class StoryBibleMigrationTests: XCTestCase {
    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct Fixture {
        let project = UUID()
        let folder = UUID()
        let document = UUID()
        let character = UUID()
        let place = UUID()
        let profile = UUID()
        let card = UUID()
        let note = UUID()
        let alias = UUID()
        let mention = UUID()
        let relationship = UUID()
        let label = UUID()
        let status = UUID()
    }

    func testV10StoreMigratesToV11PreservingStoryBibleGraphAndMetadata() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.sqlite")
        let modelURL = Self.projectRoot.appendingPathComponent(
            "Sources/AuthorData/Resources/AuthorData.momd/AuthorDataV10.mom"
        )
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        XCTAssertNil(model.entitiesByName["Document"]?.attributesByName["storyBibleOrderIndex"])
        XCTAssertNil(model.entitiesByName["SemanticEntity"]?.attributesByName["labelIdentifier"])
        let old = NSPersistentContainer(name: "AuthorData", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        old.persistentStoreDescriptions = [description]
        var loadError: Error?
        old.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        defer { try? close(old) }
        let fixture = Fixture()
        populate(fixture, in: old.viewContext)
        try old.viewContext.save()
        try close(old)

        let migrated = try AuthorDataStore(storeURL: url)
        defer { try? close(migrated.container) }
        XCTAssertEqual(migrated.container.managedObjectModel.versionIdentifiers, ["11"])
        try assertGraph(fixture, in: migrated)
        try assertNewFieldsAreNil(in: migrated)
        let document = try migrated.documents.require(id: fixture.document)
        let place = try migrated.semanticEntities.require(id: fixture.place)
        document.storyBibleOrderIndex = NSNumber(value: Int64(4_294_967_296))
        place.storyBibleOrderIndex = NSNumber(value: Int64(4_294_967_297))
        place.labelIdentifier = "imported.label.7"
        place.statusIdentifier = "imported.status.3"
        try migrated.save()
        try close(migrated.container)

        let reopened = try AuthorDataStore(storeURL: url)
        defer { try? close(reopened.container) }
        try assertGraph(fixture, in: reopened)
        XCTAssertEqual(
            try reopened.documents.require(id: fixture.document).storyBibleOrderIndex?.int64Value,
            4_294_967_296
        )
        let reopenedPlace = try reopened.semanticEntities.require(id: fixture.place)
        XCTAssertEqual(reopenedPlace.storyBibleOrderIndex?.int64Value, 4_294_967_297)
        XCTAssertEqual(reopenedPlace.labelIdentifier, "imported.label.7")
        XCTAssertEqual(reopenedPlace.statusIdentifier, "imported.status.3")
        let importedCharacter = try reopened.semanticEntities.require(id: fixture.character)
        XCTAssertNil(importedCharacter.labelIdentifier)
        XCTAssertNil(importedCharacter.statusIdentifier)
        XCTAssertNil(importedCharacter.storyBibleOrderIndex)
        XCTAssertNil(try reopened.documents.require(id: fixture.folder).storyBibleOrderIndex)
    }

    func testLatestStoreReopensAssignedAndClearedOptionalStoryBibleFields() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("latest.sqlite")
        let fixture = Fixture()
        let original = try AuthorDataStore(storeURL: url)
        defer { try? close(original.container) }
        populate(fixture, in: original.context)
        try assertNewFieldsAreNil(in: original)
        let document = try original.documents.require(id: fixture.document)
        let place = try original.semanticEntities.require(id: fixture.place)
        document.storyBibleOrderIndex = NSNumber(value: Int64.max)
        place.storyBibleOrderIndex = NSNumber(value: Int64(0))
        place.labelIdentifier = "imported.label.7"
        place.statusIdentifier = "imported.status.3"
        try original.save()
        try close(original.container)

        let reopened = try AuthorDataStore(storeURL: url)
        defer { try? close(reopened.container) }
        try assertGraph(fixture, in: reopened)
        let reopenedDocument = try reopened.documents.require(id: fixture.document)
        let reopenedPlace = try reopened.semanticEntities.require(id: fixture.place)
        XCTAssertEqual(reopenedDocument.storyBibleOrderIndex?.int64Value, Int64.max)
        XCTAssertEqual(reopenedPlace.storyBibleOrderIndex?.int64Value, 0)
        XCTAssertEqual(reopenedPlace.labelIdentifier, "imported.label.7")
        XCTAssertEqual(reopenedPlace.statusIdentifier, "imported.status.3")
        reopenedDocument.storyBibleOrderIndex = nil
        reopenedPlace.storyBibleOrderIndex = nil
        reopenedPlace.labelIdentifier = nil
        reopenedPlace.statusIdentifier = nil
        try reopened.save()
        try close(reopened.container)

        let cleared = try AuthorDataStore(storeURL: url)
        defer { try? close(cleared.container) }
        try assertGraph(fixture, in: cleared)
        try assertNewFieldsAreNil(in: cleared)
    }

    func testV11AddsOnlyOptionalStoryBibleAttributes() throws {
        let store = try AuthorDataStore(inMemory: true)
        let model = store.container.managedObjectModel
        let oldURL = Self.projectRoot.appendingPathComponent(
            "Sources/AuthorData/Resources/AuthorData.momd/AuthorDataV10.mom"
        )
        let old = try XCTUnwrap(NSManagedObjectModel(contentsOf: oldURL))
        XCTAssertEqual(model.versionIdentifiers, ["11"])
        XCTAssertEqual(Set(model.entitiesByName.keys), Set(old.entitiesByName.keys))
        let additions: [String: [String: NSAttributeType]] = [
            "Document": ["storyBibleOrderIndex": .integer64AttributeType],
            "SemanticEntity": [
                "storyBibleOrderIndex": .integer64AttributeType,
                "labelIdentifier": .stringAttributeType,
                "statusIdentifier": .stringAttributeType
            ]
        ]
        for entity in model.entities {
            let name = try XCTUnwrap(entity.name)
            let previous = try XCTUnwrap(old.entitiesByName[name])
            let expected = additions[name] ?? [:]
            XCTAssertEqual(
                Set(entity.attributesByName.keys).subtracting(previous.attributesByName.keys),
                Set(expected.keys)
            )
            for (attributeName, type) in expected {
                let attribute = try XCTUnwrap(entity.attributesByName[attributeName])
                XCTAssertEqual(attribute.attributeType, type)
                XCTAssertTrue(attribute.isOptional)
                XCTAssertNil(attribute.defaultValue)
            }
            for (attributeName, attribute) in previous.attributesByName {
                XCTAssertEqual(entity.attributesByName[attributeName]?.versionHash, attribute.versionHash)
            }
            XCTAssertEqual(Set(entity.relationshipsByName.keys), Set(previous.relationshipsByName.keys))
            for (relationshipName, relationship) in previous.relationshipsByName {
                XCTAssertEqual(
                    entity.relationshipsByName[relationshipName]?.versionHash,
                    relationship.versionHash
                )
            }
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty)
            for attribute in entity.attributesByName.values {
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil)
            }
        }
    }

    private func makeStoreDirectory() throws -> URL {
        let directory = Self.projectRoot.appendingPathComponent(
            ".build/story-bible-migration-tests/\(UUID().uuidString)",
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

    private func populate(_ ids: Fixture, in context: NSManagedObjectContext) {
        func insert<T: AuthorManagedObject>(_ type: T.Type, id: UUID) -> T {
            let object = NSEntityDescription.insertNewObject(forEntityName: T.entityName, into: context) as! T
            object.id = id
            return object
        }
        let project = insert(WritingProject.self, id: ids.project)
        project.title = "Synthetic migration project"
        project.sourceIdentifier = "synthetic.project"
        project.sourceFormat = "scrivener"
        project.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        project.modifiedAt = project.createdAt
        let folder = insert(Document.self, id: ids.folder)
        folder.project = project
        folder.sourceIdentifier = "synthetic.folder"
        folder.title = "People"
        folder.kind = "Folder"
        folder.orderIndex = 8
        let document = insert(Document.self, id: ids.document)
        document.project = project
        document.parent = folder
        document.sourceIdentifier = "synthetic.dossier"
        document.title = "Mira"
        document.kind = "Text"
        document.orderIndex = 17
        document.plainText = "Mira lives by the harbor."
        document.labelIdentifier = "imported.label.7"
        document.statusIdentifier = "imported.status.3"
        let label = insert(LabelDefinition.self, id: ids.label)
        label.project = project
        label.sourceIdentifier = "imported.label.7"
        label.title = "Viewpoint"
        label.colorRed = 0.25
        let status = insert(StatusDefinition.self, id: ids.status)
        status.project = project
        status.sourceIdentifier = "imported.status.3"
        status.title = "Revised"
        let character = insert(SemanticEntity.self, id: ids.character)
        character.project = project
        character.canonicalName = "Mira"
        character.kind = "character"
        character.source = "scrivener"
        character.createdAt = project.createdAt
        character.modifiedAt = project.modifiedAt
        let place = insert(SemanticEntity.self, id: ids.place)
        place.project = project
        place.canonicalName = "Harbor"
        place.kind = "location"
        place.source = "human"
        place.createdAt = project.createdAt
        place.modifiedAt = project.modifiedAt
        let profile = insert(CharacterProfile.self, id: ids.profile)
        profile.project = project
        profile.semanticEntity = character
        profile.sourceDocument = document
        profile.firstName = "Mira"
        profile.createdAt = project.createdAt
        profile.modifiedAt = project.modifiedAt
        let card = insert(StoryBibleCard.self, id: ids.card)
        card.project = project
        card.semanticEntity = place
        card.details = "A quiet harbor"
        card.relatedCharacters = [profile]
        card.createdAt = project.createdAt
        card.modifiedAt = project.modifiedAt
        let note = insert(StoryBibleNote.self, id: ids.note)
        note.card = card
        note.body = "The tide is rising."
        note.orderIndex = 2
        note.createdAt = project.createdAt
        note.modifiedAt = project.modifiedAt
        let alias = insert(EntityAlias.self, id: ids.alias)
        alias.semanticEntity = character
        alias.name = "Captain Mira"
        alias.normalizedName = "captain mira"
        let mention = insert(DocumentEntityMention.self, id: ids.mention)
        mention.document = document
        mention.semanticEntity = character
        mention.location = 0
        mention.length = 4
        mention.surfaceText = "Mira"
        mention.source = "human"
        let relationship = insert(StoryBibleRelationship.self, id: ids.relationship)
        relationship.sourceEntity = character
        relationship.targetEntity = place
        relationship.kind = "lives in"
        relationship.createdAt = project.createdAt
        relationship.modifiedAt = project.modifiedAt
    }

    private func assertNewFieldsAreNil(in store: AuthorDataStore) throws {
        for document in try store.documents.fetchAll() {
            XCTAssertNil(document.storyBibleOrderIndex)
        }
        for entity in try store.semanticEntities.fetchAll() {
            XCTAssertNil(entity.storyBibleOrderIndex)
            XCTAssertNil(entity.labelIdentifier)
            XCTAssertNil(entity.statusIdentifier)
        }
    }

    private func assertGraph(_ ids: Fixture, in store: AuthorDataStore) throws {
        let project = try store.projects.require(id: ids.project)
        XCTAssertEqual(project.title, "Synthetic migration project")
        XCTAssertEqual(Set(project.documents.map(\.id)), [ids.folder, ids.document])
        XCTAssertEqual(Set(project.semanticEntities.map(\.id)), [ids.character, ids.place])
        XCTAssertEqual(try store.documents.count(), 2)
        XCTAssertEqual(try store.semanticEntities.count(), 2)
        let document = try store.documents.require(id: ids.document)
        let folder = try store.documents.require(id: ids.folder)
        XCTAssertEqual(document.project.id, ids.project)
        XCTAssertEqual(document.sourceIdentifier, "synthetic.dossier")
        XCTAssertEqual(document.title, "Mira")
        XCTAssertEqual(document.plainText, "Mira lives by the harbor.")
        XCTAssertEqual(document.parent?.id, ids.folder)
        XCTAssertEqual(folder.orderedChildren.map(\.id), [ids.document])
        XCTAssertEqual(document.orderIndex, 17)
        XCTAssertEqual(folder.orderIndex, 8)
        XCTAssertEqual(document.labelIdentifier, "imported.label.7")
        XCTAssertEqual(document.statusIdentifier, "imported.status.3")
        let label = try store.labelDefinitions.require(id: ids.label)
        XCTAssertEqual(label.sourceIdentifier, document.labelIdentifier)
        XCTAssertEqual(label.title, "Viewpoint")
        XCTAssertEqual(label.colorRed?.doubleValue, 0.25)
        XCTAssertEqual(label.project.id, ids.project)
        let status = try store.statusDefinitions.require(id: ids.status)
        XCTAssertEqual(status.sourceIdentifier, document.statusIdentifier)
        XCTAssertEqual(status.title, "Revised")
        XCTAssertEqual(status.project.id, ids.project)
        let character = try store.semanticEntities.require(id: ids.character)
        let place = try store.semanticEntities.require(id: ids.place)
        XCTAssertEqual(character.canonicalName, "Mira")
        XCTAssertEqual(character.kind, "character")
        XCTAssertEqual(place.canonicalName, "Harbor")
        XCTAssertEqual(place.kind, "location")
        XCTAssertEqual(character.characterProfile?.id, ids.profile)
        let profile = try store.characterProfiles.require(id: ids.profile)
        XCTAssertEqual(profile.semanticEntity.id, ids.character)
        XCTAssertEqual(profile.sourceDocument?.id, ids.document)
        XCTAssertEqual(Set(document.sourceCharacterProfiles.map(\.id)), [ids.profile])
        let card = try store.storyBibleCards.require(id: ids.card)
        XCTAssertEqual(place.storyBibleCard?.id, ids.card)
        XCTAssertEqual(card.semanticEntity.id, ids.place)
        XCTAssertEqual(card.details, "A quiet harbor")
        XCTAssertEqual(Set(card.relatedCharacters.map(\.id)), [ids.profile])
        XCTAssertEqual(Set(card.notes.map(\.id)), [ids.note])
        XCTAssertEqual(try store.storyBibleNotes.require(id: ids.note).body, "The tide is rising.")
        XCTAssertEqual(Set(character.aliases.map(\.id)), [ids.alias])
        XCTAssertEqual(try store.entityAliases.require(id: ids.alias).name, "Captain Mira")
        let mention = try store.mentions.require(id: ids.mention)
        XCTAssertEqual(mention.semanticEntity.id, ids.character)
        XCTAssertEqual(mention.document.id, ids.document)
        XCTAssertEqual(mention.surfaceText, "Mira")
        XCTAssertEqual(mention.length, 4)
        XCTAssertEqual(Set(character.mentions.map(\.id)), [ids.mention])
        XCTAssertEqual(Set(document.mentions.map(\.id)), [ids.mention])
        let relationship = try store.storyBibleRelationships.require(id: ids.relationship)
        XCTAssertEqual(relationship.sourceEntity.id, ids.character)
        XCTAssertEqual(relationship.targetEntity.id, ids.place)
        XCTAssertEqual(relationship.kind, "lives in")
        XCTAssertEqual(Set(character.outgoingStoryBibleRelationships.map(\.id)), [ids.relationship])
        XCTAssertEqual(Set(place.incomingStoryBibleRelationships.map(\.id)), [ids.relationship])
    }
}
