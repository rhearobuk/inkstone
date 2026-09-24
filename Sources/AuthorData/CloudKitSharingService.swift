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
    case participantNotFound(String)

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
        case .participantNotFound(let identity):
            "CloudKit no longer has a participant matching \(identity). Refresh sharing status and try again."
        }
    }
}

@MainActor
public final class CloudKitSharingService {
    public static let scopedProjectionSourceFormat = "inkstone-scoped-share"
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
        // `share(objects:to:)` has already created the private share. Return that exact
        // server-versioned object so the caller can add participants without modifying a
        // stale pre-save copy and triggering a CloudKit change-tag conflict.
        return result
    }

    /// Prepares the canonical manuscript records for sharing. The lightweight project record
    /// is navigation metadata only; manuscript text is never copied.
    public func prepareScopedManuscript(
        for group: SharingGroup,
        project: WritingProject,
        documents sourceDocuments: [Document]
    ) throws {
        guard group.domain == SharingGroupDomain.manuscript.rawValue else { return }

        let projectionIdentifier = scopedProjectIdentifier(for: group)
        let existingProjection = try dataStore.projects.fetchAll(
            predicate: NSPredicate(format: "sourceIdentifier == %@", projectionIdentifier)
        ).first
        let scopedProject: WritingProject
        if let existingProjection {
            scopedProject = existingProjection
        } else {
            // A scoped share is a distinct project on the recipient's device. Reusing the
            // owner's project UUID makes Core Data/UI joins merge separate shares back into
            // the canonical novel, which exposes sibling books and chapters.
            scopedProject = dataStore.projects.create(id: group.id) { projection in
                self.copyAttributes(from: project, to: projection)
                projection.title = sourceDocuments.first(where: { $0.id == group.scopeRootID })?.title ?? project.title
                projection.sourceIdentifier = projectionIdentifier
                projection.sourceFormat = Self.scopedProjectionSourceFormat
            }
            scopedProject.modifiedAt = Date()
        }

        let requestedIDs = Set(sourceDocuments.map(\.id))
        for document in group.documents where !requestedIDs.contains(document.id) {
            document.sharingGroup = nil
            document.sharingGroupID = nil
        }
        try CanonicalSharingGraphPreparer().prepareManuscript(sourceDocuments, for: group)
        let preparedIDs = Set(group.documents.lazy.filter { !$0.isDeleted }.map(\.id))
        guard preparedIDs == requestedIDs else {
            throw CloudSharingError.unsafeObjectGraph(details: "canonical document membership did not match the selected preview")
        }
        group.state = "ready"
        group.modifiedAt = Date()
        try dataStore.save()

        let scopedObjects: [NSManagedObject] = [group, scopedProject] + Array(group.documents)
        let allowed = Set(scopedObjects.map(\.objectID))
        detachRelationshipsOutsideScope(from: scopedObjects, allowedObjectIDs: allowed)
        try dataStore.save()
        let report = CoreDataSharingPreflight.audit(root: group, allowedObjectIDs: allowed)
        guard report.isObjectGraphSafe else {
            let details = report.exposures.map(\.relationshipPath).joined(separator: ", ")
            throw CloudSharingError.unsafeObjectGraph(details: details)
        }
    }

    public func publishInvitation(
        for groups: [SharingGroup],
        recipientEmail: String,
        permission: CKShare.ParticipantPermission
    ) async throws -> CKShare {
        try requireCloudKit()
        guard let firstGroup = groups.first else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        guard permission == .readOnly || permission == .readWrite else {
            throw CloudSharingError.publicSharingDisabled
        }
        guard let projectID = firstGroup.projectID,
              let project = try canonicalProject(id: projectID) else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        try dataStore.save()
        let manuscriptGroup = try manuscriptGroup(for: firstGroup)
        guard groups.allSatisfy({
            $0.projectID == manuscriptGroup.projectID && $0.scopeRootID == manuscriptGroup.scopeRootID
        }) else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        let projection = try scopedProject(for: manuscriptGroup)
        let objectIDs = Array(Set(groups.map(\.objectID) + [manuscriptGroup.objectID]))
        let matches = try dataStore.container.fetchShares(matching: objectIDs)
        let existing = matches[manuscriptGroup.objectID] ?? groups.compactMap { matches[$0.objectID] }.first
        var share: CKShare
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
            let missingGroups = groups.filter { matches[$0.objectID] == nil }
            if !missingGroups.isEmpty {
                share = try await addObjects(missingGroups, to: share)
            }
        } else {
            guard groups.contains(where: { $0.id == manuscriptGroup.id }) else {
                throw CloudSharingError.recordOutsidePrivateStore
            }
            (share, cloudContainer) = try await createPrivateShare(for: groups + [projection])
        }

        let normalizedEmail = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let participant: CKShare.Participant
        if let existingParticipant = share.participants.first(where: {
            $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == normalizedEmail
        }) {
            participant = existingParticipant
        } else {
            participant = try await cloudContainer.shareParticipant(forEmailAddress: normalizedEmail)
        }
        participant.permission = permission
        share.publicPermission = .none
        if !share.participants.contains(where: { $0 === participant }) {
            share.addParticipant(participant)
        }
        let scopeTitle = try scopeTitle(for: manuscriptGroup) ?? project.title
        share[CKShare.SystemFieldKey.title] = scopeTitle as CKRecordValue
        let updatedShare = try await persist(share, in: dataStore.privatePersistentStore)

        let identity = normalizedEmail
        for group in groups {
            group.cloudKitShareID = share.recordID.recordName
            group.state = "awaitingAcceptance"
            group.modifiedAt = Date()
            let existingParticipant = try dataStore.shareParticipants.fetchAll(
                predicate: NSPredicate(
                    format: "sharingGroupID == %@ AND cloudKitIdentity == %@",
                    group.id as CVarArg,
                    identity
                )
            ).first
            let participantRecord = existingParticipant ?? dataStore.shareParticipants.create { record in
                record.sharingGroupID = group.id
                record.cloudKitIdentity = identity
                record.createdAt = Date()
            }
            participantRecord.inkstoneRole = "participant"
            participantRecord.cloudKitPermission = permission == .readOnly ? "readOnly" : "readWrite"
            participantRecord.invitationState = Self.invitationState(for: participant.acceptanceStatus)
            participantRecord.modifiedAt = Date()
        }
        try dataStore.save()
        return updatedShare
    }

    /// Fetches each scoped share for a project and reconciles its invitation state.
    @discardableResult
    public func refreshInvitationStatuses(for project: WritingProject) async throws -> CKShare? {
        try requireCloudKit()
        let groups = try dataStore.sharingGroups.fetchAll(
            predicate: NSPredicate(format: "projectID == %@", project.id as CVarArg)
        )
        let manuscriptGroups = groups.filter { $0.domain == SharingGroupDomain.manuscript.rawValue }
        let matches = try dataStore.container.fetchShares(matching: manuscriptGroups.map(\.objectID))
        let cloudContainer = CKContainer(identifier: Self.containerIdentifier)
        var firstShare: CKShare?
        for manuscriptGroup in manuscriptGroups {
            guard let localShare = matches[manuscriptGroup.objectID] else { continue }
            let serverRecord = try await cloudContainer.privateCloudDatabase.record(for: localShare.recordID)
            let serverShare = (serverRecord as? CKShare) ?? localShare
            firstShare = firstShare ?? serverShare
            let scopeGroupIDs = Set(groups.filter {
                $0.scopeRootID == manuscriptGroup.scopeRootID
            }.map(\.id))
            let localParticipants = try dataStore.shareParticipants.fetchAll().filter {
                $0.sharingGroupID.map(scopeGroupIDs.contains) == true && $0.invitationState != "revoked"
            }
            for participant in serverShare.participants where participant.role != .owner {
                let identities = Self.identities(for: participant)
                for record in localParticipants where identities.contains(record.cloudKitIdentity?.lowercased() ?? "") {
                    record.invitationState = Self.invitationState(for: participant.acceptanceStatus)
                    record.cloudKitPermission = participant.permission == .readOnly ? "readOnly" : "readWrite"
                    record.modifiedAt = Date()
                }
            }
        }
        try dataStore.save()
        return firstShare
    }

    public func invitationURL(for project: WritingProject) async throws -> URL? {
        try await refreshInvitationStatuses(for: project)?.url
    }

    public func invitationURL(for group: SharingGroup) throws -> URL? {
        try projectShare(for: group).url
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
        if let participant = try cloudParticipant(identity: identity, in: share, for: group) {
            try await revoke(participant, from: share)
        }
        for record in try participantRecords(identity: identity, inProjectOf: group) {
            record.invitationState = "revoked"
            record.modifiedAt = Date()
        }
        let scopeGroups = try dataStore.sharingGroups.fetchAll().filter {
            $0.projectID == group.projectID && $0.scopeRootID == group.scopeRootID
        }
        let scopeGroupIDs = Set(scopeGroups.map(\.id))
        let hasActiveParticipants = try dataStore.shareParticipants.fetchAll().contains {
            $0.sharingGroupID.map(scopeGroupIDs.contains) == true && $0.invitationState != "revoked"
        }
        if !hasActiveParticipants {
            for scopeGroup in scopeGroups {
                scopeGroup.state = "revoked"
                scopeGroup.modifiedAt = Date()
            }
        }
        try dataStore.save()
    }

    public func updatePermission(
        for identity: String,
        in group: SharingGroup,
        to permission: CKShare.ParticipantPermission
    ) async throws {
        let share = try projectShare(for: group)
        guard let participant = try cloudParticipant(identity: identity, in: share, for: group) else {
            throw CloudSharingError.participantNotFound(identity)
        }
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

    private func addObjects(_ objects: [NSManagedObject], to share: CKShare) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            dataStore.container.share(objects, to: share) { _, updatedShare, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let updatedShare { continuation.resume(returning: updatedShare) }
                else { continuation.resume(throwing: CloudSharingError.recordOutsidePrivateStore) }
            }
        }
    }

    private func copyAttributes(from source: NSManagedObject, to destination: NSManagedObject) {
        for key in source.entity.attributesByName.keys where key != "id" {
            destination.setValue(source.value(forKey: key), forKey: key)
        }
    }

    /// Projection objects are disposable sharing records. Their persisted relationships must
    /// never escape the projection, even if a previous failed attempt or Core Data inverse
    /// maintenance temporarily connected them to an owner-private record.
    private func detachRelationshipsOutsideScope(
        from objects: [NSManagedObject],
        allowedObjectIDs: Set<NSManagedObjectID>
    ) {
        for object in objects {
            for relationship in object.entity.relationshipsByName.values {
                guard let value = object.primitiveValue(forKey: relationship.name) else { continue }
                if relationship.isToMany {
                    let related: [NSManagedObject]
                    if let set = value as? Set<NSManagedObject> {
                        related = Array(set)
                    } else if let set = value as? NSSet {
                        related = set.compactMap { $0 as? NSManagedObject }
                    } else {
                        related = []
                    }
                    let scoped = related.filter { allowedObjectIDs.contains($0.objectID) }
                    if scoped.count != related.count {
                        object.setPrimitiveValue(NSSet(array: scoped), forKey: relationship.name)
                    }
                } else if let related = value as? NSManagedObject,
                          !allowedObjectIDs.contains(related.objectID) {
                    object.setPrimitiveValue(nil, forKey: relationship.name)
                }
            }
        }
    }

    private func canonicalProject(id: UUID) throws -> WritingProject? {
        try dataStore.projects.fetchAll(predicate: NSPredicate(format: "id == %@", id as CVarArg))
            .first { $0.sourceFormat != Self.scopedProjectionSourceFormat }
    }

    private func manuscriptGroup(for group: SharingGroup) throws -> SharingGroup {
        if group.domain == SharingGroupDomain.manuscript.rawValue { return group }
        guard let projectID = group.projectID, let scopeRootID = group.scopeRootID,
              let manuscript = try dataStore.sharingGroups.fetchAll(predicate: NSPredicate(
                format: "projectID == %@ AND scopeRootID == %@ AND domain == %@",
                projectID as CVarArg,
                scopeRootID as CVarArg,
                SharingGroupDomain.manuscript.rawValue
              )).first else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        return manuscript
    }

    private func scopedProjectIdentifier(for group: SharingGroup) -> String {
        "scoped-share.\(group.id.uuidString)"
    }

    private func scopedProject(for group: SharingGroup) throws -> WritingProject {
        guard let project = try dataStore.projects.fetchAll(predicate: NSPredicate(
            format: "sourceIdentifier == %@",
            scopedProjectIdentifier(for: group)
        )).first else {
            throw CloudSharingError.recordOutsidePrivateStore
        }
        return project
    }

    private func scopeTitle(for group: SharingGroup) throws -> String? {
        guard let scopeRootID = group.scopeRootID else { return nil }
        return try dataStore.documents.fetchAll(predicate: NSPredicate(
            format: "id == %@ AND sharingGroupID == nil",
            scopeRootID as CVarArg
        )).first?.title
    }

    private func requireCloudKit() throws {
        guard dataStore.cloudKitSyncEnabled else { throw CloudSharingError.localOnlyBuild }
    }

    private static var containerIdentifier: String { AuthorDataStore.cloudKitContainerIdentifier }

    private func projectShare(for group: SharingGroup) throws -> CKShare {
        let manuscript = try manuscriptGroup(for: group)
        let shares = try dataStore.container.fetchShares(matching: [manuscript.objectID, group.objectID])
        guard let share = shares[manuscript.objectID] ?? shares[group.objectID] else {
            throw CloudSharingError.ownerAuthorityRequired
        }
        return share
    }

    private func participantRecords(identity: String, inProjectOf group: SharingGroup) throws -> [ShareParticipant] {
        guard let projectID = group.projectID, let scopeRootID = group.scopeRootID else { return [] }
        let scopeGroupIDs = Set(try dataStore.sharingGroups.fetchAll(predicate: NSPredicate(
            format: "projectID == %@ AND scopeRootID == %@",
            projectID as CVarArg,
            scopeRootID as CVarArg
        )).map(\.id))
        return try dataStore.shareParticipants.fetchAll(
            predicate: NSPredicate(format: "cloudKitIdentity == %@", identity)
        ).filter { participant in
            participant.sharingGroupID.map(scopeGroupIDs.contains) == true
        }
    }

    private func cloudParticipant(
        identity: String,
        in share: CKShare,
        for group: SharingGroup
    ) throws -> CKShare.Participant? {
        let normalizedIdentity = identity.lowercased()
        let cloudParticipants = share.participants.filter { $0.role != .owner }
        if let exact = cloudParticipants.first(where: {
            $0.userIdentity.userRecordID?.recordName.lowercased() == normalizedIdentity
                || $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == normalizedIdentity
        }) {
            return exact
        }

        // CloudKit can replace an invited email with an opaque record identity after
        // acceptance. A single local participant and a single CloudKit participant in
        // this scoped share are therefore the same person even when the email disappears.
        let localIdentities = Set(try participantRecords(identity: identity, inProjectOf: group)
            .compactMap { $0.cloudKitIdentity?.lowercased() })
        if localIdentities == [normalizedIdentity], cloudParticipants.count == 1 {
            return cloudParticipants[0]
        }
        return nil
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

    public static func invitationState(for status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .accepted: "accepted"
        case .removed: "removed"
        case .pending: "pending"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    private static func identities(for participant: CKShare.Participant) -> Set<String> {
        var result = Set<String>()
        if let email = participant.userIdentity.lookupInfo?.emailAddress?.lowercased() {
            result.insert(email)
        }
        if let recordName = participant.userIdentity.userRecordID?.recordName.lowercased() {
            result.insert(recordName)
        }
        return result
    }

    private func requireOwner(of share: CKShare) throws {
        try requireCloudKit()
        // A share loaded from the owner's private persistent store can temporarily omit
        // currentUserParticipant while CloudKit is reconciling its server metadata. A
        // concrete non-owner role is authoritative; nil is not evidence that this user
        // lacks ownership. The server still validates the mutation when it is persisted.
        if let currentParticipant = share.currentUserParticipant,
           currentParticipant.role != .owner {
            throw CloudSharingError.ownerAuthorityRequired
        }
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
