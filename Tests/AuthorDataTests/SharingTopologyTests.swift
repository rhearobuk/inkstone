import Foundation
import Testing
@testable import AuthorData

@Suite("Sharing topology")
struct SharingTopologyTests {
    @Test("Private and collaboration records have one valid owner")
    func validOwnershipManifest() throws {
        let projectID = UUID()
        let manuscriptGroup = SharingGroupDescriptor(
            id: UUID(),
            projectID: projectID,
            scopeRootID: UUID(),
            domain: .manuscript
        )
        let feedbackGroup = SharingGroupDescriptor(
            id: UUID(),
            projectID: projectID,
            scopeRootID: manuscriptGroup.scopeRootID,
            domain: .feedback
        )
        let routes = [
            try CanonicalRecordRoute(
                recordID: UUID(),
                projectID: projectID,
                storeScope: .ownerPrivate
            ),
            try CanonicalRecordRoute(
                recordID: manuscriptGroup.scopeRootID,
                projectID: projectID,
                storeScope: .ownerPrivate,
                sharingGroupID: manuscriptGroup.id
            ),
            try CanonicalRecordRoute(
                recordID: UUID(),
                projectID: projectID,
                storeScope: .ownerPrivate,
                sharingGroupID: feedbackGroup.id
            )
        ]

        try SharingTopologyValidator().validate(
            groups: [manuscriptGroup, feedbackGroup],
            routes: routes
        )
    }

    @Test("Owner records may join a group without moving stores")
    func ownerGroupAssignmentIsValid() throws {
        let recordID = UUID()
        let groupID = UUID()
        let route = try CanonicalRecordRoute(
            recordID: recordID,
            projectID: UUID(),
            storeScope: .ownerPrivate,
            sharingGroupID: groupID
        )
        #expect(route.sharingGroupID == groupID)
    }

    @Test("Participant shared records require exactly one sharing group")
    func participantRecordWithoutGroupIsRejected() {
        let recordID = UUID()

        #expect(throws: SharingTopologyError.participantRecordHasNoGroup(recordID)) {
            try CanonicalRecordRoute(
                recordID: recordID,
                projectID: UUID(),
                storeScope: .participantShared
            )
        }
    }

    @Test("A canonical record cannot have two routes")
    func duplicateCanonicalOwnershipIsRejected() throws {
        let projectID = UUID()
        let recordID = UUID()
        let group = SharingGroupDescriptor(
            id: UUID(),
            projectID: projectID,
            scopeRootID: recordID,
            domain: .manuscript
        )
        let first = try CanonicalRecordRoute(
            recordID: recordID,
            projectID: projectID,
            storeScope: .ownerPrivate,
            sharingGroupID: group.id
        )
        let second = try CanonicalRecordRoute(
            recordID: recordID,
            projectID: projectID,
            storeScope: .participantShared,
            sharingGroupID: group.id
        )

        #expect(throws: SharingTopologyError.duplicateCanonicalRecord(recordID)) {
            try SharingTopologyValidator().validate(groups: [group], routes: [first, second])
        }
    }

    @Test("A route cannot silently cross a project boundary")
    func crossProjectGroupIsRejected() throws {
        let recordID = UUID()
        let recordProjectID = UUID()
        let groupProjectID = UUID()
        let group = SharingGroupDescriptor(
            id: UUID(),
            projectID: groupProjectID,
            scopeRootID: recordID,
            domain: .manuscript
        )
        let route = try CanonicalRecordRoute(
            recordID: recordID,
            projectID: recordProjectID,
            storeScope: .ownerPrivate,
            sharingGroupID: group.id
        )

        #expect(throws: SharingTopologyError.crossProjectGroup(
            recordID: recordID,
            recordProjectID: recordProjectID,
            groupProjectID: groupProjectID
        )) {
            try SharingTopologyValidator().validate(groups: [group], routes: [route])
        }
    }

    @Test("Unknown sharing groups are rejected")
    func unknownGroupIsRejected() throws {
        let groupID = UUID()
        let route = try CanonicalRecordRoute(
            recordID: UUID(),
            projectID: UUID(),
            storeScope: .participantShared,
            sharingGroupID: groupID
        )

        #expect(throws: SharingTopologyError.unknownSharingGroup(groupID)) {
            try SharingTopologyValidator().validate(groups: [], routes: [route])
        }
    }
}
