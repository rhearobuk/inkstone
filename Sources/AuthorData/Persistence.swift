import CoreData
import Foundation

public enum PersistenceError: LocalizedError {
    case modelNotFound
    case modelInvalid(String)
    case storeLoadFailed(Error)
    case objectNotFound(entity: String, id: UUID)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound: "AuthorData.momd was not found in package resources."
        case .modelInvalid(let detail): "The Core Data model is invalid: \(detail)"
        case .storeLoadFailed(let error): "The persistent store failed to load: \(error.localizedDescription)"
        case .objectNotFound(let entity, let id): "\(entity) \(id) was not found."
        }
    }
}

@MainActor
public final class AuthorDataStore {
    public let container: NSPersistentContainer
    public var context: NSManagedObjectContext { container.viewContext }

    public let projects: EntityRepository<WritingProject>
    public let documents: EntityRepository<Document>
    public let resources: EntityRepository<ContentResource>
    public let metadataFields: EntityRepository<MetadataField>
    public let labelDefinitions: EntityRepository<LabelDefinition>
    public let statusDefinitions: EntityRepository<StatusDefinition>
    public let sectionTypeDefinitions: EntityRepository<SectionTypeDefinition>
    public let metadataValues: EntityRepository<MetadataValue>
    public let semanticEntities: EntityRepository<SemanticEntity>
    public let entityAliases: EntityRepository<EntityAlias>
    public let mentions: EntityRepository<DocumentEntityMention>
    public let annotations: EntityRepository<Annotation>
    public let revisions: EntityRepository<Revision>
    public let links: EntityRepository<DocumentLink>
    public let styles: EntityRepository<StyleDefinition>
    public let importRuns: EntityRepository<ImportRun>
    public let provenanceEvents: EntityRepository<ProvenanceEvent>
    public let characterProfiles: EntityRepository<CharacterProfile>
    public let characterMeasurements: EntityRepository<CharacterMeasurement>
    public let characterNotes: EntityRepository<CharacterNote>
    public let characterRelationships: EntityRepository<CharacterRelationship>
    public let characterConflicts: EntityRepository<CharacterConflict>

    public init(storeURL: URL? = nil, inMemory: Bool = false) throws {
        guard let modelURL = Bundle.module.url(forResource: "AuthorData", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw PersistenceError.modelNotFound
        }
        guard model.entities.allSatisfy({ $0.managedObjectClassName != nil }) else {
            throw PersistenceError.modelInvalid("one or more entities have no managed object class")
        }

        container = NSPersistentContainer(name: "AuthorData", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            description.url = storeURL
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw PersistenceError.storeLoadFailed(loadError) }

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true

        projects = EntityRepository(context: container.viewContext)
        documents = EntityRepository(context: container.viewContext)
        resources = EntityRepository(context: container.viewContext)
        metadataFields = EntityRepository(context: container.viewContext)
        labelDefinitions = EntityRepository(context: container.viewContext)
        statusDefinitions = EntityRepository(context: container.viewContext)
        sectionTypeDefinitions = EntityRepository(context: container.viewContext)
        metadataValues = EntityRepository(context: container.viewContext)
        semanticEntities = EntityRepository(context: container.viewContext)
        entityAliases = EntityRepository(context: container.viewContext)
        mentions = EntityRepository(context: container.viewContext)
        annotations = EntityRepository(context: container.viewContext)
        revisions = EntityRepository(context: container.viewContext)
        links = EntityRepository(context: container.viewContext)
        styles = EntityRepository(context: container.viewContext)
        importRuns = EntityRepository(context: container.viewContext)
        provenanceEvents = EntityRepository(context: container.viewContext)
        characterProfiles = EntityRepository(context: container.viewContext)
        characterMeasurements = EntityRepository(context: container.viewContext)
        characterNotes = EntityRepository(context: container.viewContext)
        characterRelationships = EntityRepository(context: container.viewContext)
        characterConflicts = EntityRepository(context: container.viewContext)
    }

    public func save() throws {
        if context.hasChanges { try context.save() }
    }

    public func rollback() {
        context.rollback()
    }
}

@MainActor
public final class EntityRepository<Model: AuthorManagedObject> {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    public func create(id: UUID = UUID(), configure: (Model) throws -> Void) rethrows -> Model {
        let object = NSEntityDescription.insertNewObject(
            forEntityName: Model.entityName,
            into: context
        ) as! Model
        object.id = id
        try configure(object)
        return object
    }

    public func fetch(id: UUID) throws -> Model? {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public func require(id: UUID) throws -> Model {
        guard let object = try fetch(id: id) else {
            throw PersistenceError.objectNotFound(entity: Model.entityName, id: id)
        }
        return object
    }

    public func fetchAll(
        predicate: NSPredicate? = nil,
        sortedBy sortDescriptors: [NSSortDescriptor] = []
    ) throws -> [Model] {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return try context.fetch(request)
    }

    public func count(predicate: NSPredicate? = nil) throws -> Int {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        request.predicate = predicate
        return try context.count(for: request)
    }

    public func update(id: UUID, configure: (Model) throws -> Void) throws {
        try configure(require(id: id))
    }

    public func delete(id: UUID) throws {
        context.delete(try require(id: id))
    }

    public func upsert(id: UUID, configure: (Model, Bool) throws -> Void) throws -> Model {
        if let existing = try fetch(id: id) {
            try configure(existing, false)
            return existing
        }
        let object = NSEntityDescription.insertNewObject(
            forEntityName: Model.entityName,
            into: context
        ) as! Model
        object.id = id
        try configure(object, true)
        return object
    }
}
