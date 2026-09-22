import Foundation
import Testing
@testable import AuthorData

@Suite("Store-aware repositories")
@MainActor
struct StoreAwareRepositoryTests {
    @Test("Private and shared repositories remain physically isolated")
    func physicalStoreRouting() throws {
        let store = try AuthorDataStore(inMemory: true)
        let privateGroups = try store.repository(for: SharingGroup.self, scope: .ownerPrivate)
        let sharedGroups = try store.repository(for: SharingGroup.self, scope: .participantShared)
        let privateGroupID = UUID()
        let sharedGroupID = UUID()
        _ = privateGroups.create(id: privateGroupID) {
            $0.projectID = UUID()
            $0.scopeRootID = UUID()
            $0.domain = SharingGroupDomain.manuscript.rawValue
            $0.state = "private"
        }
        _ = sharedGroups.create(id: sharedGroupID) {
            $0.projectID = UUID()
            $0.scopeRootID = UUID()
            $0.domain = SharingGroupDomain.manuscript.rawValue
            $0.state = "shared"
        }
        try store.save()

        #expect(try privateGroups.fetch(id: privateGroupID) != nil)
        #expect(try privateGroups.fetch(id: sharedGroupID) == nil)
        #expect(try sharedGroups.fetch(id: sharedGroupID) != nil)
        #expect(try sharedGroups.fetch(id: privateGroupID) == nil)
        #expect(try store.sharingGroups.count() == 1)
        #expect(store.privatePersistentStore.configurationName == "Private")
        #expect(store.sharedPersistentStore.configurationName == "Shared")
    }

    @Test("Saving synchronizes scalar routing IDs from private relationships")
    func scalarRoutingIDSynchronization() throws {
        let store = try AuthorDataStore(inMemory: true)
        let projectID = UUID()
        let parentID = UUID()
        let childID = UUID()
        let project = store.projects.create(id: projectID) {
            $0.title = "Routing test"
            $0.sourceIdentifier = "routing.project"
            $0.sourceFormat = "native"
            $0.createdAt = Date()
            $0.modifiedAt = $0.createdAt
        }
        let parent = store.documents.create(id: parentID) {
            $0.sourceIdentifier = "routing.parent"
            $0.title = "Parent"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
        }
        let child = store.documents.create(id: childID) {
            $0.sourceIdentifier = "routing.child"
            $0.title = "Child"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.parent = parent
        }

        try store.save()

        #expect(parent.projectID == projectID)
        #expect(parent.parentID == nil)
        #expect(child.projectID == projectID)
        #expect(child.parentID == parentID)
        #expect(parent.sharingGroupID == nil)
        #expect(child.sharingGroupID == nil)
    }
}
