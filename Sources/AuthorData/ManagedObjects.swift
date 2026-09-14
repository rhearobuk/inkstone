import CoreData
import Foundation

public protocol AuthorManagedObject: NSManagedObject {
    static var entityName: String { get }
    var id: UUID { get set }
}

public extension AuthorManagedObject {
    static var entityName: String { String(describing: Self.self) }
}

@objc(WritingProject)
public final class WritingProject: NSManagedObject, AuthorManagedObject {
    @NSManaged public var editorialReviews: Set<EditorialReview>

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var sourceFormat: String
    @NSManaged public var sourceVersion: String?
    @NSManaged public var creator: String?
    @NSManaged public var author: String?
    @NSManaged public var device: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var sourceModifiedAt: Date?
    @NSManaged public var documents: Set<Document>
    @NSManaged public var resources: Set<ContentResource>
    @NSManaged public var semanticEntities: Set<SemanticEntity>
    @NSManaged public var metadataFields: Set<MetadataField>
    @NSManaged public var labelDefinitions: Set<LabelDefinition>
    @NSManaged public var statusDefinitions: Set<StatusDefinition>
    @NSManaged public var sectionTypeDefinitions: Set<SectionTypeDefinition>
    @NSManaged public var styles: Set<StyleDefinition>
    @NSManaged public var importRuns: Set<ImportRun>
    @NSManaged public var provenanceEvents: Set<ProvenanceEvent>
    @NSManaged public var characterProfiles: Set<CharacterProfile>
    @NSManaged public var galleryItems: Set<GalleryItem>
}

@objc(Document)
public final class Document: NSManagedObject, AuthorManagedObject {
    @NSManaged public var editorialReviews: Set<EditorialReview>
    @NSManaged public var editorialInputs: Set<EditorialReviewInput>

    @NSManaged public var id: UUID
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var title: String
    @NSManaged public var kind: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var includeInCompile: NSNumber?
    @NSManaged public var labelIdentifier: String?
    @NSManaged public var statusIdentifier: String?
    @NSManaged public var sectionTypeIdentifier: String?
    @NSManaged public var selectionLocation: NSNumber?
    @NSManaged public var selectionLength: NSNumber?
    @NSManaged public var selectedChildIdentifier: String?
    @NSManaged public var plainText: String?
    @NSManaged public var synopsis: String?
    @NSManaged public var project: WritingProject
    @NSManaged public var parent: Document?
    @NSManaged public var children: Set<Document>
    @NSManaged public var resources: Set<ContentResource>
    @NSManaged public var metadataValues: Set<MetadataValue>
    @NSManaged public var annotations: Set<Annotation>
    @NSManaged public var revisions: Set<Revision>
    @NSManaged public var outgoingLinks: Set<DocumentLink>
    @NSManaged public var incomingLinks: Set<DocumentLink>
    @NSManaged public var mentions: Set<DocumentEntityMention>
    @NSManaged public var sourceCharacterProfiles: Set<CharacterProfile>
    @NSManaged public var sourceGalleryItems: Set<GalleryItem>

    public var orderedChildren: [Document] {
        children.filter { !$0.isDeleted }.sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
    }
}

@objc(ContentResource)
public final class ContentResource: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourcePath: String
    @NSManaged public var role: String
    @NSManaged public var mediaType: String
    @NSManaged public var byteCount: Int64
    @NSManaged public var sha256: String
    @NSManaged public var data: Data?
    @NSManaged public var textContent: String?
    @NSManaged public var isSourcePreserved: Bool
    @NSManaged public var project: WritingProject
    @NSManaged public var document: Document?
    @NSManaged public var galleryItem: GalleryItem?
}

@objc(GalleryItem)
public final class GalleryItem: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var caption: String?
    @NSManaged public var source: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var project: WritingProject
    @NSManaged public var resource: ContentResource
    @NSManaged public var sourceDocument: Document?
    @NSManaged public var semanticEntity: SemanticEntity?
}

