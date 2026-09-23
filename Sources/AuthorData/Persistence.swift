import CloudKit
import CoreData
import Foundation

public enum PersistenceError: LocalizedError {
    case modelNotFound
    case modelInvalid(String)
    case storeLoadFailed(Error)
    case storeNotFound(AuthorStoreScope)
    case objectNotFound(entity: String, id: UUID)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "AuthorData.momd was not found in package resources."
        case .modelInvalid(let detail):
            return "The Core Data model is invalid: \(detail)"
        case .storeLoadFailed(let error):
            let nsError = error as NSError
            return "The persistent store failed to load: \(nsError.localizedDescription) (\(nsError.domain) \(nsError.code)) \(nsError.userInfo)"
        case .storeNotFound(let scope):
            return "No \(scope.rawValue) persistent store is loaded."
        case .objectNotFound(let entity, let id):
            return "\(entity) \(id) was not found."
        }
    }
}

@MainActor
public final class AuthorDataStore {
    /// The iCloud container used to mirror the store via CloudKit. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entry in the app's entitlements.
    public static let cloudKitContainerIdentifier = "iCloud.com.robertrhea.inkstone"

    public let container: NSPersistentCloudKitContainer
    public let cloudKitSyncEnabled: Bool
    public let privatePersistentStore: NSPersistentStore
    public let sharedPersistentStore: NSPersistentStore
    /// Set only while operating in a participant shared session. Owner-private sessions leave this nil.
    public var sharingAuthorization: SharingAuthorization?
    public var context: NSManagedObjectContext { container.viewContext }

    public let editorPersonas: EntityRepository<EditorPersona>
    public let editorialReviews: EntityRepository<EditorialReview>
    public let editorialInputs: EntityRepository<EditorialReviewInput>
    public let editorialFindings: EntityRepository<EditorialFinding>
    public let editorialAnchors: EntityRepository<EditorialFindingAnchor>
    public let editorialChunks: EntityRepository<EditorialReviewChunk>
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
    public let galleryItems: EntityRepository<GalleryItem>
    public let storyBibleCards: EntityRepository<StoryBibleCard>
    public let storyBibleNotes: EntityRepository<StoryBibleNote>
    public let storyBibleRelationships: EntityRepository<StoryBibleRelationship>
    public let sharingGroups: EntityRepository<SharingGroup>
    public let shareParticipants: EntityRepository<ShareParticipant>

    /// Opens the on-disk store, mirroring it to iCloud via CloudKit. Plain `swift run` builds
    /// aren't code-signed with the iCloud entitlement, so only that specific development-only
    /// failure falls back to a local store. Schema, migration, and corruption errors are surfaced
    /// instead of silently disabling sync.
    public static func open(storeURL: URL) throws -> AuthorDataStore {
        do {
            return try AuthorDataStore(storeURL: storeURL, cloudKitSyncEnabled: true)
        } catch {
            guard isMissingCloudKitEntitlementError(error) else { throw error }
            #if DEBUG
            print("AuthorDataStore: this unsigned build has no iCloud entitlement; opening a local-only store.")
            #endif
            return try AuthorDataStore(storeURL: storeURL, cloudKitSyncEnabled: false)
        }
    }

