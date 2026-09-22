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
    public static let cloudKitContainerIdentifier = "iCloud.com.robertrhea.scribe"

    public let container: NSPersistentCloudKitContainer
    public let cloudKitSyncEnabled: Bool
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

        let syncsToCloudKit = cloudKitSyncEnabled && !inMemory
        self.cloudKitSyncEnabled = syncsToCloudKit
        container = NSPersistentCloudKitContainer(name: "AuthorData", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            description.url = storeURL
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        // CloudKit mirroring requires persistent history tracking and remote change
        // notifications so every device can replay and merge one another's changes.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = syncsToCloudKit
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
            : nil
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw PersistenceError.storeLoadFailed(loadError) }

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true

        editorPersonas = EntityRepository(context: container.viewContext)
        editorialReviews = EntityRepository(context: container.viewContext)
        editorialInputs = EntityRepository(context: container.viewContext)
        editorialFindings = EntityRepository(context: container.viewContext)
        editorialAnchors = EntityRepository(context: container.viewContext)
        editorialChunks = EntityRepository(context: container.viewContext)
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
        galleryItems = EntityRepository(context: container.viewContext)
        storyBibleCards = EntityRepository(context: container.viewContext)
        storyBibleNotes = EntityRepository(context: container.viewContext)
        storyBibleRelationships = EntityRepository(context: container.viewContext)
        sharingGroups = EntityRepository(context: container.viewContext)
        shareParticipants = EntityRepository(context: container.viewContext)
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
            context.processPendingChanges()
        }
    }

    public func rollback() {
        context.rollback()
    }

    /// Returns a repository constrained to one physical persistent store.
    ///
    /// The single unconfigured V12 store is treated as private during the
    /// additive migration. Collaboration routing is unavailable until a store
    /// using the Collaboration model configuration is loaded.
    public func repository<Model: AuthorManagedObject>(
        for model: Model.Type,
        scope: AuthorStoreScope
    ) throws -> EntityRepository<Model> {
        let stores = container.persistentStoreCoordinator.persistentStores
        let store = stores.first { $0.configurationName == scope.configurationName }
            ?? (scope == .privateData && stores.count == 1 ? stores[0] : nil)
        guard let store else { throw PersistenceError.storeNotFound(scope) }
        return EntityRepository(context: context, persistentStore: store)
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
