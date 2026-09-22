import CoreData
import Foundation
import Testing
@testable import AuthorData

@Suite("Group-scoped sharing prototype", .serialized)
@MainActor
struct GroupScopedSharingPrototypeTests {
    @Test("Group graphs stay isolated and canonical text exists once")
    func groupGraphIsolation() throws {
        let fixture = try GroupScopedFixture()
        let firstDocumentID = UUID()
        let secondDocumentID = UUID()

        let privateContext = fixture.insert("PrivateDocumentContext", values: [
            "id": UUID(), "documentID": firstDocumentID,
            "privateStatus": "Unannounced ending",
            "historicalDraft": "A discarded version that must never be shared."
        ])
        let firstGroup = fixture.insert("SharingGroup", values: [
            "id": UUID(), "scopeRootID": firstDocumentID, "name": "Book one reviewers"
        ])
        let firstDocument = fixture.insert("SharedDocument", values: [
            "id": firstDocumentID, "group": firstGroup,
            "title": "Opening scene", "currentText": "The canonical current text."
        ])
        let secondGroup = fixture.insert("SharingGroup", values: [
            "id": UUID(), "scopeRootID": secondDocumentID, "name": "Book two reviewers"
        ])
        let secondDocument = fixture.insert("SharedDocument", values: [
            "id": secondDocumentID, "group": secondGroup,
            "title": "Private second book", "currentText": "Text outside the first scope."
        ])
        try fixture.save()

        let allowedIDs = Set([firstGroup.objectID, firstDocument.objectID])
        let report = CoreDataSharingPreflight.audit(
            root: firstGroup,
            allowedObjectIDs: allowedIDs
        )

        #expect(report.isObjectGraphSafe)
        #expect(report.visitedObjectCount == 2)
        #expect(!allowedIDs.contains(privateContext.objectID))
        #expect(!allowedIDs.contains(secondGroup.objectID))
        #expect(!allowedIDs.contains(secondDocument.objectID))
        #expect(try fixture.count("SharedDocument", id: firstDocumentID) == 1)
        #expect(fixture.model.entitiesByName["PrivateDocumentContext"]?
            .attributesByName["currentText"] == nil)
    }

    @Test("The UI joins private and shared records by UUID")
    func projectionUsesIDOnlyJoin() throws {
        let fixture = try GroupScopedFixture()
        let documentID = UUID()
        _ = fixture.insert("PrivateDocumentContext", values: [
            "id": UUID(), "documentID": documentID,
            "privateStatus": "Needs author revision", "historicalDraft": "Old text"
        ])
        let group = fixture.insert("SharingGroup", values: [
            "id": UUID(), "scopeRootID": documentID, "name": "Project editors"
        ])
        _ = fixture.insert("SharedDocument", values: [
            "id": documentID, "group": group,
            "title": "Scene", "currentText": "Only canonical current text"
        ])
        try fixture.save()

        let projection = try fixture.project(documentID: documentID)

        #expect(projection.currentText == "Only canonical current text")
        #expect(projection.privateStatus == "Needs author revision")
        #expect(projection.historicalDraft == "Old text")
        #expect(try fixture.count("SharedDocument") == 1)
        #expect(try fixture.count("PrivateDocumentContext") == 1)
    }

    @Test("Feedback is disconnected from manuscript text")
    func feedbackUsesSeparateGroup() throws {
        let fixture = try GroupScopedFixture()
        let documentID = UUID()
        let manuscriptGroupID = UUID()
        let manuscriptGroup = fixture.insert("SharingGroup", values: [
            "id": manuscriptGroupID, "scopeRootID": documentID, "name": "Read-only manuscript"
        ])
        let document = fixture.insert("SharedDocument", values: [
            "id": documentID, "group": manuscriptGroup,
            "title": "Scene", "currentText": "Canonical text"
        ])
        let feedbackGroup = fixture.insert("FeedbackGroup", values: [
            "id": UUID(), "manuscriptGroupID": manuscriptGroupID, "name": "Writable feedback"
        ])
        let feedback = fixture.insert("Feedback", values: [
            "id": UUID(), "group": feedbackGroup,
            "documentID": documentID, "body": "Consider a stronger opening."
        ])
        try fixture.save()

        let report = CoreDataSharingPreflight.audit(
            root: feedbackGroup,
            allowedObjectIDs: [feedbackGroup.objectID, feedback.objectID]
        )

        #expect(report.isObjectGraphSafe)
        #expect(report.visitedObjectCount == 2)
        #expect(document.value(forKey: "currentText") as? String == "Canonical text")
    }

    @Test("Membership withdrawal preserves canonical identity")
    func membershipWithdrawalPreservesDocument() throws {
        let fixture = try GroupScopedFixture()
        let documentID = UUID()
        let group = fixture.insert("SharingGroup", values: [
            "id": UUID(), "scopeRootID": documentID, "name": "Chapter reviewers"
        ])
        let document = fixture.insert("SharedDocument", values: [
            "id": documentID, "group": group,
            "title": "Chapter", "currentText": "Canonical text"
        ])
        let member = fixture.insert("GroupMember", values: [
            "id": UUID(), "group": group, "userRecordName": "reviewer"
        ])
        try fixture.save()
        let originalObjectID = document.objectID

        fixture.context.delete(member)
        try fixture.save()
        #expect(try fixture.count("GroupMember") == 0)
        #expect(try fixture.count("SharedDocument") == 1)
        #expect(document.objectID == originalObjectID)

        _ = fixture.insert("GroupMember", values: [
            "id": UUID(), "group": group, "userRecordName": "reviewer"
        ])
        try fixture.save()
        #expect(try fixture.count("GroupMember") == 1)
        #expect(try fixture.count("SharedDocument") == 1)
        #expect(document.objectID == originalObjectID)
    }
}

