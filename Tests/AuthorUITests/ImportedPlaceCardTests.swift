import AuthorData
import XCTest
@testable import AuthorUI

@MainActor
final class ImportedPlaceCardTests: XCTestCase {
    func testImportedPlaceKeepsTextAndSourceResourcesAndOpensAsCard() throws {
        let (original, source) = try fixture()
        let text = try XCTUnwrap(source.plainText)
        let bytes = Data("{\\rtf1 Original place resource.}".utf8)
        let resource = original.store.resources.create {
            $0.sourcePath = "Files/Data/\(source.id)/content.rtf"
            $0.role = "content"
            $0.mediaType = "application/rtf"
            $0.byteCount = Int64(bytes.count)
            $0.sha256 = "fixture"
            $0.data = bytes
            $0.isSourcePreserved = true
            $0.project = source.project
            $0.document = source
        }
        try original.store.save()
        let controller = WorkspaceController(store: original.store)
        let card = try XCTUnwrap(controller.importedPlaceCard(for: source))
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(card.details, text)
        XCTAssertEqual(card.semanticEntity.kind, SemanticEntityKind.location.rawValue)
        XCTAssertEqual(card.semanticEntity.canonicalName, source.title)
        XCTAssertEqual(resource.data, bytes)
        XCTAssertTrue(resource.isSourcePreserved)
        XCTAssertEqual(source.plainText, text)
        XCTAssertEqual(controller.importedPlaceSource(for: card.semanticEntity)?.id, source.id)

        let entries = flatten(controller.binderItems).filter { $0.documentID == source.id }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.selection, .storyBibleCard(card.id))
        XCTAssertEqual(entries.first?.storyBibleCategory, .places)
        controller.selection = .document(source.id)
        XCTAssertEqual(controller.selectedStoryBibleCard?.id, card.id)