@objc(MetadataField)
public final class MetadataField: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var key: String
    @NSManaged public var displayName: String
    @NSManaged public var valueType: String
    @NSManaged public var semanticPurpose: String?
    @NSManaged public var isSourceDefined: Bool
    @NSManaged public var sourceIdentifier: String?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var project: WritingProject
    @NSManaged public var values: Set<MetadataValue>
}

/// A project-level label definition (Scrivener "LabelSettings/Labels/Label"),
/// used to color-code and categorize documents in the binder.
@objc(LabelDefinition)
public final class LabelDefinition: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var title: String
    @NSManaged public var colorRed: NSNumber?
    @NSManaged public var colorGreen: NSNumber?
    @NSManaged public var colorBlue: NSNumber?
    @NSManaged public var isDefault: Bool
    @NSManaged public var orderIndex: Int64
    @NSManaged public var project: WritingProject
}

/// A project-level status definition (Scrivener "StatusSettings/StatusItems/Status"),
/// used to track a document's draft progress.
@objc(StatusDefinition)
public final class StatusDefinition: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var title: String
    @NSManaged public var isDefault: Bool
    @NSManaged public var orderIndex: Int64
    @NSManaged public var project: WritingProject
}

/// A project-level section type definition (Scrivener "SectionTypes/TypeDefinitions/Type"),
/// used to classify a binder item's structural role (Chapter, Scene, Front Matter, etc).
@objc(SectionTypeDefinition)
public final class SectionTypeDefinition: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var title: String
    @NSManaged public var levelRole: String?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var project: WritingProject
}

@objc(MetadataValue)
public final class MetadataValue: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var stringValue: String?
    @NSManaged public var integerValue: NSNumber?
    @NSManaged public var doubleValue: NSNumber?
    @NSManaged public var booleanValue: NSNumber?
    @NSManaged public var dateValue: Date?
    @NSManaged public var sourcePath: String?
    @NSManaged public var field: MetadataField
    @NSManaged public var document: Document
}

@objc(SemanticEntity)
public final class SemanticEntity: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var canonicalName: String
    @NSManaged public var kind: String
    @NSManaged public var summary: String?
    @NSManaged public var source: String
    @NSManaged public var confidence: NSNumber?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var project: WritingProject
    @NSManaged public var aliases: Set<EntityAlias>
    @NSManaged public var mentions: Set<DocumentEntityMention>
    @NSManaged public var characterProfile: CharacterProfile?
    @NSManaged public var galleryItems: Set<GalleryItem>
}

@objc(EntityAlias)
public final class EntityAlias: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var normalizedName: String
    @NSManaged public var semanticEntity: SemanticEntity
}

@objc(DocumentEntityMention)
public final class DocumentEntityMention: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var location: Int64
    @NSManaged public var length: Int64
    @NSManaged public var surfaceText: String
    @NSManaged public var context: String?
    @NSManaged public var source: String
    @NSManaged public var confidence: NSNumber?
    @NSManaged public var document: Document
    @NSManaged public var semanticEntity: SemanticEntity
}

@objc(Annotation)
public final class Annotation: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var kind: String
    @NSManaged public var body: String
    @NSManaged public var location: NSNumber?
    @NSManaged public var length: NSNumber?
    @NSManaged public var author: String?
    @NSManaged public var source: String
    @NSManaged public var status: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var document: Document
}

@objc(Revision)
public final class Revision: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sequence: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var author: String?
    @NSManaged public var source: String
    @NSManaged public var plainText: String?
    @NSManaged public var contentHash: String
    @NSManaged public var summary: String?
    @NSManaged public var document: Document
}

@objc(DocumentLink)
public final class DocumentLink: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var kind: String
    @NSManaged public var sourceLocation: NSNumber?
    @NSManaged public var sourceLength: NSNumber?
    @NSManaged public var label: String?
    @NSManaged public var unresolvedTargetIdentifier: String?
    @NSManaged public var sourceDocument: Document
    @NSManaged public var targetDocument: Document?
}

