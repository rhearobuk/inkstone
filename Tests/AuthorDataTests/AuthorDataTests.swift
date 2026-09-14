import CoreData
import XCTest
@testable import AuthorData

@MainActor
final class AuthorDataTests: XCTestCase {
    func testImportsRealProjectWithHierarchyContentLinksAndIdempotency() throws {
        let store = try AuthorDataStore(inMemory: true)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let xmlURL = root.appendingPathComponent("Cloaked Desire Aidan's Surrender.xml")
        let filesURL = root.appendingPathComponent("Files")
        let importer = ScrivenerImporter(store: store)

        let first = try importer.importProject(xmlURL: xmlURL, filesURL: filesURL)
        XCTAssertEqual(first.documentCount, 284)
        XCTAssertEqual(try store.documents.count(), 284)
        XCTAssertGreaterThan(first.resourceCount, 350)
        XCTAssertGreaterThan(first.linkCount, 15)
        XCTAssertTrue(first.warnings.allSatisfy { !$0.code.isEmpty })

        let project = try store.projects.require(id: first.projectID)
        XCTAssertEqual(project.sourceIdentifier, "935D19E3-65EB-4002-8F1E-95BB314D0B47")
        XCTAssertEqual(project.author, "Evan Blackwood")
        XCTAssertFalse(project.styles.isEmpty)

        let draft = try store.documents.require(id: UUID(uuidString: "4A1D6B18-0952-42EB-A487-D17915DD3BA1")!)
        XCTAssertEqual(draft.kind, "DraftFolder")
        XCTAssertEqual(draft.orderedChildren.first?.title, "The Empyrean Guild")

        let chapter = try store.documents.require(id: UUID(uuidString: "FD75AC3C-F304-4EA6-ADCC-2C32D6589969")!)
        XCTAssertEqual(chapter.orderedChildren.prefix(3).map(\.title), [
            "Final Departures", "Gateway Interview", "Onward to Destiny"
        ])

        let gateway = try store.documents.require(id: UUID(uuidString: "AA6DDF0F-F4E5-46F2-A9AC-805ADDFD5746")!)
        XCTAssertNotNil(gateway.plainText)
        XCTAssertFalse(gateway.plainText?.contains("\\fonttbl") == true)
        XCTAssertFalse(gateway.plainText?.contains("\\colortbl") == true)
        XCTAssertTrue(gateway.resources.contains { $0.role == "content" && $0.data?.isEmpty == false })
        XCTAssertTrue(gateway.outgoingLinks.contains {
            $0.targetDocument?.sourceIdentifier == "CFDF5044-06F5-4130-A7F8-11BEBA8C19C3"
        })
        XCTAssertTrue(gateway.metadataValues.contains {
            $0.field.key == "scrivener.MetaData.Custom.sexualcontent" && $0.stringValue == "R"
        })

        XCTAssertEqual(project.sectionTypeDefinitions.count, 9)
        XCTAssertTrue(project.sectionTypeDefinitions.contains { $0.title == "Chapter Heading" })
        XCTAssertTrue(project.sectionTypeDefinitions.contains {
            $0.sourceIdentifier == "9AFECE21-8C79-45E0-9B9F-D6D62A9729D3" && $0.title == "Scene"
        })

        XCTAssertEqual(project.labelDefinitions.count, 7)
        let intenseLabel = try XCTUnwrap(project.labelDefinitions.first { $0.sourceIdentifier == "7" })
        XCTAssertEqual(intenseLabel.title, "Scenes of Intense Sexuality/Violence")
        XCTAssertNotNil(intenseLabel.colorRed)
        XCTAssertTrue(project.labelDefinitions.contains { $0.sourceIdentifier == "-1" && $0.title == "No Label" })

        XCTAssertEqual(project.statusDefinitions.count, 7)
        XCTAssertTrue(project.statusDefinitions.contains { $0.sourceIdentifier == "4" && $0.title == "Final Draft" })

        let customFields = project.metadataFields.filter { $0.sourceIdentifier != nil }
        XCTAssertEqual(customFields.count, 3)
        XCTAssertTrue(customFields.contains {
            $0.key == "scrivener.MetaData.Custom.sexualcontent" && $0.displayName == "Sexual Content"
        })
        XCTAssertTrue(customFields.contains {
            $0.key == "scrivener.MetaData.Custom.paperbackisbn" && $0.displayName == "Paperback ISBN"
        })

        let illustratedCharacter = try store.documents.require(
            id: UUID(uuidString: "FBD567AB-8642-42E6-84B3-0E213E1FC4DC")!
        )
        let illustratedRTF = try XCTUnwrap(
            illustratedCharacter.resources.first { $0.role == "content" }?.data
        )
        XCTAssertTrue(String(decoding: illustratedRTF, as: UTF8.self).contains("\\jpegblip"))
        XCTAssertFalse(illustratedCharacter.plainText?.contains("\\jpegblip") == true)

        let aidanDocument = try store.documents.require(
            id: UUID(uuidString: "92261C90-C85C-4E52-B2CF-553F92DA7467")!
        )
        let aidan = try XCTUnwrap(aidanDocument.sourceCharacterProfiles.first)
        XCTAssertEqual(aidan.firstName, "Aidan")
        XCTAssertEqual(aidan.middleName, "Dylan")
        XCTAssertEqual(aidan.lastName, "Spalding")
        XCTAssertEqual(aidan.age?.intValue, 21)
        XCTAssertEqual(aidan.location, "London")
        XCTAssertEqual(aidan.height, "6’3")
        XCTAssertFalse(aidan.measurements.isEmpty)
        XCTAssertTrue(aidan.semanticEntity.aliases.contains { $0.name == "Iphis" })
        XCTAssertFalse(aidan.biography?.isEmpty ?? true)
        XCTAssertFalse(aidan.notes.isEmpty)
        XCTAssertFalse(aidan.conflicts.isEmpty)

        let jacobDocument = try store.documents.require(
            id: UUID(uuidString: "4A5215B5-53F1-42D8-9D00-BC0F93EE6F9D")!
        )
        let jacob = try XCTUnwrap(jacobDocument.sourceCharacterProfiles.first)
        XCTAssertTrue(jacob.outgoingRelationships.contains {
            $0.targetCharacter.id == aidan.id
        })

        let documentCount = try store.documents.count()
        let resourceCount = try store.resources.count()
        let characterProfileCount = try store.characterProfiles.count()
        let labelCount = try store.labelDefinitions.count()
        let statusCount = try store.statusDefinitions.count()
        let sectionTypeCount = try store.sectionTypeDefinitions.count()
        XCTAssertGreaterThan(characterProfileCount, 10)
        aidan.firstName = "Edited Aidan"
        let second = try importer.importProject(xmlURL: xmlURL, filesURL: filesURL)
        XCTAssertEqual(try store.documents.count(), documentCount)
        XCTAssertEqual(try store.resources.count(), resourceCount)
        XCTAssertEqual(try store.characterProfiles.count(), characterProfileCount)
        XCTAssertEqual(aidan.firstName, "Edited Aidan")
        XCTAssertEqual(try store.labelDefinitions.count(), labelCount)
        XCTAssertEqual(try store.statusDefinitions.count(), statusCount)
        XCTAssertEqual(try store.sectionTypeDefinitions.count(), sectionTypeCount)
        XCTAssertEqual(second.projectID, first.projectID)
        XCTAssertGreaterThan(second.updatedCount, 0)
        XCTAssertEqual(try store.importRuns.count(), 2)
    }

