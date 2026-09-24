import Foundation
import Testing
@testable import AuthorData

@Suite("Central review access policy")
struct ReviewAccessPolicyTests {
    private let projectID = UUID()
    private let rootID = UUID()
    private let reviewable = "status.reviewable"

    @Test("Every participant role receives only its owner-authorized capabilities", arguments: [
        (ReviewParticipantRole.viewer, Set([ReviewCapability.readManuscript])),
        (.reviewer, Set([.readManuscript, .createFeedback])),
        (.editor, Set([.readManuscript, .createFeedback])),
        (.collaborator, Set([.readManuscript, .createFeedback, .editManuscript]))
    ])
    func roleCapabilities(role: ReviewParticipantRole, expected: Set<ReviewCapability>) throws {
        let result = try resolve(grant: .init(role: role))
        #expect(result.capabilities == expected)
    }

    @Test("Direct and inherited Do Not Publish are excluded")
    func publishingExclusions() throws {
        let folderID = UUID()
        let childID = UUID()
        let directID = UUID()
        let records = baseRecords + [
            record(folderID, parent: rootID, kind: .structure, include: false),
            record(childID, parent: folderID, kind: .manuscriptText, status: reviewable),
            record(directID, parent: rootID, kind: .manuscriptText, status: reviewable, include: false)
        ]
        let result = try resolve(records: records)
        #expect(result.exclusions[folderID] == .directDoNotPublish)
        #expect(result.exclusions[childID] == .inheritedDoNotPublish)
        #expect(result.exclusions[directID] == .directDoNotPublish)
    }

    @Test("Statuses use stable identifiers and missing or deleted status fails closed", arguments: [
        (Optional("status.reviewable"), Optional<ReviewExclusionReason>.none),
        (Optional("Reviewable"), Optional(.statusNotReviewable)),
        (Optional("status.deleted"), Optional(.statusNotReviewable)),
        (Optional<String>.none, Optional(.missingOrDeletedStatus))
    ])
    func stableStatuses(status: String?, expectedReason: ReviewExclusionReason?) throws {
        let id = UUID()
        let result = try resolve(records: baseRecords + [record(id, parent: rootID, kind: .manuscriptText, status: status)])
        #expect(result.exclusions[id] == expectedReason)
        #expect(result.included.contains { $0.recordID == id } == (expectedReason == nil))
    }

    @Test("Every configured status identifier is eligible")
    func allConfiguredStatuses() throws {
        let firstID = UUID()
        let secondID = UUID()
        let policy = ReviewAccessPolicy(
            version: 1,
            projectID: projectID,
            scopeRootID: rootID,
            reviewableStatusIdentifiers: ["status.first", "status.second"]
        )
        let result = try ReviewAccessPolicyResolver.preview(
            policy: policy,
            grant: .init(role: .reviewer),
            records: baseRecords + [
                record(firstID, parent: rootID, kind: .manuscriptText, status: "status.first"),
                record(secondID, parent: rootID, kind: .manuscriptText, status: "status.second")
            ]
        )
        #expect(Set(result.included.map(\.recordID)).isSuperset(of: [firstID, secondID]))
        #expect(result.includedCount == 3)
        #expect(result.excludedCount == 0)
    }

    @Test("Private resources and feedback cannot pull manuscript into a share")
    func privateBoundaries() throws {
        let resourceID = UUID()
        let feedbackID = UUID()
        let result = try resolve(records: baseRecords + [
            record(resourceID, parent: rootID, kind: .privateResource),
            record(feedbackID, parent: rootID, kind: .feedback)
        ], grant: .init(role: .editor, storyBible: .edit))
        #expect(result.exclusions[resourceID] == .privateResource)
        #expect(result.exclusions[feedbackID] == .separateFeedbackBoundary)
    }

    @Test("Story Bible access is independent and selected access is non-transitive")
    func selectedStoryContext() throws {
        let selectedID = UUID()
        let relatedID = UUID()
        let records = baseRecords + [
            record(selectedID, kind: .storyContext),
            record(relatedID, parent: selectedID, kind: .storyContext)
        ]
        let result = try resolve(records: records, grant: .init(role: .viewer, storyBible: .selected([selectedID])))
        #expect(result.included.contains { $0.recordID == selectedID && $0.payload == .storyContext })
        #expect(result.exclusions[relatedID] == .storyBibleNotGranted)
    }

