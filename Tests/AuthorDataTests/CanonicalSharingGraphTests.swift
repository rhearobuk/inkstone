import Foundation
import Testing
@testable import AuthorData

@Suite("Canonical production sharing graph", .serialized)
@MainActor
struct CanonicalSharingGraphTests {
    @Test("Manuscript preparation detaches private graph without copying text")
    func manuscriptBoundary() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Project"; $0.sourceIdentifier = "project"; $0.sourceFormat = "native"
            $0.createdAt = Date(); $0.modifiedAt = Date()
        }
        let document = store.documents.create {
            $0.project = project; $0.sourceIdentifier = "scene"; $0.title = "Scene"
            $0.kind = "text"; $0.plainText = "Canonical text"; $0.orderIndex = 0
        }
        let revision = store.revisions.create {
            $0.document = document; $0.sequence = 1; $0.createdAt = Date()
            $0.source = "private"; $0.contentHash = "hash"; $0.plainText = "Private history"
        }
        let group = store.sharingGroups.create {
            $0.projectID = project.id; $0.scopeRootID = document.id
            $0.domain = SharingGroupDomain.manuscript.rawValue; $0.state = "preparing"
        }
        try store.save()

        try CanonicalSharingGraphPreparer().prepareManuscript([document], for: group)
        try store.save()

        #expect(document.plainText == "Canonical text")
        #expect(document.sharingGroupID == group.id)
        #expect(revision.documentID == document.id)
        #expect(document.primitiveValue(forKey: "revisions") as? Set<Revision> == [])
        #expect(project.documents.contains(document))
        #expect(try store.documents.count(predicate: NSPredicate(format: "id == %@", document.id as CVarArg)) == 1)
        let report = CoreDataSharingPreflight.audit(
            root: group,
            allowedObjectIDs: [group.objectID, document.objectID]
        )
        #expect(report.isObjectGraphSafe)
        #expect(report.visitedObjectCount == 2)
    }

    @Test("Participant feedback is created in the shared store and joined only by UUID")
    func sharedFeedbackInsertion() throws {
        let store = try AuthorDataStore(inMemory: true)
        let groups = try store.repository(for: SharingGroup.self, scope: .participantShared)
        let group = groups.create {
            $0.projectID = UUID(); $0.scopeRootID = UUID()
            $0.domain = SharingGroupDomain.feedback.rawValue; $0.state = "active"
        }
        try store.save()

        let annotation = try CloudKitSharingService(dataStore: store).createFeedback(
            body: "Strengthen the opening.",
            documentID: UUID(),
            in: group,
            author: "Reviewer"
        )

        #expect(annotation.objectID.persistentStore == store.sharedPersistentStore)
        #expect(annotation.feedbackGroup == group)
        #expect(annotation.primitiveValue(forKey: "document") == nil)
    }
}
