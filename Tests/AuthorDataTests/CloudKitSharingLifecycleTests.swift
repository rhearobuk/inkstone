import CoreData
import Foundation
import Testing
@testable import AuthorData

@Suite("CloudKit sharing lifecycle")
@MainActor
struct CloudKitSharingLifecycleTests {
    @Test("Unsigned local-only builds fail explicitly")
    func localOnlyBuild() async throws {
        let store = try AuthorDataStore(inMemory: true)
        let service = CloudKitSharingService(dataStore: store)
        #expect(service.state == .localOnly)
        await #expect(throws: CloudSharingError.localOnlyBuild) {
            try await service.createPrivateShare(for: [])
        }
    }

    @Test("Private and shared repositories cannot bypass store boundaries")
    func repositoriesRemainScoped() throws {
        let store = try AuthorDataStore(inMemory: true)
        let privateGroups = try store.repository(for: SharingGroup.self, scope: .ownerPrivate)
        let sharedGroups = try store.repository(for: SharingGroup.self, scope: .participantShared)
        let privateID = UUID()
        let sharedID = UUID()
        _ = privateGroups.create(id: privateID) { $0.domain = "manuscript"; $0.state = "private" }
        _ = sharedGroups.create(id: sharedID) { $0.domain = "manuscript"; $0.state = "active" }
        try store.save()
        #expect(try privateGroups.fetch(id: sharedID) == nil)
        #expect(try sharedGroups.fetch(id: privateID) == nil)
    }

    @Test("Partial multi-group outcomes remain retryable and non-atomic")
    func partialWorkflow() {
        let result = SharingWorkflowResult(groups: [
            .init(groupID: UUID(), succeeded: true),
            .init(groupID: UUID(), succeeded: false, message: "network unavailable")
        ])
        #expect(result.isPartial)
        #expect(result.canRetry)
    }
}
