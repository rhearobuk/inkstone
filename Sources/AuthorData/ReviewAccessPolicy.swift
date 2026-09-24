import CryptoKit
import Foundation

public enum ReviewParticipantRole: String, Codable, CaseIterable, Sendable {
    case viewer
    case editor
    case reviewer
    case collaborator

    public var capabilities: Set<ReviewCapability> {
        switch self {
        case .viewer: [.readManuscript]
        case .editor, .reviewer: [.readManuscript, .createFeedback]
        case .collaborator: [.readManuscript, .createFeedback, .editManuscript]
        }
    }
}

public enum ReviewCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case readManuscript
    case createFeedback
    case editManuscript
    case readStoryContext
    case editStoryContext
}

public enum StoryBibleGrant: Codable, Equatable, Hashable, Sendable {
    case none
    case selected(Set<UUID>)
    case fullRead
    case edit
}

public enum ReviewPolicyRecordKind: String, Codable, Sendable {
    case manuscriptText
    case structure
    case storyContext
    case privateResource
    case feedback
}

public struct ReviewPolicyRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let parentID: UUID?
    public let kind: ReviewPolicyRecordKind
    public let statusIdentifier: String?
    public let includeInCompile: Bool?

    public init(
        id: UUID,
        projectID: UUID,
        parentID: UUID? = nil,
        kind: ReviewPolicyRecordKind,
        statusIdentifier: String? = nil,
        includeInCompile: Bool? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.kind = kind
        self.statusIdentifier = statusIdentifier
        self.includeInCompile = includeInCompile
    }
}

public struct ReviewAccessPolicy: Codable, Equatable, Sendable {
    public let version: Int
    public let projectID: UUID
    public let scopeRootID: UUID
    public let reviewableStatusIdentifiers: Set<String>
    public let allowsNavigationMetadata: Bool

    public init(
        version: Int,
        projectID: UUID,
        scopeRootID: UUID,
        reviewableStatusIdentifiers: Set<String>,
        allowsNavigationMetadata: Bool = true
    ) {
        self.version = version
        self.projectID = projectID
        self.scopeRootID = scopeRootID
        self.reviewableStatusIdentifiers = reviewableStatusIdentifiers
        self.allowsNavigationMetadata = allowsNavigationMetadata
    }
}

public struct OwnerAuthorizedReviewGrant: Codable, Equatable, Sendable {
    public let role: ReviewParticipantRole
    public let storyBible: StoryBibleGrant

    public init(role: ReviewParticipantRole, storyBible: StoryBibleGrant = .none) {
        self.role = role
        self.storyBible = storyBible
    }
}

public enum ReviewExclusionReason: String, Codable, CaseIterable, Sendable {
    case outsideScope
    case directDoNotPublish
    case inheritedDoNotPublish
    case statusNotReviewable
    case missingOrDeletedStatus
    case navigationMetadataNotGranted
    case storyBibleNotGranted
    case privateResource
    case separateFeedbackBoundary
}

public enum ReviewPayload: String, Codable, Sendable {
    case manuscriptText
    case navigationMetadata
    case storyContext
}

public enum ReviewBoundaryEnforcement: String, Codable, Sendable {
    case pendingCloudPublication
    case serverEnforced
}

public enum ReviewCapabilityEnforcement: String, Codable, Sendable {
    case appEnforcedWithinShare
}

public struct ReviewPolicyInclusion: Codable, Equatable, Sendable {
    public let recordID: UUID
    public let payload: ReviewPayload
    public let boundary: ReviewBoundaryEnforcement
}

public struct ReviewAccessPolicyResult: Codable, Equatable, Sendable {
    public let policyVersion: Int
    public let previewToken: String
    public let included: [ReviewPolicyInclusion]
    public let exclusions: [UUID: ReviewExclusionReason]
    public let capabilities: Set<ReviewCapability>
    public let capabilityEnforcement: ReviewCapabilityEnforcement

    public var includedCount: Int { included.count }
    public var excludedCount: Int { exclusions.count }

    public func exclusionCount(for reason: ReviewExclusionReason) -> Int {
        exclusions.values.count { $0 == reason }
    }
}

public struct ReviewPolicyTransition: Codable, Equatable, Sendable {
    public let publishRecordIDs: Set<UUID>
    public let withdrawRecordIDs: Set<UUID>

