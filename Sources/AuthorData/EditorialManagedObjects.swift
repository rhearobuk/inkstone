import CoreData
import Foundation

@objc(EditorPersona)
public final class EditorPersona: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var presetKey: String
    @NSManaged public var instructions: String
    @NSManaged public var version: Int64
    @NSManaged public var isBuiltIn: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var reviews: Set<EditorialReview>
}

@objc(EditorialReview)
public final class EditorialReview: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var targetID: UUID
    @NSManaged public var targetTitle: String
    @NSManaged public var scope: String
    @NSManaged public var personaName: String
    @NSManaged public var personaInstructions: String
    @NSManaged public var personaVersion: Int64
    @NSManaged public var providerID: String
    @NSManaged public var modelID: String
    @NSManaged public var promptVersion: String
    @NSManaged public var schemaVersion: String
    @NSManaged public var parameters: String
    @NSManaged public var environment: String
    @NSManaged public var summary: String
    @NSManaged public var status: String
    @NSManaged public var createdAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var errorMessage: String?
    @NSManaged public var previousReviewID: UUID?
    @NSManaged public var inputTokens: NSNumber?
    @NSManaged public var outputTokens: NSNumber?
    @NSManaged public var project: WritingProject?
    @NSManaged public var target: Document?
    @NSManaged public var persona: EditorPersona?
    @NSManaged public var inputs: Set<EditorialReviewInput>
    @NSManaged public var findings: Set<EditorialFinding>
    @NSManaged public var chunks: Set<EditorialReviewChunk>
}

@objc(EditorialReviewInput)
public final class EditorialReviewInput: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var documentID: UUID
    @NSManaged public var title: String
    @NSManaged public var path: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var plainText: String
    @NSManaged public var contentHash: String
    @NSManaged public var role: String
    @NSManaged public var document: Document?
    @NSManaged public var review: EditorialReview?
    @NSManaged public var anchors: Set<EditorialFindingAnchor>
    @NSManaged public var chunks: Set<EditorialReviewChunk>
}

@objc(EditorialFinding)
public final class EditorialFinding: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var category: String
    @NSManaged public var severity: String
    @NSManaged public var title: String
    @NSManaged public var explanation: String
    @NSManaged public var recommendation: String
    @NSManaged public var status: String
    @NSManaged public var userNote: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var review: EditorialReview?
    @NSManaged public var anchors: Set<EditorialFindingAnchor>
}

@objc(EditorialFindingAnchor)
public final class EditorialFindingAnchor: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var excerpt: String
    @NSManaged public var location: NSNumber?
    @NSManaged public var length: NSNumber?
    @NSManaged public var finding: EditorialFinding?
    @NSManaged public var input: EditorialReviewInput?
}

@objc(EditorialReviewChunk)
public final class EditorialReviewChunk: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var stage: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var location: Int64
    @NSManaged public var length: Int64
    @NSManaged public var status: String
    @NSManaged public var attempts: Int64
    @NSManaged public var summary: String
    @NSManaged public var errorMessage: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var review: EditorialReview?
    @NSManaged public var input: EditorialReviewInput?
}
