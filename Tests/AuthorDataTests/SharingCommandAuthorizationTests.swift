import Foundation
import Testing
@testable import AuthorData

@Suite("Sharing command authorization")
struct SharingCommandAuthorizationTests {
    private let recordID = UUID()
    private let authorizer = SharingCommandAuthorizer()

    @Test("Every role has the intended command boundary", arguments: [
        (SharingRole.viewer, SharingCommand.readManuscript, true),
        (.viewer, .createFeedback, false),
        (.reviewer, .createFeedback, true),
        (.reviewer, .editProse, false),
        (.editor, .editProse, true),
        (.editor, .editStructure, false),
        (.collaborator, .editStructure, true),
        (.collaborator, .administerSharing, false),
        (.owner, .administerSharing, true),
        (.reviewer, .readPrivateHistory, false)
    ])
    func roleMatrix(role: SharingRole, command: SharingCommand, allowed: Bool) {
        let authorization = SharingAuthorization(role: role, authorizedRecordIDs: [recordID], policyVersion: 1)
        if allowed {
            #expect(throws: Never.self) { try authorizer.authorize(command, recordID: recordID, using: authorization) }
        } else {
            #expect(throws: SharingAuthorizationError.unauthorizedCommand(command)) {
                try authorizer.authorize(command, recordID: recordID, using: authorization)
            }
        }
    }

    @Test("Direct command execution is denied before its operation runs")
    func directCommandBoundary() async {
        let authorization = SharingAuthorization(role: .reviewer, authorizedRecordIDs: [recordID], policyVersion: 1)
        let gateway = PermissionedCommandGateway(authorization: authorization)
        await #expect(throws: SharingAuthorizationError.unauthorizedCommand(.editProse)) {
            try await gateway.perform(.editProse, recordID: recordID) { Issue.record("Mutation ran"); return () }
        }
    }

    @Test("Repository mutations cannot bypass the participant authorization boundary")
    @MainActor
    func persistenceBoundary() throws {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Project"; $0.sourceIdentifier = "project"; $0.sourceFormat = "native"
            $0.createdAt = Date(); $0.modifiedAt = Date()
        }
        let document = store.documents.create {
            $0.project = project; $0.sourceIdentifier = "scene"; $0.title = "Scene"
            $0.kind = DocumentKind.text.rawValue; $0.orderIndex = 0
        }
        try store.save()

        store.sharingAuthorization = SharingAuthorization(
            role: .reviewer,
            authorizedRecordIDs: [document.id],
            policyVersion: 1
        )
        document.plainText = "A prohibited edit"

        #expect(throws: SharingAuthorizationError.unauthorizedCommand(.editProse)) {
            try store.save()
        }
        store.context.rollback()
        #expect(document.plainText != "A prohibited edit")
    }

    @Test("Every independent Story Bible grant is enforced", arguments: [
        (StoryBibleGrant.none, false, false),
        (.selected([]), false, false),
        (.fullRead, true, false),
        (.edit, true, true)
    ])
    func storyBibleMatrix(grant: StoryBibleGrant, canRead: Bool, canEdit: Bool) {
        let authorization = SharingAuthorization(role: .collaborator, authorizedRecordIDs: [recordID],
                                                 storyBibleGrant: grant, policyVersion: 1)
        let capabilities = authorizer.capabilities(for: authorization.role, storyBible: grant)
        #expect(capabilities.contains(.readStoryContext) == canRead)
        #expect(capabilities.contains(.editStoryContext) == canEdit)
    }

    @Test("Missing IDs reveal no private record details")
    func inaccessibleIDsAreOpaque() {
        let authorization = SharingAuthorization(role: .owner, authorizedRecordIDs: [], policyVersion: 1)
        #expect(throws: SharingAuthorizationError.inaccessibleRecord) {
            try authorizer.authorize(.readManuscript, recordID: UUID(), using: authorization)
        }
    }

    @Test("External AI context retains explicit consent")
    func aiConsent() {
        let authorization = SharingAuthorization(role: .reviewer, authorizedRecordIDs: [recordID],
                                                 externalAIConsent: false, policyVersion: 1)
        #expect(throws: SharingAuthorizationError.externalAIConsentRequired) {
            try authorizer.authorize(.useAIContext, recordID: recordID, using: authorization)
        }
    }

    @Test("Feedback is writable without manuscript or private-history write access")
    func separateFeedbackBoundary() {
        let descriptor = FeedbackGroupDescriptor(
            groupID: UUID(), manuscriptGroupID: UUID(), reviewerID: "reviewer",
            anchor: .init(documentID: recordID, revisionID: UUID(), contentHash: "hash", state: .stale)
        )
        #expect(descriptor.manuscriptPermission == "readOnly")
        #expect(descriptor.feedbackPermission == "readWrite")
        #expect(descriptor.anchor.state == .stale)
    }

    @Test("Overlapping canonical context groups fail closed")
    func overlappingGroups() {
        let entityID = UUID()
        #expect(throws: SharingAuthorizationError.unsupportedOverlappingContext(entityID)) {
            try StoryContextGroupValidator().validate(assignments: [entityID: [UUID(), UUID()]])
        }
    }
}