    public init(publishRecordIDs: Set<UUID>, withdrawRecordIDs: Set<UUID>) {
        self.publishRecordIDs = publishRecordIDs
        self.withdrawRecordIDs = withdrawRecordIDs
    }
}

public enum ReviewAccessPolicyError: Error, Equatable, LocalizedError, Sendable {
    case missingScopeRoot(UUID)
    case duplicateRecord(UUID)
    case missingParent(recordID: UUID, parentID: UUID)
    case crossProjectRecord(UUID)
    case invalidHierarchy(UUID)
    case stalePreview

    public var errorDescription: String? {
        switch self {
        case .missingScopeRoot(let id): "Review scope root \(id) does not exist."
        case .duplicateRecord(let id): "Review policy input contains duplicate record \(id)."
        case .missingParent(let recordID, let parentID): "Record \(recordID) references missing parent \(parentID)."
        case .crossProjectRecord(let id): "Record \(id) crosses the selected project boundary."
        case .invalidHierarchy(let id): "Record \(id) participates in an invalid or cyclic hierarchy."
        case .stalePreview: "The review preview is stale and must be regenerated before publication."
        }
    }
}

public enum ReviewAccessPolicyResolver {
    public static func transition(
        from published: ReviewAccessPolicyResult,
        to preview: ReviewAccessPolicyResult
    ) -> ReviewPolicyTransition {
        let publishedIDs = Set(published.included.map(\.recordID))
        let previewIDs = Set(preview.included.map(\.recordID))
        return ReviewPolicyTransition(
            publishRecordIDs: previewIDs.subtracting(publishedIDs),
            withdrawRecordIDs: publishedIDs.subtracting(previewIDs)
        )
    }

    public static func preview(
        policy: ReviewAccessPolicy,
        grant: OwnerAuthorizedReviewGrant,
        records: [ReviewPolicyRecord]
    ) throws -> ReviewAccessPolicyResult {
        try resolve(policy: policy, grant: grant, records: records, boundary: .pendingCloudPublication)
    }

    public static func authorizePublication(
        policy: ReviewAccessPolicy,
        grant: OwnerAuthorizedReviewGrant,
        records: [ReviewPolicyRecord],
        previewToken: String
    ) throws -> ReviewAccessPolicyResult {
        let current = try resolve(policy: policy, grant: grant, records: records, boundary: .serverEnforced)
        guard current.previewToken == previewToken else { throw ReviewAccessPolicyError.stalePreview }
        return current
    }

    private static func resolve(
        policy: ReviewAccessPolicy,
        grant: OwnerAuthorizedReviewGrant,
        records: [ReviewPolicyRecord],
        boundary: ReviewBoundaryEnforcement
    ) throws -> ReviewAccessPolicyResult {
        var byID: [UUID: ReviewPolicyRecord] = [:]
        for record in records {
            guard byID[record.id] == nil else { throw ReviewAccessPolicyError.duplicateRecord(record.id) }
            guard record.projectID == policy.projectID else { throw ReviewAccessPolicyError.crossProjectRecord(record.id) }
            byID[record.id] = record
        }
        guard byID[policy.scopeRootID] != nil else { throw ReviewAccessPolicyError.missingScopeRoot(policy.scopeRootID) }
        for record in records {
            if let parentID = record.parentID, byID[parentID] == nil {
                throw ReviewAccessPolicyError.missingParent(recordID: record.id, parentID: parentID)
            }
        }
        try validateAcyclic(records: records, byID: byID)

        let descendants = descendantsOf(policy.scopeRootID, records: records)
        var included: [ReviewPolicyInclusion] = []
        var exclusions: [UUID: ReviewExclusionReason] = [:]
        for record in records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if record.kind == .storyContext {
                if storyBibleAllows(record.id, grant: grant.storyBible) {
                    included.append(.init(recordID: record.id, payload: .storyContext, boundary: boundary))
                } else {
                    exclusions[record.id] = .storyBibleNotGranted
                }
                continue
            }
            if record.kind == .privateResource {
                exclusions[record.id] = .privateResource
                continue
            }
            if record.kind == .feedback {
                exclusions[record.id] = .separateFeedbackBoundary
                continue
            }
            guard descendants.contains(record.id) else {
                exclusions[record.id] = .outsideScope
                continue
            }
            if record.includeInCompile == false {
                exclusions[record.id] = .directDoNotPublish
                continue
            }
            if hasExcludedAncestor(record, byID: byID, scopeRootID: policy.scopeRootID) {
                exclusions[record.id] = .inheritedDoNotPublish
                continue
            }

            switch record.kind {
            case .manuscriptText:
                guard let status = record.statusIdentifier else {
                    exclusions[record.id] = .missingOrDeletedStatus
                    continue
                }
                guard policy.reviewableStatusIdentifiers.contains(status) else {
                    exclusions[record.id] = .statusNotReviewable
                    continue
                }
                included.append(.init(recordID: record.id, payload: .manuscriptText, boundary: boundary))
            case .structure:
                if policy.allowsNavigationMetadata {
                    included.append(.init(recordID: record.id, payload: .navigationMetadata, boundary: boundary))
                } else {
                    exclusions[record.id] = .navigationMetadataNotGranted
                }
            case .storyContext, .privateResource, .feedback:
                preconditionFailure("Independent policy domains are resolved before manuscript scope.")
            }
        }

