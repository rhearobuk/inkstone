import CoreData
import Foundation

/// A local, deterministic preflight for `NSPersistentCloudKitContainer` sharing.
///
/// Core Data sharing moves the complete connected object graph into a share's
/// record zone. This audit mirrors that traversal over the objects currently
/// registered in the context, making unintended disclosure visible before any
/// CloudKit operation is attempted.
public enum CoreDataSharingPreflight {
    public struct Exposure: Equatable, Sendable {
        public let entityName: String
        public let objectID: URL
        public let relationshipPath: String

        public init(entityName: String, objectID: URL, relationshipPath: String) {
            self.entityName = entityName
            self.objectID = objectID
            self.relationshipPath = relationshipPath
        }
    }

    public struct Report: Equatable, Sendable {
        public let rootEntityName: String
        public let visitedObjectCount: Int
        public let exposures: [Exposure]

        /// A share is safe only when traversal contains exactly the explicitly
        /// allowed records. This does not make field-level filtering possible.
        public var isObjectGraphSafe: Bool { exposures.isEmpty }
    }

    /// Audits the realized relationship graph rooted at `root`.
    ///
    /// - Important: CloudKit shares entire records. `allowedObjectIDs` controls
    ///   which records may be reached; it cannot hide individual attributes.
    public static func audit(
        root: NSManagedObject,
        allowedObjectIDs: Set<NSManagedObjectID>
    ) -> Report {
        struct Pending {
            let object: NSManagedObject
            let path: String
        }

        var pending = [Pending(object: root, path: root.entity.name ?? "Object")]
        var visited = Set<NSManagedObjectID>()
        var exposures: [Exposure] = []

        while let current = pending.popLast() {
            let object = current.object
            guard visited.insert(object.objectID).inserted else { continue }

            if !allowedObjectIDs.contains(object.objectID) {
                exposures.append(Exposure(
                    entityName: object.entity.name ?? "Unknown",
                    objectID: object.objectID.uriRepresentation(),
                    relationshipPath: current.path
                ))
            }

            for relationship in object.entity.relationshipsByName.values.sorted(by: { $0.name < $1.name }) {
                // CloudKit traverses the persisted Core Data relationship graph. Custom
                // ID-backed accessors deliberately resolve UUID joins for the application,
                // but they are not persisted relationships and must not be treated as such.
                guard let value = object.primitiveValue(forKey: relationship.name) else { continue }
                let relatedObjects: [NSManagedObject]
                if relationship.isToMany {
                    if let set = value as? Set<NSManagedObject> {
                        relatedObjects = Array(set)
                    } else if let set = value as? NSSet {
                        relatedObjects = set.compactMap { $0 as? NSManagedObject }
                    } else {
                        relatedObjects = []
                    }
                } else if let relatedObject = value as? NSManagedObject {
                    relatedObjects = [relatedObject]
                } else {
                    relatedObjects = []
                }

                for relatedObject in relatedObjects {
                    pending.append(Pending(
                        object: relatedObject,
                        path: "\(current.path).\(relationship.name)"
                    ))
                }
            }
        }

        return Report(
            rootEntityName: root.entity.name ?? "Unknown",
            visitedObjectCount: visited.count,
            exposures: exposures.sorted {
                if $0.relationshipPath == $1.relationshipPath {
                    return $0.objectID.absoluteString < $1.objectID.absoluteString
                }
                return $0.relationshipPath < $1.relationshipPath
            }
        )
    }
}
