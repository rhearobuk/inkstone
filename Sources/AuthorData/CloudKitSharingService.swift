import CloudKit
import CoreData
import Foundation

public enum CloudSharingState: Equatable, Sendable {
    case localOnly
    case ready
    case publishing
    case awaitingAcceptance
    case active
    case withdrawing
    case revoked
    case failed(message: String, recoverable: Bool)
}

public enum CloudSharingError: Error, Equatable, LocalizedError, Sendable {
    case localOnlyBuild
    case recordOutsidePrivateStore
    case publicSharingDisabled
    case ownerAuthorityRequired
    case participantCannotRevokeOwnerData
    case invitationAlreadyProcessed
    case unsafeObjectGraph(details: String)
    case staleShareZone

    public var errorDescription: String? {
        switch self {
        case .localOnlyBuild: "This build is local-only; no CloudKit sharing operation was performed."
        case .recordOutsidePrivateStore: "Only canonical records in the owner's private store can begin a share."
        case .publicSharingDisabled: "Public sharing is disabled."
        case .ownerAuthorityRequired: "Only the CloudKit share owner can change participant permissions."
        case .participantCannotRevokeOwnerData: "Participant cleanup cannot delete the owner's canonical records."
        case .invitationAlreadyProcessed: "This invitation has already been processed."
        case .unsafeObjectGraph(let details): "Sharing stopped because the selected group reaches private records through: \(details)."
        case .staleShareZone: "This local share refers to a CloudKit zone that no longer exists. Reset the local development library, then try again."
        }
    }
}

public struct SharingGroupOperationResult: Equatable, Sendable {
    public let groupID: UUID
    public let succeeded: Bool
    public let message: String?

    public init(groupID: UUID, succeeded: Bool, message: String? = nil) {
        self.groupID = groupID
        self.succeeded = succeeded
        self.message = message
    }
}

public struct SharingWorkflowResult: Equatable, Sendable {
    public let groups: [SharingGroupOperationResult]
    public var isPartial: Bool { groups.contains(where: \.succeeded) && groups.contains { !$0.succeeded } }
    public var canRetry: Bool { groups.contains { !$0.succeeded } }

    public init(groups: [SharingGroupOperationResult]) { self.groups = groups }
}

@MainActor
public final class CloudKitSharingService {
    public let dataStore: AuthorDataStore
    private var processedInvitationIDs = Set<CKRecord.ID>()

    public init(dataStore: AuthorDataStore) {
        self.dataStore = dataStore
    }

    public var state: CloudSharingState {
        dataStore.cloudKitSyncEnabled ? .ready : .localOnly
    }

