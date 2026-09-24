import Foundation
import Testing
@testable import AuthorData

@Suite("Canonical production sharing graph", .serialized)
@MainActor
struct CanonicalSharingGraphTests {
    @Test("Scoped sharing uses the canonical manuscript records")
    func canonicalScopedManuscript() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Flexible Outline"; $0.sourceIdentifier = "project"; $0.sourceFormat = "native"
            $0.createdAt = Date(); $0.modifiedAt = Date()
        }
        let book = store.documents.create {
            $0.project = project; $0.sourceIdentifier = "book"; $0.title = "Book"
            $0.kind = DocumentKind.folder.rawValue; $0.narrativeType = NarrativeType.book.rawValue
        }
        let chapter = store.documents.create {
            $0.project = project; $0.parent = book; $0.sourceIdentifier = "chapter"; $0.title = "Chapter"
            $0.kind = DocumentKind.text.rawValue; $0.narrativeType = NarrativeType.chapter.rawValue
            $0.plainText = "Canonical chapter text"
        }
        let bookGroup = store.sharingGroups.create {
            $0.projectID = project.id; $0.scopeRootID = book.id
            $0.domain = SharingGroupDomain.manuscript.rawValue; $0.state = "preparing"
        }
        try store.save()
        let service = CloudKitSharingService(dataStore: store)

        try service.prepareScopedManuscript(for: bookGroup, project: project, documents: [book, chapter])

        #expect(book.sharingGroupID == bookGroup.id)
        #expect(chapter.sharingGroupID == bookGroup.id)
        #expect(chapter.project == project)
        let sharedDocuments = try store.documents.fetchAll(predicate: NSPredicate(
            format: "sharingGroupID == %@", bookGroup.id as CVarArg
        ))
        #expect(Set(sharedDocuments.map(\.id)) == [book.id, chapter.id])
        #expect(try store.documents.count() == 2)
        chapter.plainText = "Live canonical edit"
        #expect(sharedDocuments.first(where: { $0.id == chapter.id })?.plainText == "Live canonical edit")
        #expect(try store.projects.fetchAll(predicate: NSPredicate(
            format: "sourceFormat == %@", CloudKitSharingService.scopedProjectionSourceFormat
        )).count == 1)
        let scopedBookProject = try #require(store.projects.fetchAll(predicate: NSPredicate(
            format: "sourceIdentifier == %@",
            "scoped-share.\(bookGroup.id.uuidString)"
        )).first)
        #expect(scopedBookProject.id == bookGroup.id)
        #expect(scopedBookProject.id != project.id)
        #expect(scopedBookProject.title == "Book")
        #expect(sharedDocuments.allSatisfy { $0.projectID == project.id })

        // Retrying preparation replaces membership exactly; it must never retain records
        // from an earlier, broader preview.
        try service.prepareScopedManuscript(for: bookGroup, project: project, documents: [chapter])
        let narrowedDocuments = try store.documents.fetchAll(predicate: NSPredicate(
            format: "sharingGroupID == %@", bookGroup.id as CVarArg
        ))
        #expect(narrowedDocuments.map(\.id) == [chapter.id])
        #expect(book.sharingGroupID == nil)
        #expect(try store.documents.count() == 2)
        let allowed = Set(narrowedDocuments.map(\.objectID)).union([
            bookGroup.objectID,
            scopedBookProject.objectID
        ])
        #expect(CoreDataSharingPreflight.audit(root: bookGroup, allowedObjectIDs: allowed).isObjectGraphSafe)
    }

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
