import Foundation
import Testing
@testable import AuthorData

@Suite("Store-aware repositories")
@MainActor
struct StoreAwareRepositoryTests {
    @Test("The transitional V12 store is private and collaboration routing is unavailable")
    func transitionalStoreRouting() throws {
        let store = try AuthorDataStore(inMemory: true)
        let privateGroups = try store.repository(for: SharingGroup.self, scope: .privateData)
        let groupID = UUID()
        _ = privateGroups.create(id: groupID) {
            $0.projectID = UUID()
            $0.scopeRootID = UUID()
            $0.domain = SharingGroupDomain.manuscript.rawValue
            $0.state = "private"
        }
        try store.save()

        #expect(try privateGroups.require(id: groupID).id == groupID)
        do {
            _ = try store.repository(for: SharingGroup.self, scope: .collaboration)
            Issue.record("Collaboration routing unexpectedly resolved to the private store.")
        } catch PersistenceError.storeNotFound(let scope) {
            #expect(scope == .collaboration)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
