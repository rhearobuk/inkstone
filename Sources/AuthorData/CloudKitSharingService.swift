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

    public var errorDescription: String? {
        switch self {
        case .localOnlyBuild: "This build is local-only; no CloudKit sharing operation was performed."
        case .recordOutsidePrivateStore: "Only canonical records in the owner's private store can begin a share."
        case .publicSharingDisabled: "Public sharing is disabled."
        case .ownerAuthorityRequired: "Only the CloudKit share owner can change participant permissions."
        case .participantCannotRevokeOwnerData: "Participant cleanup cannot delete the owner's canonical records."
        case .invitationAlreadyProcessed: "This invitation has already been processed."
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