    @Test("Invalid cycles, missing parents, and cross-project records are rejected")
    func invalidTrees() {
        let first = UUID()
        let second = UUID()
        #expect(throws: ReviewAccessPolicyError.invalidHierarchy(first)) {
            try resolve(records: [
                record(rootID, kind: .structure),
                record(first, parent: second, kind: .structure),
                record(second, parent: first, kind: .structure)
            ])
        }
        let missing = UUID()
        let orphan = UUID()
        #expect(throws: ReviewAccessPolicyError.missingParent(recordID: orphan, parentID: missing)) {
            try resolve(records: baseRecords + [record(orphan, parent: missing, kind: .manuscriptText, status: reviewable)])
        }
        let foreign = ReviewPolicyRecord(id: UUID(), projectID: UUID(), parentID: nil, kind: .manuscriptText)
        #expect(throws: ReviewAccessPolicyError.crossProjectRecord(foreign.id)) {
            try resolve(records: baseRecords + [foreign])
        }
    }

    @Test("Publication rejects a stale preview and reuses the same policy result")
    func stalePreviewProtection() throws {
        let manuscriptID = UUID()
        let records = baseRecords + [record(manuscriptID, parent: rootID, kind: .manuscriptText, status: reviewable)]
        let policy = makePolicy()
        let grant = OwnerAuthorizedReviewGrant(role: .reviewer)
        let preview = try ReviewAccessPolicyResolver.preview(policy: policy, grant: grant, records: records)
        let publication = try ReviewAccessPolicyResolver.authorizePublication(
            policy: policy, grant: grant, records: records, previewToken: preview.previewToken
        )
        #expect(preview.included.map(\.recordID) == publication.included.map(\.recordID))
        #expect(preview.included.allSatisfy { $0.boundary == .pendingCloudPublication })
        #expect(publication.included.allSatisfy { $0.boundary == .serverEnforced })
        #expect(publication.capabilityEnforcement == .appEnforcedWithinShare)

        let changed = records + [record(UUID(), parent: rootID, kind: .manuscriptText, status: reviewable)]
        #expect(throws: ReviewAccessPolicyError.stalePreview) {
            try ReviewAccessPolicyResolver.authorizePublication(
                policy: policy, grant: grant, records: changed, previewToken: preview.previewToken
            )
        }
    }

    @Test("Policy changes produce explicit publication and withdrawal actions")
    func lifecycleTransition() throws {
        let retainedID = UUID()
        let withdrawnID = UUID()
        let addedID = UUID()
        let policy = makePolicy()
        let grant = OwnerAuthorizedReviewGrant(role: .reviewer)
        let originalRecords = baseRecords + [
            record(retainedID, parent: rootID, kind: .manuscriptText, status: reviewable),
            record(withdrawnID, parent: rootID, kind: .manuscriptText, status: reviewable)
        ]
        let preview = try ReviewAccessPolicyResolver.preview(policy: policy, grant: grant, records: originalRecords)
        let published = try ReviewAccessPolicyResolver.authorizePublication(
            policy: policy, grant: grant, records: originalRecords, previewToken: preview.previewToken
        )
        let changed = baseRecords + [
            record(retainedID, parent: rootID, kind: .manuscriptText, status: reviewable),
            record(withdrawnID, parent: rootID, kind: .manuscriptText, status: "status.private"),
            record(addedID, parent: rootID, kind: .manuscriptText, status: reviewable)
        ]
        let nextPreview = try ReviewAccessPolicyResolver.preview(policy: policy, grant: grant, records: changed)
        let transition = ReviewAccessPolicyResolver.transition(from: published, to: nextPreview)
        #expect(transition.publishRecordIDs == [addedID])
        #expect(transition.withdrawRecordIDs == [withdrawnID])
    }

    private var baseRecords: [ReviewPolicyRecord] { [record(rootID, kind: .structure)] }

    private func makePolicy() -> ReviewAccessPolicy {
        .init(version: 1, projectID: projectID, scopeRootID: rootID, reviewableStatusIdentifiers: [reviewable])
    }

    private func resolve(
        records: [ReviewPolicyRecord]? = nil,
        grant: OwnerAuthorizedReviewGrant = .init(role: .reviewer)
    ) throws -> ReviewAccessPolicyResult {
        try ReviewAccessPolicyResolver.preview(policy: makePolicy(), grant: grant, records: records ?? baseRecords)
    }

    private func record(
        _ id: UUID,
        parent: UUID? = nil,
        kind: ReviewPolicyRecordKind,
        status: String? = nil,
        include: Bool? = nil
    ) -> ReviewPolicyRecord {
        .init(id: id, projectID: projectID, parentID: parent, kind: kind,
              statusIdentifier: status, includeInCompile: include)
    }
}
