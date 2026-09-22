import CoreData
import Foundation

public enum CanonicalSharingGraphError: Error, Equatable, LocalizedError {
    case recordAlreadyAssigned(recordID: UUID, groupID: UUID)
    case unsafeRelationship(recordID: UUID, relationship: String)

    public var errorDescription: String? {
        switch self {
        case .recordAlreadyAssigned(let recordID, let groupID):
            "Record \(recordID) already belongs to sharing group \(groupID)."
        case .unsafeRelationship(let recordID, let relationship):
            "Record \(recordID) still has unsafe relationship \(relationship)."
        }
    }
}

/// Converts legacy relationship-connected documents to the production sharing boundary.
/// Manuscript records remain canonical; relationships crossing group boundaries become UUID joins.
@MainActor
public struct CanonicalSharingGraphPreparer {
    public init() {}

    public func prepareManuscript(_ documents: [Document], for group: SharingGroup) throws {
        for document in documents {
            if let existing = document.sharingGroupID, existing != group.id {
                throw CanonicalSharingGraphError.recordAlreadyAssigned(recordID: document.id, groupID: existing)
            }
            backfillSidecarIDs(for: document)
            document.parentID = document.parent?.id
            document.sharingGroupID = group.id
            document.sharingGroup = group
            detachUnsafeRelationships(from: document)
        }
        try validate(documents)
    }

    public func prepareFeedback(_ annotation: Annotation, documentID: UUID, for group: SharingGroup) throws {
        if let existing = annotation.sharingGroupID, existing != group.id {
            throw CanonicalSharingGraphError.recordAlreadyAssigned(recordID: annotation.id, groupID: existing)
        }
        annotation.documentID = documentID
        annotation.sharingGroupID = group.id
        annotation.feedbackGroup = group
        annotation.setPrimitiveValue(nil, forKey: "document")
    }

    public func prepareStoryContext(_ entities: [SemanticEntity], for group: SharingGroup) throws {
        for entity in entities {
            if let existing = entity.sharingGroupID, existing != group.id {
                throw CanonicalSharingGraphError.recordAlreadyAssigned(recordID: entity.id, groupID: existing)
            }
            entity.projectID = entity.project.id
            entity.sharingGroupID = group.id
            entity.contextGroup = group
        }
        detachPrivateRecordsFromStoryGraph(roots: entities)
    }

    public func validate(_ documents: [Document]) throws {
        let allowed = Set(["sharingGroup"])
        for document in documents {
            for relationship in document.entity.relationshipsByName.keys where !allowed.contains(relationship) {
                let value = document.primitiveValue(forKey: relationship)
                if let set = value as? NSSet, set.count > 0 {
                    throw CanonicalSharingGraphError.unsafeRelationship(recordID: document.id, relationship: relationship)
                }
                if value is NSManagedObject {
                    throw CanonicalSharingGraphError.unsafeRelationship(recordID: document.id, relationship: relationship)
                }
            }
        }
    }

    private func backfillSidecarIDs(for document: Document) {
        let resources = document.primitiveValue(forKey: "resources") as? Set<ContentResource> ?? []
        for resource in resources { resource.documentID = document.id; resource.projectID = document.projectID }
        let values = document.primitiveValue(forKey: "metadataValues") as? Set<MetadataValue> ?? []
        for value in values { value.documentID = document.id; value.fieldID = value.field.id }
        let annotations = document.primitiveValue(forKey: "annotations") as? Set<Annotation> ?? []
        for annotation in annotations { annotation.documentID = document.id }
        let revisions = document.primitiveValue(forKey: "revisions") as? Set<Revision> ?? []
        for revision in revisions { revision.documentID = document.id }
        let outgoing = document.primitiveValue(forKey: "outgoingLinks") as? Set<DocumentLink> ?? []
        for link in outgoing { link.sourceDocumentID = document.id; link.targetDocumentID = link.targetDocument?.id }
        let incoming = document.primitiveValue(forKey: "incomingLinks") as? Set<DocumentLink> ?? []
        for link in incoming { link.targetDocumentID = document.id; link.sourceDocumentID = link.sourceDocument.id }
        let mentions = document.primitiveValue(forKey: "mentions") as? Set<DocumentEntityMention> ?? []
        for mention in mentions {
            mention.documentID = document.id
            mention.semanticEntityID = mention.semanticEntity.id
        }
    }

    private func detachUnsafeRelationships(from document: Document) {
        let safeRelationships = Set(["sharingGroup"])
        for relationship in document.entity.relationshipsByName.keys where !safeRelationships.contains(relationship) {
            if document.entity.relationshipsByName[relationship]?.isToMany == true {
                document.setPrimitiveValue(NSSet(), forKey: relationship)
            } else {
                document.setPrimitiveValue(nil, forKey: relationship)
            }
        }
    }

    private func detachPrivateRecordsFromStoryGraph(roots: [SemanticEntity]) {
        let allowedEntities = Set([
            SemanticEntity.entityName, EntityAlias.entityName, CharacterProfile.entityName,
            CharacterMeasurement.entityName, CharacterNote.entityName, CharacterRelationship.entityName,
            CharacterConflict.entityName, StoryBibleCard.entityName, StoryBibleNote.entityName,
            StoryBibleRelationship.entityName, SharingGroup.entityName
        ])
        var pending: [NSManagedObject] = roots
        var visited = Set<NSManagedObjectID>()
        while let object = pending.popLast() {
            guard visited.insert(object.objectID).inserted else { continue }
            for relationship in object.entity.relationshipsByName.values {
                guard relationship.name != "contextGroup",
                      let value = object.primitiveValue(forKey: relationship.name) else { continue }
                if relationship.isToMany {
                    let related = (value as? NSSet)?.compactMap { $0 as? NSManagedObject } ?? []
                    let kept = related.filter { allowedEntities.contains($0.entity.name ?? "") }
                    object.setPrimitiveValue(NSSet(array: kept), forKey: relationship.name)
                    pending.append(contentsOf: kept)
                } else if let related = value as? NSManagedObject {
                    if allowedEntities.contains(related.entity.name ?? "") {
                        pending.append(related)
                    } else {
                        object.setPrimitiveValue(nil, forKey: relationship.name)
                    }
                }
            }
        }
    }
}