    private static func isMissingCloudKitEntitlementError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var visited = Set<ObjectIdentifier>()
        while let candidate = current, visited.insert(ObjectIdentifier(candidate)).inserted {
            let detail = [
                candidate.localizedDescription,
                candidate.localizedFailureReason,
                candidate.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            if detail.contains("entitlement"),
               detail.contains("icloud") || detail.contains("cloudkit") {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// - Parameters:
    ///   - storeURL: Location of the on-disk SQLite store. Ignored when `inMemory` is `true`.
    ///   - inMemory: Uses a throwaway in-memory store (previews/tests) with CloudKit sync disabled.
    ///   - cloudKitSyncEnabled: Mirrors the store to the user's private iCloud database via
    ///     CloudKit so changes propagate instantly across their devices. Defaults to `false` so
    ///     unsigned contexts (unit tests, SwiftPM command-line tools) keep working without an
    ///     iCloud entitlement; the shipping app opts in explicitly. Automatically disabled when
    ///     `inMemory` is `true`, since `NSInMemoryStoreType` cannot be mirrored.
    public init(storeURL: URL? = nil, inMemory: Bool = false, cloudKitSyncEnabled: Bool = false) throws {
        guard let modelURL = Bundle.module.url(forResource: "AuthorData", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw PersistenceError.modelNotFound
        }
        guard model.entities.allSatisfy({ $0.managedObjectClassName != nil }) else {
            throw PersistenceError.modelInvalid("one or more entities have no managed object class")
        }

        model.setEntities(model.entities, forConfigurationName: AuthorStoreScope.ownerPrivate.configurationName)
        model.setEntities(model.entities, forConfigurationName: AuthorStoreScope.participantShared.configurationName)

        let syncsToCloudKit = cloudKitSyncEnabled && !inMemory
        self.cloudKitSyncEnabled = syncsToCloudKit
        container = NSPersistentCloudKitContainer(name: "AuthorData", managedObjectModel: model)

        let privateDescription = NSPersistentStoreDescription()
        privateDescription.configuration = AuthorStoreScope.ownerPrivate.configurationName
        let sharedDescription = NSPersistentStoreDescription()
        sharedDescription.configuration = AuthorStoreScope.participantShared.configurationName
        if inMemory {
            privateDescription.type = NSInMemoryStoreType
            privateDescription.url = URL(fileURLWithPath: "/dev/null/author-private-\(UUID().uuidString)")
            sharedDescription.type = NSInMemoryStoreType
            sharedDescription.url = URL(fileURLWithPath: "/dev/null/author-shared-\(UUID().uuidString)")
        } else {
            let privateURL = storeURL ?? NSPersistentContainer.defaultDirectoryURL()
                .appendingPathComponent("AuthorData.sqlite")
            let sharedURL = Self.sharedStoreURL(for: privateURL)
            for (description, url) in [(privateDescription, privateURL), (sharedDescription, sharedURL)] {
                description.type = NSSQLiteStoreType
                description.url = url
                description.shouldMigrateStoreAutomatically = true
                description.shouldInferMappingModelAutomatically = true
            }
        }
        for description in [privateDescription, sharedDescription] {
            description.shouldAddStoreAsynchronously = false
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        if syncsToCloudKit {
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
        }
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw PersistenceError.storeLoadFailed(loadError) }
        guard let loadedPrivateStore = container.persistentStoreCoordinator.persistentStores.first(where: {
            $0.configurationName == AuthorStoreScope.ownerPrivate.configurationName
        }) else {
            throw PersistenceError.storeNotFound(.ownerPrivate)
        }
        guard let loadedSharedStore = container.persistentStoreCoordinator.persistentStores.first(where: {
            $0.configurationName == AuthorStoreScope.participantShared.configurationName
        }) else {
            throw PersistenceError.storeNotFound(.participantShared)
        }
        privatePersistentStore = loadedPrivateStore
        sharedPersistentStore = loadedSharedStore

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true

        editorPersonas = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        editorialReviews = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        editorialInputs = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        editorialFindings = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        editorialAnchors = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        editorialChunks = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        projects = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        documents = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        resources = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        metadataFields = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        labelDefinitions = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        statusDefinitions = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        sectionTypeDefinitions = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        metadataValues = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        semanticEntities = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        entityAliases = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        mentions = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        annotations = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        revisions = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        links = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        styles = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        importRuns = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        provenanceEvents = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        characterProfiles = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        characterMeasurements = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        characterNotes = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        characterRelationships = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        characterConflicts = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        galleryItems = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        storyBibleCards = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        storyBibleNotes = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        storyBibleRelationships = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        sharingGroups = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
        shareParticipants = EntityRepository(context: container.viewContext, persistentStore: loadedPrivateStore)
    }

    public static func sharedStoreURL(for privateStoreURL: URL) -> URL {
        privateStoreURL
            .deletingPathExtension()
            .appendingPathExtension("shared")
            .appendingPathExtension("sqlite")
    }

    private static func backfillLegacyRoutingIDs(
        context: NSManagedObjectContext,
        privateStore: NSPersistentStore
    ) throws {
        let documentRequest = NSFetchRequest<Document>(entityName: Document.entityName)
        documentRequest.affectedStores = [privateStore]
        documentRequest.predicate = NSPredicate(format: "projectID == nil OR parentID == nil")

        let semanticEntityRequest = NSFetchRequest<SemanticEntity>(entityName: SemanticEntity.entityName)
        semanticEntityRequest.affectedStores = [privateStore]
        semanticEntityRequest.predicate = NSPredicate(format: "projectID == nil")

        let objects = Set<NSManagedObject>(try context.fetch(documentRequest))
            .union(try context.fetch(semanticEntityRequest))
        synchronizeRoutingIDs(in: objects)
        if context.hasChanges {
            try context.save()
            context.processPendingChanges()
        }
    }

    private static func synchronizeRoutingIDs(in objects: Set<NSManagedObject>) {
        for object in objects {
            if let document = object as? Document {
                let project = document.primitiveValue(forKey: "project") as? WritingProject
                let parent = document.primitiveValue(forKey: "parent") as? Document
                if let project { document.projectID = project.id }
                if let parent { document.parentID = parent.id }
            } else if let semanticEntity = object as? SemanticEntity {
                let project = semanticEntity.primitiveValue(forKey: "project") as? WritingProject
                if let project { semanticEntity.projectID = project.id }
            }
        }
    }

    public func save() throws {
        if context.hasChanges {
            if let sharingAuthorization {
                try SharingMutationGuard().validate(
                    inserted: context.insertedObjects,
                    updated: context.updatedObjects,
                    deleted: context.deletedObjects,
                    authorization: sharingAuthorization
                )
            }
            Self.synchronizeRoutingIDs(in: context.insertedObjects.union(context.updatedObjects))
            try context.save()
            context.processPendingChanges()
        }
    }

    public func rollback() {
        context.rollback()
    }

    /// Returns a repository constrained to one physical persistent store.
    ///
    /// A single unconfigured store is treated as the owner's private
    /// database during the additive migration. Participant-shared routing is
    /// unavailable until a store using the Shared configuration is loaded.
    public func repository<Model: AuthorManagedObject>(
        for model: Model.Type,
        scope: AuthorStoreScope
    ) throws -> EntityRepository<Model> {
        let stores = container.persistentStoreCoordinator.persistentStores
        let store = stores.first { $0.configurationName == scope.configurationName }
            ?? (scope == .ownerPrivate && stores.count == 1 ? stores[0] : nil)
        guard let store else { throw PersistenceError.storeNotFound(scope) }
        return EntityRepository(context: context, persistentStore: store)
    }

    /// Fetches a record for display regardless of whether CloudKit placed it in
    /// the owner's private store or a participant's shared store.
    public func fetchAcrossStores<Model: AuthorManagedObject>(
        _ model: Model.Type,
        id: UUID
    ) throws -> Model? {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let matches = try context.fetch(request)
        if Model.self == Document.self {
            return matches.first { ($0 as? Document)?.sharingGroupID == nil }
                ?? matches.first
        }
        if Model.self == WritingProject.self {
            return matches.first {
                ($0 as? WritingProject)?.sourceFormat != CloudKitSharingService.scopedProjectionSourceFormat
            } ?? matches.first
        }
        return matches.first
    }

    /// Fetches display records from both the private and shared databases. New
    /// records must still be created through a store-scoped repository.
    public func fetchAcrossStores<Model: AuthorManagedObject>(
        _ model: Model.Type,
        predicate: NSPredicate? = nil,
        sortedBy sortDescriptors: [NSSortDescriptor] = []
    ) throws -> [Model] {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return try context.fetch(request)
    }

    public func scope(of object: NSManagedObject) -> AuthorStoreScope? {
        guard let persistentStore = object.objectID.persistentStore else { return nil }
        if persistentStore === sharedPersistentStore { return .participantShared }
        if persistentStore === privatePersistentStore { return .ownerPrivate }
        return nil
    }
}

@MainActor
public final class EntityRepository<Model: AuthorManagedObject> {
    private let context: NSManagedObjectContext
    private let persistentStore: NSPersistentStore?

    init(context: NSManagedObjectContext, persistentStore: NSPersistentStore? = nil) {
        self.context = context
        self.persistentStore = persistentStore
    }

    @discardableResult
    public func create(id: UUID = UUID(), configure: (Model) throws -> Void) rethrows -> Model {
        let object = NSEntityDescription.insertNewObject(
            forEntityName: Model.entityName,
            into: context
        ) as! Model
        if let persistentStore {
            context.assign(object, to: persistentStore)
        }
        object.id = id
        try configure(object)
        return object
    }

    public func fetch(id: UUID) throws -> Model? {
        let request = makeRequest()
        var predicates = [NSPredicate(format: "id == %@", id as CVarArg)]
        if persistentStore?.configurationName == AuthorStoreScope.ownerPrivate.configurationName {
            if Model.self == Document.self {
                predicates.append(NSPredicate(format: "sharingGroupID == nil"))
            } else if Model.self == WritingProject.self {
                predicates.append(NSPredicate(
                    format: "sourceFormat != %@",
                    CloudKitSharingService.scopedProjectionSourceFormat
                ))
            }
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
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
        let request = makeRequest()
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return try context.fetch(request)
    }

    public func count(predicate: NSPredicate? = nil) throws -> Int {
        let request = makeRequest()
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
        if let persistentStore {
            context.assign(object, to: persistentStore)
        }
        object.id = id
        try configure(object, true)
        return object
    }

    private func makeRequest() -> NSFetchRequest<Model> {
        let request = NSFetchRequest<Model>(entityName: Model.entityName)
        if let persistentStore {
            request.affectedStores = [persistentStore]
        }
        return request
    }
}