@objc(StyleDefinition)
public final class StyleDefinition: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var name: String
    @NSManaged public var kind: String
    @NSManaged public var fontChange: String?
    @NSManaged public var shortcut: String?
    @NSManaged public var formatRTF: String?
    @NSManaged public var project: WritingProject
}

@objc(ImportRun)
public final class ImportRun: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var sourceURL: String
    @NSManaged public var sourceFingerprint: String
    @NSManaged public var startedAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var status: String
    @NSManaged public var insertedCount: Int64
    @NSManaged public var updatedCount: Int64
    @NSManaged public var warningCount: Int64
    @NSManaged public var errorMessage: String?
    @NSManaged public var project: WritingProject?
}

@objc(ProvenanceEvent)
public final class ProvenanceEvent: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var eventType: String
    @NSManaged public var agent: String
    @NSManaged public var agentVersion: String?
    @NSManaged public var timestamp: Date
    @NSManaged public var sourceURI: String?
    @NSManaged public var sourceIdentifier: String?
    @NSManaged public var contentHash: String?
    @NSManaged public var details: String?
    @NSManaged public var project: WritingProject
}

@objc(CharacterProfile)
public final class CharacterProfile: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var firstName: String
    @NSManaged public var middleName: String?
    @NSManaged public var lastName: String?
    @NSManaged public var age: NSNumber?
    @NSManaged public var ageText: String?
    @NSManaged public var location: String?
    @NSManaged public var height: String?
    @NSManaged public var weight: String?
    @NSManaged public var physicalDescription: String?
    @NSManaged public var biography: String?
    @NSManaged public var source: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var project: WritingProject
    @NSManaged public var semanticEntity: SemanticEntity
    @NSManaged public var sourceDocument: Document?
    @NSManaged public var measurements: Set<CharacterMeasurement>
    @NSManaged public var notes: Set<CharacterNote>
    @NSManaged public var outgoingRelationships: Set<CharacterRelationship>
    @NSManaged public var incomingRelationships: Set<CharacterRelationship>
    @NSManaged public var conflicts: Set<CharacterConflict>
    @NSManaged public var conflictsInvolving: Set<CharacterConflict>
}

@objc(CharacterMeasurement)
public final class CharacterMeasurement: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var value: String
    @NSManaged public var unit: String?
    @NSManaged public var notes: String?
    @NSManaged public var orderIndex: Int64
    @NSManaged public var characterProfile: CharacterProfile
}

@objc(CharacterNote)
public final class CharacterNote: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String?
    @NSManaged public var body: String
    @NSManaged public var kind: String
    @NSManaged public var source: String
    @NSManaged public var orderIndex: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var characterProfile: CharacterProfile
}

@objc(CharacterRelationship)
public final class CharacterRelationship: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var kind: String
    @NSManaged public var label: String?
    @NSManaged public var notes: String?
    @NSManaged public var source: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var sourceCharacter: CharacterProfile
    @NSManaged public var targetCharacter: CharacterProfile
}

@objc(CharacterConflict)
public final class CharacterConflict: NSManagedObject, AuthorManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var summary: String?
    @NSManaged public var notes: String?
    @NSManaged public var kind: String
    @NSManaged public var status: String
    @NSManaged public var source: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var characterProfile: CharacterProfile
    @NSManaged public var relatedCharacters: Set<CharacterProfile>
}

public enum DocumentKind: String, CaseIterable, Sendable {
    case draftFolder = "DraftFolder"
    case folder = "Folder"
    case text = "Text"
    case image = "Image"
    case pdf = "PDF"
    case webArchive = "WebArchive"
    case unknown
}

public enum SemanticEntityKind: String, CaseIterable, Sendable {
    case character, location, organization, object, event, concept, theme, relationship, timeline, other
}

public enum AnnotationKind: String, CaseIterable, Sendable {
    case note, comment, highlight, todo, question, warning, modelSuggestion
}

public enum ProvenanceAgent: String, Sendable {
    case human, sourceImport, model, automation
}

public enum CharacterConflictKind: String, CaseIterable, Sendable {
    case `internal`, external, other
}
