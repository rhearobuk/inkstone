import Foundation

/// The persistent ownership boundary for canonical authoring data.
///
/// A value belongs to one scope only. Moving data between scopes is an explicit
/// migration; it is never implemented by maintaining synchronized copies.
public enum AuthorStoreScope: String, Codable, CaseIterable, Sendable {
    case ownerPrivate
    case participantShared

    public var configurationName: String {
        switch self {
        case .ownerPrivate:
            return "Private"
        case .participantShared:
            return "Shared"
        }
    }
}

/// A CloudKit permission boundary. Domains with different permissions use
/// different groups even when they refer to the same logical document.
public enum SharingGroupDomain: String, Codable, CaseIterable, Sendable {
    case manuscript
    case feedback
    case storyContext
}

/// Identifies one disconnected collaboration graph.
public struct SharingGroupDescriptor: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let scopeRootID: UUID
    public let domain: SharingGroupDomain

    public init(
        id: UUID,
        projectID: UUID,
        scopeRootID: UUID,
        domain: SharingGroupDomain
    ) {
        self.id = id
        self.projectID = projectID
        self.scopeRootID = scopeRootID
        self.domain = domain
    }
}

/// The single authoritative location of a canonical record.
///
/// Cross-boundary references use the record's stable UUID. They must not be
/// represented as Core Data relationships or resolved by copying the record.
public struct CanonicalRecordRoute: Codable, Equatable, Hashable, Sendable {
    public let recordID: UUID
    public let projectID: UUID
    public let storeScope: AuthorStoreScope
    public let sharingGroupID: UUID?

    public init(
        recordID: UUID,
        projectID: UUID,
        storeScope: AuthorStoreScope,
        sharingGroupID: UUID? = nil
    ) throws {
        switch (storeScope, sharingGroupID) {
        case (.ownerPrivate, _), (.participantShared, .some):
            break
        case (.participantShared, nil):
            throw SharingTopologyError.participantRecordHasNoGroup(recordID)
        }

        self.recordID = recordID
        self.projectID = projectID
        self.storeScope = storeScope
        self.sharingGroupID = sharingGroupID
    }
}

public enum SharingTopologyError: Error, Equatable, LocalizedError, Sendable {
    case participantRecordHasNoGroup(UUID)
    case duplicateCanonicalRecord(UUID)
    case unknownSharingGroup(UUID)
    case crossProjectGroup(recordID: UUID, recordProjectID: UUID, groupProjectID: UUID)

    public var errorDescription: String? {
        switch self {
        case .participantRecordHasNoGroup(let id):
            return "Record \(id) in the participant shared store must identify its sharing group."
        case .duplicateCanonicalRecord(let id):
            return "Canonical record \(id) has more than one authoritative route."
        case .unknownSharingGroup(let id):
            return "Sharing group \(id) is not defined."
        case .crossProjectGroup(let recordID, let recordProjectID, let groupProjectID):
            return "Record \(recordID) belongs to project \(recordProjectID), not group project \(groupProjectID)."
        }
    }
}

/// Validates a complete routing manifest before records are inserted or moved.
///
/// This manifest is owner-authoritative. It describes storage ownership, not a
/// participant-editable role or a UI visibility filter.
public struct SharingTopologyValidator: Sendable {
    public init() {}

    public func validate(
        groups: [SharingGroupDescriptor],
        routes: [CanonicalRecordRoute]
    ) throws {
        let groupsByID = groups.reduce(into: [UUID: SharingGroupDescriptor]()) { result, group in
            result[group.id] = group
        }
        var recordIDs = Set<UUID>()

        for route in routes {
            guard recordIDs.insert(route.recordID).inserted else {
                throw SharingTopologyError.duplicateCanonicalRecord(route.recordID)
            }
            guard let groupID = route.sharingGroupID else { continue }
            guard let group = groupsByID[groupID] else {
                throw SharingTopologyError.unknownSharingGroup(groupID)
            }
            guard group.projectID == route.projectID else {
                throw SharingTopologyError.crossProjectGroup(
                    recordID: route.recordID,
                    recordProjectID: route.projectID,
                    groupProjectID: group.projectID
                )
            }
        }
    }
}
