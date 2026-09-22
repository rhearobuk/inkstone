import Foundation

public enum SharingRole: String, Codable, CaseIterable, Sendable {
    case viewer, reviewer, editor, collaborator, owner
}

public enum SharingCommand: String, Codable, CaseIterable, Sendable {
    case readManuscript, readMetadata, search, export, useAIContext
    case createFeedback, editFeedback
    case editProse, editMetadata, editStructure, editResource
    case readStoryContext, editStoryContext
    case administerSharing, readPrivateHistory
}

public struct SharingAuthorization: Codable, Equatable, Sendable {
    public let role: SharingRole
    public let authorizedRecordIDs: Set<UUID>
    public let storyBibleGrant: StoryBibleGrant
    public let externalAIConsent: Bool
    public let policyVersion: Int

    public init(role: SharingRole, authorizedRecordIDs: Set<UUID>, storyBibleGrant: StoryBibleGrant = .none,
                externalAIConsent: Bool = false, policyVersion: Int) {
        self.role = role
        self.authorizedRecordIDs = authorizedRecordIDs
        self.storyBibleGrant = storyBibleGrant
        self.externalAIConsent = externalAIConsent
        self.policyVersion = policyVersion
    }
}

public enum SharingAuthorizationError: Error, Equatable, LocalizedError, Sendable {
    case unauthorizedCommand(SharingCommand)
    case inaccessibleRecord
    case externalAIConsentRequired
    case unsupportedOverlappingContext(UUID)

    public var errorDescription: String? {
        switch self {
        case .unauthorizedCommand(let command): "The participant cannot perform \(command.rawValue)."
        case .inaccessibleRecord: "The requested record is unavailable."
        case .externalAIConsentRequired: "External AI access requires the author's existing explicit consent."
        case .unsupportedOverlappingContext: "A canonical Story Bible entity cannot belong to overlapping context groups."
        }
    }
}

public struct SharingCommandAuthorizer: Sendable {
    public init() {}

    public func authorize(_ command: SharingCommand, recordID: UUID,
                          using authorization: SharingAuthorization) throws {
        guard authorization.authorizedRecordIDs.contains(recordID) || isGrantedStoryRecord(recordID, authorization.storyBibleGrant) else {
            throw SharingAuthorizationError.inaccessibleRecord
        }
        guard capabilities(for: authorization.role, storyBible: authorization.storyBibleGrant).contains(command) else {
            throw SharingAuthorizationError.unauthorizedCommand(command)
        }
        if command == .useAIContext, !authorization.externalAIConsent {
            throw SharingAuthorizationError.externalAIConsentRequired
        }
    }

    public func capabilities(for role: SharingRole, storyBible: StoryBibleGrant) -> Set<SharingCommand> {
        var result: Set<SharingCommand>
        switch role {
        case .viewer:
            result = [.readManuscript, .readMetadata, .search, .export, .useAIContext]
        case .reviewer:
            result = [.readManuscript, .readMetadata, .search, .export, .useAIContext, .createFeedback, .editFeedback]
        case .editor:
            result = [.readManuscript, .readMetadata, .search, .export, .useAIContext,
                      .createFeedback, .editFeedback, .editProse, .editMetadata]
        case .collaborator:
            result = Set(SharingCommand.allCases).subtracting([.administerSharing, .readPrivateHistory])
        case .owner:
            result = Set(SharingCommand.allCases)
        }
        result.remove(.readStoryContext)
        result.remove(.editStoryContext)
        switch storyBible {
        case .none: break
        case .selected(let ids):
            if !ids.isEmpty { result.insert(.readStoryContext) }
        case .fullRead: result.insert(.readStoryContext)
        case .edit:
            result.insert(.readStoryContext)
            result.insert(.editStoryContext)
        }
        if role == .owner {
            result.insert(.readStoryContext)
            result.insert(.editStoryContext)
        }
        if role != .owner && role != .collaborator { result.remove(.editStoryContext) }
        return result
    }

    private func isGrantedStoryRecord(_ id: UUID, _ grant: StoryBibleGrant) -> Bool {
        switch grant {
        case .none: false
        case .selected(let ids): ids.contains(id)
        case .fullRead, .edit: true
        }
    }
}

public struct PermissionedCommandGateway: Sendable {
    public let authorization: SharingAuthorization
    private let authorizer = SharingCommandAuthorizer()

    public init(authorization: SharingAuthorization) { self.authorization = authorization }

    public func perform<T: Sendable>(_ command: SharingCommand, recordID: UUID,
                                     operation: @Sendable () async throws -> T) async throws -> T {
        try authorizer.authorize(command, recordID: recordID, using: authorization)
        return try await operation()
    }
}

public enum FeedbackAnchorState: String, Codable, Sendable { case current, stale, documentDeleted, accessWithdrawn }

public struct FeedbackAnchor: Codable, Equatable, Sendable {
    public let documentID: UUID
    public let revisionID: UUID
    public let contentHash: String
    public let state: FeedbackAnchorState

    public init(documentID: UUID, revisionID: UUID, contentHash: String, state: FeedbackAnchorState) {
        self.documentID = documentID
        self.revisionID = revisionID
        self.contentHash = contentHash
        self.state = state
    }
}

public struct FeedbackGroupDescriptor: Codable, Equatable, Sendable {
    public let groupID: UUID
    public let manuscriptGroupID: UUID
    public let reviewerID: String
    public let anchor: FeedbackAnchor
    public let manuscriptPermission: String
    public let feedbackPermission: String

    public init(groupID: UUID, manuscriptGroupID: UUID, reviewerID: String, anchor: FeedbackAnchor) {
        self.groupID = groupID
        self.manuscriptGroupID = manuscriptGroupID
        self.reviewerID = reviewerID
        self.anchor = anchor
        manuscriptPermission = "readOnly"
        feedbackPermission = "readWrite"
    }
}

public struct StoryContextGroupValidator: Sendable {
    public init() {}
    public func validate(assignments: [UUID: [UUID]]) throws {
        for (entityID, groups) in assignments where Set(groups).count > 1 {
            throw SharingAuthorizationError.unsupportedOverlappingContext(entityID)
        }
    }
}