@MainActor
private final class GroupScopedFixture {
    struct Projection {
        let currentText: String
        let privateStatus: String
        let historicalDraft: String
    }

    let model: NSManagedObjectModel
    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }

    init() throws {
        model = Self.makeModel()
        container = NSPersistentContainer(name: "GroupScopedPrototype", managedObjectModel: model)
        let privateStore = Self.store(configuration: "Private")
        let collaborationStore = Self.store(configuration: "Collaboration")
        container.persistentStoreDescriptions = [privateStore, collaborationStore]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    func insert(_ entityName: String, values: [String: Any]) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
        for (key, value) in values { object.setValue(value, forKey: key) }
        return object
    }

    func save() throws {
        try context.save()
        context.processPendingChanges()
    }

    func count(_ entityName: String, id: UUID? = nil) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        if let id { request.predicate = NSPredicate(format: "id == %@", id as CVarArg) }
        return try context.count(for: request)
    }

    func project(documentID: UUID) throws -> Projection {
        func first(_ entity: String) throws -> NSManagedObject {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "%K == %@", entity == "SharedDocument" ? "id" : "documentID", documentID as CVarArg)
            return try #require(context.fetch(request).first)
        }
        let shared = try first("SharedDocument")
        let privateContext = try first("PrivateDocumentContext")
        return Projection(
            currentText: try #require(shared.value(forKey: "currentText") as? String),
            privateStatus: try #require(privateContext.value(forKey: "privateStatus") as? String),
            historicalDraft: try #require(privateContext.value(forKey: "historicalDraft") as? String)
        )
    }

    private static func store(configuration: String) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.configuration = configuration
        description.url = URL(fileURLWithPath: "/dev/null/\(configuration)-\(UUID().uuidString)")
        return description
    }

    private static func makeModel() -> NSManagedObjectModel {
        let privateContext = entity("PrivateDocumentContext", [
            attribute("id", .UUIDAttributeType), attribute("documentID", .UUIDAttributeType),
            attribute("privateStatus", .stringAttributeType), attribute("historicalDraft", .stringAttributeType)
        ])
        let sharingGroup = entity("SharingGroup", [
            attribute("id", .UUIDAttributeType), attribute("scopeRootID", .UUIDAttributeType),
            attribute("name", .stringAttributeType)
        ])
        let sharedDocument = entity("SharedDocument", [
            attribute("id", .UUIDAttributeType), attribute("title", .stringAttributeType),
            attribute("currentText", .stringAttributeType)
        ])
        let groupMember = entity("GroupMember", [
            attribute("id", .UUIDAttributeType), attribute("userRecordName", .stringAttributeType)
        ])
        let feedbackGroup = entity("FeedbackGroup", [
            attribute("id", .UUIDAttributeType), attribute("manuscriptGroupID", .UUIDAttributeType),
            attribute("name", .stringAttributeType)
        ])
        let feedback = entity("Feedback", [
            attribute("id", .UUIDAttributeType), attribute("documentID", .UUIDAttributeType),
            attribute("body", .stringAttributeType)
        ])
        relate(sharingGroup, "documents", sharedDocument, "group")
        relate(sharingGroup, "members", groupMember, "group")
        relate(feedbackGroup, "feedback", feedback, "group")

        let model = NSManagedObjectModel()
        model.entities = [privateContext, sharingGroup, sharedDocument, groupMember, feedbackGroup, feedback]
        model.setEntities([privateContext], forConfigurationName: "Private")
        model.setEntities(
            [sharingGroup, sharedDocument, groupMember, feedbackGroup, feedback],
            forConfigurationName: "Collaboration"
        )
        return model
    }

    private static func entity(_ name: String, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = attributes
        return entity
    }

    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }

    private static func relate(
        _ source: NSEntityDescription, _ sourceName: String,
        _ destination: NSEntityDescription, _ inverseName: String
    ) {
        let forward = NSRelationshipDescription()
        forward.name = sourceName
        forward.destinationEntity = destination
        forward.maxCount = 0
        forward.deleteRule = .cascadeDeleteRule
        forward.isOptional = true
        let inverse = NSRelationshipDescription()
        inverse.name = inverseName
        inverse.destinationEntity = source
        inverse.maxCount = 1
        inverse.deleteRule = .nullifyDeleteRule
        inverse.isOptional = true
        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        source.properties.append(forward)
        destination.properties.append(inverse)
    }
}
