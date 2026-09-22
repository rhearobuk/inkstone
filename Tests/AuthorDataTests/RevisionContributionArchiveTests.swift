import Foundation
import Testing
@testable import AuthorData

@Suite("Durable revision contribution archive", .serialized)
@MainActor
struct RevisionContributionArchiveTests {
    @Test("Offline edits survive either delivery order with rich content recoverable")
    func divergentOfflineEdits() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = fixture.contribution(after: ["richText": .richText(Data("base".utf8))])
        let first = fixture.contribution(parents: [base.id], after: ["richText": .richText(Data("first".utf8))])
        let second = fixture.contribution(parents: [base.id], after: ["richText": .richText(Data("second".utf8))])
        try fixture.archive.ingest(base)
        try fixture.archive.ingest(second)
        try fixture.archive.ingest(first)
        #expect(fixture.archive.conflict(entityID: fixture.entityID)?.headRevisionIDs == [first.id, second.id])
        #expect(fixture.archive.contribution(id: first.id)?.after == first.after)
        #expect(fixture.archive.contribution(id: second.id)?.after == second.after)

        let reverseArchive = try RevisionContributionArchive(
            fileURL: fixture.directory.appendingPathComponent("reverse-revisions.json")
        )
        try reverseArchive.ingest(base)
        try reverseArchive.ingest(first)
        try reverseArchive.ingest(second)
        #expect(reverseArchive.conflict(entityID: fixture.entityID)?.headRevisionIDs == [first.id, second.id])
    }

    @Test("Edit/delete and move/edit races preserve every branch")
    func structuralRaces() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = fixture.contribution(after: ["plainText": .text("draft")])
        let deletion = fixture.contribution(parents: [base.id], after: ["deleted": .tombstone(true)], type: .delete)
        let edit = fixture.contribution(parents: [base.id], after: ["plainText": .text("offline edit")])
        let move = fixture.contribution(parents: [base.id], after: ["parentID": .identifier(UUID())], type: .move)
        for value in [base, deletion, edit, move] { try fixture.archive.ingest(value) }
        #expect(fixture.archive.heads(entityID: fixture.entityID) == [deletion.id, edit.id, move.id])
    }

    @Test("Retries, replay, and restart are idempotent and tokens are per store")
    func idempotencyAndRestart() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let revision = fixture.contribution(after: ["plainText": .text("once")])
        #expect(try fixture.archive.ingest(revision, deliveryID: "transaction-1"))
        #expect(try !fixture.archive.ingest(revision, deliveryID: "transaction-1"))
        try fixture.archive.setHistoryToken(Data([1]), forStore: "Private")
        try fixture.archive.setHistoryToken(Data([2]), forStore: "Shared")
        let reopened = try RevisionContributionArchive(fileURL: fixture.fileURL)
        #expect(reopened.contributions(entityID: fixture.entityID).count == 1)
        #expect(reopened.historyToken(forStore: "Private") == Data([1]))
        #expect(reopened.historyToken(forStore: "Shared") == Data([2]))
    }

    @Test("Private history never appears in an authorized group archive view")
    func visibilityBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let groupID = UUID()
        let privateDraft = fixture.contribution(after: ["plainText": .text("private")])
        let sharedEdit = fixture.contribution(after: ["plainText": .text("reviewable")], visibility: .authorizedGroup(groupID))
        try fixture.archive.ingest(privateDraft)
        try fixture.archive.ingest(sharedEdit)
        #expect(fixture.archive.contributions(entityID: fixture.entityID, visibleTo: groupID).map(\.id) == [sharedEdit.id])
    }

    @Test("Restoration is a new audited revision and retains conflict history")
    func auditedRestore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = fixture.contribution(after: ["plainText": .text("original")])
        let changed = fixture.contribution(parents: [original.id], after: ["plainText": .text("changed")])
        try fixture.archive.ingest(original)
        try fixture.archive.ingest(changed)
        let restored = try fixture.archive.restore(
            revisionID: original.id,
            actor: fixture.actor,
            timestamp: Date(timeIntervalSince1970: 3),
            effectiveRole: "owner",
            policyVersion: 2
        )
        #expect(restored.changeType == .restore)
        #expect(restored.parentRevisionIDs == [changed.id])
        #expect(restored.after == original.after)
        #expect(fixture.archive.contributions(entityID: fixture.entityID).count == 3)
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let fileURL: URL
        let archive: RevisionContributionArchive
        let entityID = UUID()
        let projectID = UUID()
        let actor = RevisionActorIdentity(platformVerifiedID: "platform-user", clientReportedName: "Alice", deviceID: "device-a")

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            fileURL = directory.appendingPathComponent("revisions.json")
            archive = try RevisionContributionArchive(fileURL: fileURL)
        }

        func contribution(
            parents: Set<UUID> = [],
            after: [String: RevisionValue],
            type: RevisionChangeType = .edit,
            visibility: RevisionVisibility = .ownerPrivate
        ) -> RevisionContribution {
            RevisionContribution(
                entityID: entityID, projectID: projectID, parentRevisionIDs: parents, actor: actor,
                timestamp: Date(), scope: "document", affectedFields: Set(after.keys), before: [:], after: after,
                changeType: type, effectiveRole: "editor", policyVersion: 1,
                provenanceSource: "client.authored", visibility: visibility
            )
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
