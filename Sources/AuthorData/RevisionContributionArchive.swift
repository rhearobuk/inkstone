import Foundation

public enum RevisionValue: Codable, Equatable, Sendable {
    case text(String)
    case richText(Data)
    case string(String)
    case bool(Bool)
    case identifier(UUID?)
    case tombstone(Bool)
}

public enum RevisionChangeType: String, Codable, Sendable {
    case create, edit, move, delete, status, publishingExclusion, annotation, storyBible, restore
}

public enum RevisionVisibility: Codable, Equatable, Sendable {
    case ownerPrivate
    case authorizedGroup(UUID)
}

public struct RevisionActorIdentity: Codable, Equatable, Sendable {
    public let platformVerifiedID: String?
    public let clientReportedName: String?
    public let deviceID: String?

    public init(platformVerifiedID: String?, clientReportedName: String?, deviceID: String?) {
        self.platformVerifiedID = platformVerifiedID
        self.clientReportedName = clientReportedName
        self.deviceID = deviceID
    }
}

public struct RevisionContribution: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let entityID: UUID
    public let projectID: UUID
    public let parentRevisionIDs: Set<UUID>
    public let actor: RevisionActorIdentity
    public let timestamp: Date
    public let scope: String
    public let affectedFields: Set<String>
    public let before: [String: RevisionValue]
    public let after: [String: RevisionValue]
    public let changeType: RevisionChangeType
    public let effectiveRole: String
    public let policyVersion: Int
    public let provenanceSource: String
    public let visibility: RevisionVisibility

    public init(
        id: UUID = UUID(),
        entityID: UUID,
        projectID: UUID,
        parentRevisionIDs: Set<UUID>,
        actor: RevisionActorIdentity,
        timestamp: Date,
        scope: String,
        affectedFields: Set<String>,
        before: [String: RevisionValue],
        after: [String: RevisionValue],
        changeType: RevisionChangeType,
        effectiveRole: String,
        policyVersion: Int,
        provenanceSource: String,
        visibility: RevisionVisibility
    ) {
        self.id = id
        self.entityID = entityID
        self.projectID = projectID
        self.parentRevisionIDs = parentRevisionIDs
        self.actor = actor
        self.timestamp = timestamp
        self.scope = scope
        self.affectedFields = affectedFields
        self.before = before
        self.after = after
        self.changeType = changeType
        self.effectiveRole = effectiveRole
        self.policyVersion = policyVersion
        self.provenanceSource = provenanceSource
        self.visibility = visibility
    }
}

public struct RevisionConflict: Equatable, Sendable {
    public let entityID: UUID
    public let headRevisionIDs: Set<UUID>
}

public enum RevisionArchiveError: Error, Equatable, Sendable {
    case identifierCollision(UUID)
    case revisionNotFound(UUID)
    case invalidRestorationTarget(UUID)
}

@MainActor
public final class RevisionContributionArchive {
    private struct State: Codable {
        var contributions: [UUID: RevisionContribution] = [:]
        var consumedDeliveries: Set<String> = []
        var historyTokens: [String: Data] = [:]
    }

    private let fileURL: URL
    private var state: State

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
        } else {
            state = State()
        }
    }

    @discardableResult
    public func ingest(_ contribution: RevisionContribution, deliveryID: String? = nil) throws -> Bool {
        if let deliveryID, state.consumedDeliveries.contains(deliveryID) { return false }
        if let existing = state.contributions[contribution.id] {
            guard existing == contribution else { throw RevisionArchiveError.identifierCollision(contribution.id) }
            if let deliveryID { state.consumedDeliveries.insert(deliveryID) }
            try persist()
            return false
        }
        state.contributions[contribution.id] = contribution
        if let deliveryID { state.consumedDeliveries.insert(deliveryID) }
        try persist()
        return true
    }

    public func contribution(id: UUID) -> RevisionContribution? { state.contributions[id] }

    public func contributions(entityID: UUID, visibleTo groupID: UUID? = nil) -> [RevisionContribution] {
        state.contributions.values.filter { contribution in
            guard contribution.entityID == entityID else { return false }
            if let groupID { return contribution.visibility == .authorizedGroup(groupID) }
            return true
        }.sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
    }

    public func heads(entityID: UUID) -> Set<UUID> {
        let revisions = state.contributions.values.filter { $0.entityID == entityID }
        let parentIDs = Set(revisions.flatMap(\.parentRevisionIDs))
        return Set(revisions.map(\.id)).subtracting(parentIDs)
    }

    public func conflict(entityID: UUID) -> RevisionConflict? {
        let headIDs = heads(entityID: entityID)
        return headIDs.count > 1 ? RevisionConflict(entityID: entityID, headRevisionIDs: headIDs) : nil
    }

    @discardableResult
    public func restore(
        revisionID: UUID,
        actor: RevisionActorIdentity,
        timestamp: Date,
        effectiveRole: String,
        policyVersion: Int
    ) throws -> RevisionContribution {
        guard let target = state.contributions[revisionID] else {
            throw RevisionArchiveError.revisionNotFound(revisionID)
        }
        let currentHeads = heads(entityID: target.entityID)
        guard !currentHeads.isEmpty else { throw RevisionArchiveError.invalidRestorationTarget(revisionID) }
        let restored = RevisionContribution(
            entityID: target.entityID,
            projectID: target.projectID,
            parentRevisionIDs: currentHeads,
            actor: actor,
            timestamp: timestamp,
            scope: target.scope,
            affectedFields: Set(target.after.keys),
            before: [:],
            after: target.after,
            changeType: .restore,
            effectiveRole: effectiveRole,
            policyVersion: policyVersion,
            provenanceSource: "owner.restore",
            visibility: .ownerPrivate
        )
        try ingest(restored)
        return restored
    }

    public func setHistoryToken(_ token: Data?, forStore storeIdentifier: String) throws {
        state.historyTokens[storeIdentifier] = token
        try persist()
    }

    public func historyToken(forStore storeIdentifier: String) -> Data? {
        state.historyTokens[storeIdentifier]
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