        let person = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        XCTAssertEqual(controller.storyBibleRelationshipTargets(from: person, category: .places).map(\.id), [card.semanticEntity.id])
        try controller.addStoryBibleRelationship(kind: "visits", notes: nil, from: person, to: card.semanticEntity)
        let board = try controller.createMurderBoard()
        var state = MurderBoardState()
        state.focusCategory = .people
        state.selectedEntityID = person.id
        state.destinationCategories = [.places]
        XCTAssertEqual(controller.murderBoardGraph(for: board, state: state).edges.map(\.relationship.sentence), ["Mara visits Moon Gate"])
    }

    func testNormalizationIsIdempotentAndNeverMergesByNameOrOverwritesCardEdits() throws {
        let (controller, source) = try fixture()
        let duplicate = importedDocument("Moon Gate", project: source.project, parent: source.parent, store: controller.store)
        duplicate.plainText = "A different place with the same name."
        let native = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)
        let nativeDocument = importedDocument("Native Note", project: source.project, parent: source.parent, store: controller.store)
        nativeDocument.sourceIdentifier = "native.document.\(nativeDocument.id)"
        let templates = importedDocument("Templates", project: source.project, parent: nil, store: controller.store, kind: .folder)
        let placesTemplate = importedDocument("Places", project: source.project, parent: templates, store: controller.store)
        try controller.store.save()
        try controller.normalizeImportedPlaceCards()
        let card = try XCTUnwrap(controller.importedPlaceCard(for: source))
        let duplicateCard = try XCTUnwrap(controller.importedPlaceCard(for: duplicate))
        XCTAssertNotEqual(card.semanticEntity.id, duplicateCard.semanticEntity.id)
        XCTAssertNotEqual(card.semanticEntity.id, native.id)
        XCTAssertNil(controller.importedPlaceCard(for: nativeDocument))
        XCTAssertNil(controller.importedPlaceCard(for: placesTemplate))
        XCTAssertNil(source.parent.flatMap { controller.importedPlaceCard(for: $0) })

        card.details = "My revised description.\n"
        card.semanticEntity.canonicalName = "The Moon Gate"
        controller.saveStoryBibleCard(card)
        source.plainText = "Changed source text from a later import."
        try controller.store.save()
        let reopened = WorkspaceController(store: controller.store)
        XCTAssertEqual(reopened.importedPlaceCard(for: source)?.id, card.id)
        XCTAssertEqual(card.details, "My revised description.\n")
        XCTAssertEqual(card.semanticEntity.canonicalName, "The Moon Gate")
        XCTAssertEqual(source.project.semanticEntities.count, 3)
        XCTAssertEqual(flatten(reopened.binderItems).first { $0.documentID == source.id }?.title, "The Moon Gate")
    }

    func testTrashRestoreAndPermanentDeleteKeepPlaceRelationshipsConsistent() throws {
        let (controller, source) = try fixture()
        try controller.normalizeImportedPlaceCards()
        let card = try XCTUnwrap(controller.importedPlaceCard(for: source))
        let entityID = card.semanticEntity.id
        let person = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        try controller.addStoryBibleRelationship(kind: "visits", notes: nil, from: person, to: card.semanticEntity)
        controller.trashDocument(source.id)
        XCTAssertTrue(controller.storyBibleRelationshipTargets(from: person, category: .places).isEmpty)
        controller.restoreDocument(source.id)
        XCTAssertEqual(controller.selectedStoryBibleCard?.id, card.id)
        XCTAssertEqual(controller.storyBibleRelationshipTargets(from: person, category: .places).count, 1)
        controller.selection = .storyBibleCard(card.id)
        try controller.deleteDocumentPermanently(source.id)
        XCTAssertNil(try controller.store.semanticEntities.fetch(id: entityID))
        XCTAssertTrue(person.outgoingStoryBibleRelationships.isEmpty)
        XCTAssertNil(controller.selectedStoryBibleCard)
    }

    func testImportAndReimportCreateOnePlaceCardWithoutOverwritingDescription() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PlaceImport-\(UUID())")
        let projectID = UUID()
        let folderID = UUID()
        let placeID = UUID()
        let dataFolder = root.appendingPathComponent("Files/Data/\(placeID.uuidString)")
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let xml = root.appendingPathComponent("Places.scrivx")
        try """
        <ScrivenerProject Identifier="\(projectID)" Version="2.0">
          <Binder><BinderItem UUID="\(folderID)" Type="Folder"><Title>Places</Title><Children>
            <BinderItem UUID="\(placeID)" Type="Text"><Title>Moon Gate</Title></BinderItem>
          </Children></BinderItem></Binder>
        </ScrivenerProject>
        """.write(to: xml, atomically: true, encoding: .utf8)
        let content = dataFolder.appendingPathComponent("content.rtf")
        try "{\\rtf1\\ansi Original place description.}".write(to: content, atomically: true, encoding: .utf8)
        let controller = WorkspaceController(store: try AuthorDataStore(inMemory: true))
        let project = try controller.createProject(title: "Import", createStarterContent: false)
        _ = try controller.importScrivenerProject(from: xml, destination: .existing(project.id))
        let source = try XCTUnwrap(project.documents.first { $0.title == "Moon Gate" })
        let card = try XCTUnwrap(controller.importedPlaceCard(for: source))
        let cardID = card.id
        XCTAssertEqual(card.details, source.plainText)
        XCTAssertTrue(card.details?.contains("Original place description.") == true)
        card.details = "Author-edited description."
        controller.saveStoryBibleCard(card)
        try "{\\rtf1\\ansi Updated source description.}".write(to: content, atomically: true, encoding: .utf8)
        _ = try controller.importScrivenerProject(from: xml, destination: .existing(project.id))
        XCTAssertEqual(controller.importedPlaceCard(for: source)?.id, cardID)
        XCTAssertEqual(card.details, "Author-edited description.")
        XCTAssertTrue(source.plainText?.contains("Updated source description.") == true)
        XCTAssertEqual(project.semanticEntities.filter { $0.kind == "location" }.count, 1)
    }

    func testInvalidPlaceMappingIsReportedWithoutReplacingSourceOrCard() throws {
        let (controller, source) = try fixture()
        try controller.normalizeImportedPlaceCards()
        let originalText = source.plainText
        let originalCard = try XCTUnwrap(controller.importedPlaceCard(for: source))
        let link = try XCTUnwrap(source.metadataValues.first { $0.field.key == "system.storyBible.importedPlaceEntityID" })
        link.stringValue = "invalid"
        try controller.store.save()
        let reopened = WorkspaceController(store: controller.store)
        XCTAssertTrue(reopened.lastError?.contains("saved Story Bible link") == true)
        XCTAssertEqual(source.plainText, originalText)
        XCTAssertFalse(originalCard.isDeleted)
        XCTAssertEqual(source.project.semanticEntities.count, 1)
    }

    private func fixture() throws -> (WorkspaceController, Document) {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ImportedPlaceCardTests.\(UUID())"))
        let controller = WorkspaceController(store: try AuthorDataStore(inMemory: true), projectListPreferences: preferences)
        let project = try controller.createProject(title: "Imported Places")
        let folder = importedDocument("Places", project: project, parent: nil, store: controller.store, kind: .folder)
        let source = importedDocument("Moon Gate", project: project, parent: folder, store: controller.store)
        source.plainText = "  A silver arch.\nA second paragraph with a trailing space. \n"
        source.synopsis = "The gate at the city boundary."
        try controller.store.save()
        return (controller, source)
    }

    private func importedDocument(
        _ title: String, project: WritingProject, parent: Document?, store: AuthorDataStore, kind: DocumentKind = .text
    ) -> Document {
        store.documents.create {
            $0.sourceIdentifier = $0.id.uuidString
            $0.title = title
            $0.kind = kind.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.parent = parent
        }
    }

    private func flatten(_ items: [BinderItem]) -> [BinderItem] {
        items.flatMap { [$0] + flatten($0.children ?? []) }
    }
}