    public func createPrivateShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
        try requireCloudKit()
        guard !objects.isEmpty, objects.allSatisfy({ $0.objectID.persistentStore == dataStore.privatePersistentStore }) else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        let result: (CKShare, CKContainer) = try await withCheckedThrowingContinuation { continuation in
            dataStore.container.share(objects, to: nil) { _, share, container, error in
                if let error { continuation.resume(throwing: error) }
                else if let share, let container { continuation.resume(returning: (share, container)) }
                else { continuation.resume(throwing: CloudSharingError.recordOutsidePrivateStore) }
            }
        }
        result.0.publicPermission = .none
        _ = try await persist(result.0, in: dataStore.privatePersistentStore)
        return result
    }

    public func publishInvitation(
        for group: SharingGroup,
        recipientEmail: String,
        permission: CKShare.ParticipantPermission
    ) async throws -> CKShare {
        try requireCloudKit()
        guard permission == .readOnly || permission == .readWrite else {
            throw CloudSharingError.publicSharingDisabled
        }
        guard let projectID = group.projectID,
              let project = try dataStore.projects.fetch(id: projectID) else {
            throw CloudSharingError.recordOutsidePrivateStore
        }

        // A Core Data object graph can belong to only one CKShare zone. The project is the
        // sole CloudKit sharing root; manuscript/feedback/context groups are local access rules.
        try dataStore.save()
        let existing = try dataStore.container.fetchShares(matching: [project.objectID])[project.objectID]
        let share: CKShare
        let cloudContainer: CKContainer
        if let existing {
            cloudContainer = CKContainer(identifier: Self.containerIdentifier)
            do {
                _ = try await cloudContainer.privateCloudDatabase.recordZone(for: existing.recordID.zoneID)
            } catch {
                if Self.isZoneNotFound(error) {
                    throw CloudSharingError.staleShareZone
                }
                throw error
            }
            share = existing
        } else {
            (share, cloudContainer) = try await createPrivateShare(for: [project])
        }

        let participant = try await cloudContainer.shareParticipant(forEmailAddress: recipientEmail)
        participant.permission = permission
        share.publicPermission = .none
        share.addParticipant(participant)
        _ = try await persist(share, in: dataStore.privatePersistentStore)

        group.cloudKitShareID = share.recordID.recordName
        group.state = "awaitingAcceptance"
        group.modifiedAt = Date()
        let identity = recipientEmail.lowercased()
        let existingParticipant = try dataStore.shareParticipants.fetchAll(
            predicate: NSPredicate(format: "sharingGroupID == %@ AND cloudKitIdentity == %@", group.id as CVarArg, identity)
        ).first
        let participantRecord = existingParticipant ?? dataStore.shareParticipants.create { record in
            record.sharingGroupID = group.id
            record.cloudKitIdentity = identity
            record.createdAt = Date()
        }
        participantRecord.inkstoneRole = "participant"
        participantRecord.cloudKitPermission = permission == .readOnly ? "readOnly" : "readWrite"
        participantRecord.invitationState = "pending"
        participantRecord.modifiedAt = Date()
        try dataStore.save()
        return share
    }

    public func participants(for group: SharingGroup) throws -> [ShareParticipant] {
        try dataStore.shareParticipants.fetchAll(
            predicate: NSPredicate(format: "sharingGroupID == %@", group.id as CVarArg)
        )
    }

    @discardableResult
    public func createFeedback(
        body: String,
        documentID: UUID,
        in group: SharingGroup,
        author: String? = nil
    ) throws -> Annotation {
        guard group.domain == SharingGroupDomain.feedback.rawValue else {
            throw SharingAuthorizationError.unauthorizedCommand(.createFeedback)
        }
        let repository = try dataStore.repository(for: Annotation.self, scope: .participantShared)
        let annotation = repository.create { annotation in
            annotation.documentID = documentID
            annotation.sharingGroupID = group.id
            annotation.feedbackGroup = group
            annotation.kind = "comment"
            annotation.body = body
            annotation.author = author
            annotation.source = "participant"
            annotation.status = "open"
            annotation.createdAt = Date()
            annotation.modifiedAt = Date()
        }
        try dataStore.save()
        return annotation
    }

    public func revokeParticipant(identity: String, from group: SharingGroup) async throws {
        let share = try projectShare(for: group)
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == identity
                || $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == identity.lowercased()
        }) else { return }
        try await revoke(participant, from: share)
        for record in try participantRecords(identity: identity, inProjectOf: group) {
            record.invitationState = "revoked"
            record.modifiedAt = Date()
        }
        try dataStore.save()
    }

    public func updatePermission(
        for identity: String,
        in group: SharingGroup,
        to permission: CKShare.ParticipantPermission
    ) async throws {
        let share = try projectShare(for: group)
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == identity
                || $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == identity.lowercased()
        }) else { return }
        try await setPermission(permission, for: participant, in: share)
        for record in try participantRecords(identity: identity, inProjectOf: group) {
            record.cloudKitPermission = permission == .readOnly ? "readOnly" : "readWrite"
            record.modifiedAt = Date()
        }
        try dataStore.save()
    }

    public func accept(_ metadata: CKShare.Metadata) async throws {
        try requireCloudKit()
        guard processedInvitationIDs.insert(metadata.share.recordID).inserted else {
            throw CloudSharingError.invitationAlreadyProcessed
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                dataStore.container.acceptShareInvitations(from: [metadata], into: dataStore.sharedPersistentStore) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        } catch {
            processedInvitationIDs.remove(metadata.share.recordID)
            throw error
        }
    }

    public func setPermission(_ permission: CKShare.ParticipantPermission,
                              for participant: CKShare.Participant,
                              in share: CKShare) async throws {
        try requireOwner(of: share)
        guard permission == .readOnly || permission == .readWrite else {
            throw CloudSharingError.publicSharingDisabled
        }
        participant.permission = permission
        share.publicPermission = .none
        _ = try await persist(share, in: dataStore.privatePersistentStore)
    }

    public func revoke(_ participant: CKShare.Participant, from share: CKShare) async throws {
        try requireOwner(of: share)
        share.removeParticipant(participant)
        share.publicPermission = .none
        _ = try await persist(share, in: dataStore.privatePersistentStore)
    }

    public func revokeAllParticipants(from share: CKShare) async throws {
        try requireOwner(of: share)
        for participant in share.participants where participant.role != .owner {
            share.removeParticipant(participant)
        }
        share.publicPermission = .none
        _ = try await persist(share, in: dataStore.privatePersistentStore)
    }

    /// Participant departure removes only the local/shared-zone graph. It is never used by an owner.
    public func leaveShare(_ share: CKShare) async throws {
        try requireCloudKit()
        guard share.currentUserParticipant?.role != .owner else {
            throw CloudSharingError.participantCannotRevokeOwnerData
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataStore.container.purgeObjectsAndRecordsInZone(
                with: share.recordID.zoneID,
                in: dataStore.sharedPersistentStore
            ) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    public func shares(in scope: AuthorStoreScope) throws -> [CKShare] {
        let store = scope == .ownerPrivate ? dataStore.privatePersistentStore : dataStore.sharedPersistentStore
        return try dataStore.container.fetchShares(in: store)
    }

    private func persist(_ share: CKShare, in store: NSPersistentStore) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            dataStore.container.persistUpdatedShare(share, in: store) { updated, error in
                if let error { continuation.resume(throwing: error) }
                else if let updated { continuation.resume(returning: updated) }
                else { continuation.resume(throwing: CloudSharingError.ownerAuthorityRequired) }
            }
        }
    }

    private func requireCloudKit() throws {
        guard dataStore.cloudKitSyncEnabled else { throw CloudSharingError.localOnlyBuild }
    }

    private static var containerIdentifier: String { AuthorDataStore.cloudKitContainerIdentifier }

    private func projectShare(for group: SharingGroup) throws -> CKShare {
        guard let projectID = group.projectID,
              let project = try dataStore.projects.fetch(id: projectID) else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        let shares = try dataStore.container.fetchShares(matching: [project.objectID, group.objectID])
        guard let share = shares[project.objectID] ?? shares[group.objectID] else {
            throw CloudSharingError.ownerAuthorityRequired
        }
        return share
    }

    private func participantRecords(identity: String, inProjectOf group: SharingGroup) throws -> [ShareParticipant] {
        guard let projectID = group.projectID else { return [] }
        let projectGroupIDs = Set(try dataStore.sharingGroups.fetchAll(
            predicate: NSPredicate(format: "projectID == %@", projectID as CVarArg)
        ).map(\.id))
        return try dataStore.shareParticipants.fetchAll(
            predicate: NSPredicate(format: "cloudKitIdentity == %@", identity)
        ).filter { participant in
            participant.sharingGroupID.map(projectGroupIDs.contains) == true
        }
    }

    private static func isZoneNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == CKErrorDomain, nsError.code == CKError.zoneNotFound.rawValue {
            return true
        }
        if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
           partialErrors.values.contains(where: isZoneNotFound) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isZoneNotFound(underlying)
        }
        return false
    }

    private func requireOwner(of share: CKShare) throws {
        try requireCloudKit()
        guard share.currentUserParticipant?.role == .owner else { throw CloudSharingError.ownerAuthorityRequired }
        guard share.publicPermission == .none else { throw CloudSharingError.publicSharingDisabled }
    }
}

@MainActor
public final class CloudKitInvitationInbox {
    private var pending: [CKRecord.ID: CKShare.Metadata] = [:]

    public init() {}

    public func enqueue(_ metadata: CKShare.Metadata) { pending[metadata.share.recordID] = metadata }

    public func drain(using service: CloudKitSharingService) async -> [CKRecord.ID: Result<Void, Error>] {
        var results: [CKRecord.ID: Result<Void, Error>] = [:]
        for (id, metadata) in pending {
            do {
                try await service.accept(metadata)
                pending.removeValue(forKey: id)
                results[id] = .success(())
            } catch {
                results[id] = .failure(error)
            }
        }
        return results
    }
}
