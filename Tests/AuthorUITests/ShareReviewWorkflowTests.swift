import AuthorData
import Foundation
import Testing
@testable import AuthorUI

@Suite("Share for Review workflow")
@MainActor
struct ShareReviewWorkflowTests {
    @Test("Review workflow defaults to Reviewer with no Story Bible access")
    func secureDefaultsAndExactPreview() throws {
        let fixture = try Fixture()
        let model = ShareReviewWorkflowModel(
            project: fixture.project,
            scopeRoot: fixture.book,
            service: CloudKitSharingService(dataStore: fixture.store)
        )
        #expect(model.role == .reviewer)
        #expect(model.storyBibleGrant == .none)
        #expect(model.preview?.includedCount == 2)
        #expect(model.preview?.exclusionCount(for: .directDoNotPublish) == 1)
    }

    @Test("Partial invitation groups remain visibly failed and retryable")
    func partialProgress() throws {
        let fixture = try Fixture()
        let model = ShareReviewWorkflowModel(
            project: fixture.project,
            scopeRoot: fixture.book,
            service: CloudKitSharingService(dataStore: fixture.store)
        )
        model.record(.init(groupID: UUID(), succeeded: true), for: .manuscript)
        model.record(.init(groupID: UUID(), succeeded: false, message: "Offline"), for: .feedback)
        #expect(model.groupStates[.manuscript] == .succeeded)
        #expect(model.groupStates[.feedback] == .failed("Offline"))
    }

    @MainActor
    private final class Fixture {
        let store: AuthorDataStore
        let project: WritingProject
        let book: Document

        init() throws {
            let createdStore = try AuthorDataStore(inMemory: true)
            let createdProject = createdStore.projects.create {
                $0.title = "Book Project"; $0.sourceIdentifier = "project"; $0.sourceFormat = "native"
                $0.createdAt = Date(); $0.modifiedAt = Date()
            }
            let status = createdStore.statusDefinitions.create {
                $0.project = createdProject; $0.sourceIdentifier = "status.review"; $0.title = "Review"; $0.isDefault = true
            }
            let createdBook = createdStore.documents.create {
                $0.project = createdProject; $0.sourceIdentifier = "book"; $0.title = "Book"
                $0.kind = DocumentKind.folder.rawValue; $0.narrativeType = NarrativeType.book.rawValue; $0.orderIndex = 0
            }
            _ = createdStore.documents.create {
                $0.project = createdProject; $0.parent = createdBook; $0.sourceIdentifier = "scene"; $0.title = "Scene"
                $0.kind = DocumentKind.text.rawValue; $0.statusIdentifier = status.sourceIdentifier; $0.orderIndex = 0
            }
            _ = createdStore.documents.create {
                $0.project = createdProject; $0.parent = createdBook; $0.sourceIdentifier = "private"; $0.title = "Private"
                $0.kind = DocumentKind.text.rawValue; $0.statusIdentifier = status.sourceIdentifier
                $0.includeInCompile = false; $0.orderIndex = 1
            }
            try createdStore.save()
            store = createdStore
            project = createdProject
            book = createdBook
        }
    }
}
