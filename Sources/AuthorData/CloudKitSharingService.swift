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
    case unsafeObjectGraph

    public var errorDescription: String? {
        switch self {
        case .localOnlyBuild: "This build is local-only; no CloudKit sharing operation was performed."
        case .recordOutsidePrivateStore: "Only canonical records in the owner's private store can begin a share."
        case .publicSharingDisabled: "Public sharing is disabled."
        case .ownerAuthorityRequired: "Only the CloudKit share owner can change participant permissions."
        case .participantCannotRevokeOwnerData: "Participant cleanup cannot delete the owner's canonical records."
        case .invitationAlreadyProcessed: "This invitation has already been processed."
        case .unsafeObjectGraph: "Sharing stopped because the selected group still reaches private records."
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
        try dataStore.save()

        let allowedObjectIDs = Set([group.objectID])
            .union(group.documents.map(\.objectID))
            .union(group.feedback.map(\.objectID))
            .union(group.storyEntities.map(\.objectID))
        let report = CoreDataSharingPreflight.audit(root: group, allowedObjectIDs: allowedObjectIDs)
        let storyEntityNames = Set([
            SemanticEntity.entityName, EntityAlias.entityName, CharacterProfile.entityName,
            CharacterMeasurement.entityName, CharacterNote.entityName, CharacterRelationship.entityName,
            CharacterConflict.entityName, StoryBibleCard.entityName, StoryBibleNote.entityName,
            StoryBibleRelationship.entityName
        ])
        let safeStoryExpansion = group.domain == SharingGroupDomain.storyContext.rawValue
            && report.exposures.allSatisfy { storyEntityNames.contains($0.entityName) }
        guard report.isObjectGraphSafe || safeStoryExpansion else {
            throw CloudSharingError.unsafeObjectGraph
        }

        let existing = try dataStore.container.fetchShares(matching: [group.objectID])[group.objectID]
        let share: CKShare
        let cloudContainer: CKContainer
        if let existing {
            share = existing
            cloudContainer = CKContainer(identifier: Self.containerIdentifier)
        } else {
            (share, cloudContainer) = try await createPrivateShare(for: [group])
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
        guard let share = try dataStore.container.fetchShares(matching: [group.objectID])[group.objectID] else {
            throw CloudSharingError.ownerAuthorityRequired
        }
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == identity
                || $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == identity.lowercased()
        }) else { return }
        try await revoke(participant, from: share)
        for record in try participants(for: group) where record.cloudKitIdentity == identity {
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
        guard let share = try dataStore.container.fetchShares(matching: [group.objectID])[group.objectID] else {
            throw CloudSharingError.ownerAuthorityRequired
        }
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == identity
                || $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == identity.lowercased()
        }) else { return }
        try await setPermission(permission, for: participant, in: share)
        for record in try participants(for: group) where record.cloudKitIdentity == identity {
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