        var capabilities = grant.role.capabilities
        switch grant.storyBible {
        case .none: break
        case .selected, .fullRead: capabilities.insert(.readStoryContext)
        case .edit:
            capabilities.insert(.readStoryContext)
            capabilities.insert(.editStoryContext)
        }
        let token = fingerprint(policy: policy, grant: grant, records: records)
        return ReviewAccessPolicyResult(
            policyVersion: policy.version,
            previewToken: token,
            included: included,
            exclusions: exclusions,
            capabilities: capabilities,
            capabilityEnforcement: .appEnforcedWithinShare
        )
    }

    private static func validateAcyclic(
        records: [ReviewPolicyRecord],
        byID: [UUID: ReviewPolicyRecord]
    ) throws {
        for record in records {
            var visited = Set<UUID>()
            var current: ReviewPolicyRecord? = record
            while let candidate = current, let parentID = candidate.parentID {
                guard visited.insert(candidate.id).inserted else {
                    throw ReviewAccessPolicyError.invalidHierarchy(candidate.id)
                }
                current = byID[parentID]
            }
        }
    }

    private static func descendantsOf(_ rootID: UUID, records: [ReviewPolicyRecord]) -> Set<UUID> {
        let children = Dictionary(grouping: records.compactMap { record in
            record.parentID.map { ($0, record.id) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        var result = Set<UUID>()
        var pending = [rootID]
        while let id = pending.popLast(), result.insert(id).inserted {
            pending.append(contentsOf: children[id, default: []])
        }
        return result
    }

    private static func hasExcludedAncestor(
        _ record: ReviewPolicyRecord,
        byID: [UUID: ReviewPolicyRecord],
        scopeRootID: UUID
    ) -> Bool {
        var parentID = record.parentID
        while let id = parentID, let parent = byID[id] {
            if parent.includeInCompile == false { return true }
            if id == scopeRootID { return false }
            parentID = parent.parentID
        }
        return false
    }

    private static func storyBibleAllows(_ id: UUID, grant: StoryBibleGrant) -> Bool {
        switch grant {
        case .none: false
        case .selected(let ids): ids.contains(id)
        case .fullRead, .edit: true
        }
    }

    private static func fingerprint(
        policy: ReviewAccessPolicy,
        grant: OwnerAuthorizedReviewGrant,
        records: [ReviewPolicyRecord]
    ) -> String {
        let statuses = policy.reviewableStatusIdentifiers.sorted().joined(separator: ",")
        let storyGrant: String
        switch grant.storyBible {
        case .none: storyGrant = "none"
        case .selected(let ids): storyGrant = "selected:" + ids.map(\.uuidString).sorted().joined(separator: ",")
        case .fullRead: storyGrant = "fullRead"
        case .edit: storyGrant = "edit"
        }
        let recordValues = records.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [$0.id.uuidString, $0.projectID.uuidString, $0.parentID?.uuidString ?? "-", $0.kind.rawValue,
             $0.statusIdentifier ?? "-", $0.includeInCompile.map(String.init) ?? "-"].joined(separator: "|")
        }.joined(separator: ";")
        let value = [String(policy.version), policy.projectID.uuidString, policy.scopeRootID.uuidString,
                     statuses, String(policy.allowsNavigationMetadata), grant.role.rawValue, storyGrant,
                     recordValues].joined(separator: "#")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