    func testTypedCRUDForEveryEntity() throws {
        let store = try AuthorDataStore(inMemory: true)
        let now = Date()
        let projectID = UUID()
        let documentID = UUID()

        let project = store.projects.create(id: projectID) {
            $0.title = "Project"
            $0.sourceIdentifier = "project-\(projectID)"
            $0.sourceFormat = "native"
            $0.createdAt = now
            $0.modifiedAt = now
        }
        let document = store.documents.create(id: documentID) {
            $0.sourceIdentifier = "document-\(documentID)"
            $0.title = "Document"
            $0.kind = "Text"
            $0.orderIndex = 0
            $0.project = project
        }
        let resourceID = UUID()
        _ = store.resources.create(id: resourceID) {
            $0.sourcePath = "content.rtf"
            $0.role = "content"
            $0.mediaType = "application/rtf"
            $0.byteCount = 3
            $0.sha256 = "abc"
            $0.isSourcePreserved = true
            $0.project = project
            $0.document = document
        }
        let fieldID = UUID()
        let field = store.metadataFields.create(id: fieldID) {
            $0.key = "story.pov"
            $0.displayName = "POV"
            $0.valueType = "string"
            $0.isSourceDefined = false
            $0.project = project
        }
        let valueID = UUID()
        _ = store.metadataValues.create(id: valueID) {
            $0.stringValue = "Aidan"
            $0.field = field
            $0.document = document
        }
        let entityID = UUID()
        let entity = store.semanticEntities.create(id: entityID) {
            $0.canonicalName = "Aidan"
            $0.kind = SemanticEntityKind.character.rawValue
            $0.source = ProvenanceAgent.human.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
        }
        let aliasID = UUID()
        _ = store.entityAliases.create(id: aliasID) {
            $0.name = "Aid"
            $0.normalizedName = "aid"
            $0.semanticEntity = entity
        }
        let mentionID = UUID()
        _ = store.mentions.create(id: mentionID) {
            $0.location = 0
            $0.length = 5
            $0.surfaceText = "Aidan"
            $0.source = ProvenanceAgent.human.rawValue
            $0.document = document
            $0.semanticEntity = entity
        }
        let annotationID = UUID()
        _ = store.annotations.create(id: annotationID) {
            $0.kind = AnnotationKind.note.rawValue
            $0.body = "Check continuity"
            $0.source = ProvenanceAgent.human.rawValue
            $0.status = "open"
            $0.createdAt = now
            $0.modifiedAt = now
            $0.document = document
        }
        let revisionID = UUID()
        _ = store.revisions.create(id: revisionID) {
            $0.sequence = 1
            $0.createdAt = now
            $0.source = ProvenanceAgent.human.rawValue
            $0.plainText = "Draft"
            $0.contentHash = "hash"
            $0.document = document
        }
        let linkID = UUID()
        _ = store.links.create(id: linkID) {
            $0.kind = "reference"
            $0.sourceDocument = document
            $0.targetDocument = document
        }
        let styleID = UUID()
        _ = store.styles.create(id: styleID) {
            $0.sourceIdentifier = styleID.uuidString
            $0.name = "Heading"
            $0.kind = "paragraph"
            $0.project = project
        }
        let runID = UUID()
        _ = store.importRuns.create(id: runID) {
            $0.sourceURL = "/tmp/source"
            $0.sourceFingerprint = "fingerprint"
            $0.startedAt = now
            $0.status = "succeeded"
            $0.insertedCount = 1
            $0.updatedCount = 0
            $0.warningCount = 0
            $0.project = project
        }
        let provenanceID = UUID()
        _ = store.provenanceEvents.create(id: provenanceID) {
            $0.eventType = "created"
            $0.agent = ProvenanceAgent.human.rawValue
            $0.timestamp = now
            $0.project = project
        }
        try store.save()

        XCTAssertEqual(try store.projects.require(id: projectID).title, "Project")
        XCTAssertEqual(try store.documents.require(id: documentID).title, "Document")
        XCTAssertNotNil(try store.resources.fetch(id: resourceID))
        XCTAssertNotNil(try store.metadataFields.fetch(id: fieldID))
        XCTAssertNotNil(try store.metadataValues.fetch(id: valueID))
        XCTAssertNotNil(try store.semanticEntities.fetch(id: entityID))
        XCTAssertNotNil(try store.entityAliases.fetch(id: aliasID))
        XCTAssertNotNil(try store.mentions.fetch(id: mentionID))
        XCTAssertNotNil(try store.annotations.fetch(id: annotationID))
        XCTAssertNotNil(try store.revisions.fetch(id: revisionID))
        XCTAssertNotNil(try store.links.fetch(id: linkID))
        XCTAssertNotNil(try store.styles.fetch(id: styleID))
        XCTAssertNotNil(try store.importRuns.fetch(id: runID))
        XCTAssertNotNil(try store.provenanceEvents.fetch(id: provenanceID))

        try store.documents.update(id: documentID) { $0.title = "Updated" }
        try store.semanticEntities.update(id: entityID) { $0.summary = "Protagonist" }
        try store.save()
        XCTAssertEqual(try store.documents.require(id: documentID).title, "Updated")
        XCTAssertEqual(try store.semanticEntities.require(id: entityID).summary, "Protagonist")

        try store.entityAliases.delete(id: aliasID)
        try store.mentions.delete(id: mentionID)
        try store.annotations.delete(id: annotationID)
        try store.revisions.delete(id: revisionID)
        try store.links.delete(id: linkID)
        try store.metadataValues.delete(id: valueID)
        try store.resources.delete(id: resourceID)
        try store.styles.delete(id: styleID)
        try store.importRuns.delete(id: runID)
        try store.provenanceEvents.delete(id: provenanceID)
        try store.metadataFields.delete(id: fieldID)
        try store.semanticEntities.delete(id: entityID)
        try store.documents.delete(id: documentID)
        try store.projects.delete(id: projectID)
        try store.save()
        XCTAssertEqual(try store.projects.count(), 0)
        XCTAssertEqual(try store.documents.count(), 0)
    }
}
