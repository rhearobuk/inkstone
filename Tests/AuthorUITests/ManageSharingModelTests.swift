import AuthorData
import Foundation
import Testing
@testable import AuthorUI

@Suite("Manage Sharing model")
@MainActor
struct ManageSharingModelTests {
    @Test("CloudKit duplicate group IDs do not crash refresh")
    func duplicateGroupIDsAreReconciled() async throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Project"
            $0.sourceIdentifier = "project"
            $0.sourceFormat = "native"
            $0.createdAt = Date()
            $0.modifiedAt = Date()
        }
        let duplicateID = UUID()
        _ = store.sharingGroups.create(id: duplicateID) {
            $0.projectID = project.id
            $0.scopeRootID = project.id
            $0.domain = SharingGroupDomain.feedback.rawValue
            $0.state = "ready"
            $0.modifiedAt = Date(timeIntervalSince1970: 1)
        }
        _ = store.sharingGroups.create(id: duplicateID) {
            $0.projectID = project.id
            $0.scopeRootID = project.id
            $0.domain = SharingGroupDomain.manuscript.rawValue
            $0.state = "awaitingAcceptance"
            $0.modifiedAt = Date(timeIntervalSince1970: 2)
        }
        _ = store.shareParticipants.create {
            $0.sharingGroupID = duplicateID
            $0.cloudKitIdentity = "reader@example.com"
            $0.inkstoneRole = SharingRole.reviewer.rawValue
            $0.cloudKitPermission = "readWrite"
            $0.invitationState = "pending"
            $0.modifiedAt = Date()
        }
        try store.save()

        let model = ManageSharingModel(
            projects: [project],
            service: CloudKitSharingService(dataStore: store)
        )
        await model.refresh()

        #expect(model.rows.count == 1)
        #expect(model.rows.first?.accessGroups.map(\.name) == ["Manuscript"])
    }
}
