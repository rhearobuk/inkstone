import AuthorData
import XCTest
@testable import AuthorUI

@MainActor
final class WorkspaceControllerTests: XCTestCase {
    func testCreatesStarterProjectWithWorkspaceRootsAndNarrative() throws {
        let controller = try makeController()

        let project = try controller.createProject(title: "The Long Road", author: "Ada")

        XCTAssertEqual(project.title, "The Long Road")
        XCTAssertEqual(project.author, "Ada")
        XCTAssertEqual(controller.binderItems.map(\.title), [
            "Project Definition", "Story Bible", "Gallery", "Narrative", "Trash"
        ])
        XCTAssertEqual(project.documents.count, 3)
        XCTAssertEqual(
            project.documents.first(where: { $0.title == "Narrative" })?
                .orderedChildren.first?.title,
            "Untitled Novel"
        )
    }

    func testPinsAndUnpinsProjectsBeforeUnpinnedProjects() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let first = try controller.createProject(title: "First")
        _ = try controller.createProject(title: "Second")

        controller.setProjectPinned(first.id, pinned: true)

        XCTAssertEqual(controller.projects.first?.id, first.id)
        XCTAssertTrue(controller.isProjectPinned(first.id))
        controller.setProjectPinned(first.id, pinned: false)
        XCTAssertFalse(controller.isProjectPinned(first.id))
    }

    func testHidesAndRestoresProjects() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "Hidden")

        controller.setProjectHidden(project.id, hidden: true)

        XCTAssertTrue(controller.projects.isEmpty)
        XCTAssertTrue(controller.isProjectHidden(project.id))
        controller.showsHiddenProjects = true
        controller.refresh()
        XCTAssertEqual(controller.projects.map(\.id), [project.id])
        controller.setProjectHidden(project.id, hidden: false)
        XCTAssertFalse(controller.isProjectHidden(project.id))
    }

    func testSoftDeletesAndRestoresProjects() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "Trash Project")
        let projectID = project.id

        // Soft delete moves to trash
        controller.trashProject(projectID)
        XCTAssertTrue(controller.isProjectTrashed(projectID))
        XCTAssertTrue(controller.projects.isEmpty)
        XCTAssertEqual(controller.trashedProjects.map(\.id), [projectID])

        // When showsTrashedProjects is enabled, it appears
        controller.showsTrashedProjects = true
        controller.refresh()
        XCTAssertEqual(controller.projects.map(\.id), [projectID])

        // Restore project
        controller.restoreProject(projectID)
        XCTAssertFalse(controller.isProjectTrashed(projectID))
        controller.showsTrashedProjects = false
        controller.refresh()
        XCTAssertEqual(controller.projects.map(\.id), [projectID])
    }

    func testPermanentlyDeletesProjectAndItsDocuments() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Delete Me")
        let projectID = project.id

        try controller.deleteProjectPermanently(projectID)

        XCTAssertNil(try controller.store.projects.fetch(id: projectID))
        XCTAssertEqual(try controller.store.documents.count(), 0)
        XCTAssertTrue(controller.projects.isEmpty)
    }

    func testEmptyProjectTrashPermanentlyDeletesAllTrashedProjects() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let active = try controller.createProject(title: "Active")
        let trashed1 = try controller.createProject(title: "Trash 1")
        let trashed2 = try controller.createProject(title: "Trash 2")
        let trashed1ID = trashed1.id
        let trashed2ID = trashed2.id

        controller.trashProject(trashed1ID)
        controller.trashProject(trashed2ID)

        XCTAssertEqual(controller.trashedProjects.count, 2)
        try controller.emptyProjectTrash()

        XCTAssertEqual(controller.trashedProjects.count, 0)
        XCTAssertEqual(controller.projects.map(\.id), [active.id])
        XCTAssertNil(try controller.store.projects.fetch(id: trashed1ID))
        XCTAssertNil(try controller.store.projects.fetch(id: trashed2ID))
        XCTAssertNotNil(try controller.store.projects.fetch(id: active.id))
    }

    func testSoftDeletesAndRestoresSceneToExactLocation() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "Novel")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)

        _ = try XCTUnwrap(script.orderedChildren.first) // Opening Scene (order 0)
        let scene2 = try controller.addDocument(title: "Scene Two", kind: .text, parentID: script.id)
        _ = try controller.addDocument(title: "Scene Three", kind: .text, parentID: script.id)

        XCTAssertEqual(script.orderedChildren.map(\.title), ["Opening Scene", "Scene Two", "Scene Three"])

        // Soft delete scene2
        controller.trashDocument(scene2.id)
        XCTAssertTrue(controller.isDocumentTrashed(scene2.id))
        XCTAssertEqual(controller.trashedDocuments(in: project).map(\.id), [scene2.id])

        // Binder items for narrative should now only show scene1 and scene3
        let narrativeItem = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        let novelItem = try XCTUnwrap(narrativeItem.children?.first)
        XCTAssertEqual(novelItem.children?.map(\.title), ["Opening Scene", "Scene Three"])

        // Trash binder item should show scene2
        let trashItem = try XCTUnwrap(controller.binderItems.first { $0.kind == .trash })
        XCTAssertEqual(trashItem.title, "Trash (1)")
        XCTAssertEqual(trashItem.children?.map(\.title), ["Scene Two"])

        // Restore scene2 -> it must return to its EXACT location (between Scene 1 and Scene 3)
        controller.restoreDocument(scene2.id)
        XCTAssertFalse(controller.isDocumentTrashed(scene2.id))
        XCTAssertEqual(controller.trashedDocuments(in: project).count, 0)

        controller.refresh()
        let refreshedNarrative = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        let refreshedNovel = try XCTUnwrap(refreshedNarrative.children?.first)
        XCTAssertEqual(refreshedNovel.children?.map(\.title), ["Opening Scene", "Scene Two", "Scene Three"])
    }

    func testHidesAndShowsScenesInBinder() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "Novel")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)

        _ = try XCTUnwrap(script.orderedChildren.first)
        let scene2 = try controller.addDocument(title: "Scene Two", kind: .text, parentID: script.id)

        controller.setDocumentHidden(scene2.id, hidden: true)
        XCTAssertTrue(controller.isDocumentHidden(scene2.id))

        // When showsHiddenDocuments is false, scene2 is omitted from binder
        let narrativeItem = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        let novelItem = try XCTUnwrap(narrativeItem.children?.first)
        XCTAssertEqual(novelItem.children?.map(\.title), ["Opening Scene"])

        // When showsHiddenDocuments is true, scene2 appears with isHidden = true
        controller.showsHiddenDocuments = true
        controller.refresh()
        let visibleNarrative = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        let visibleNovel = try XCTUnwrap(visibleNarrative.children?.first)
        XCTAssertEqual(visibleNovel.children?.map(\.title), ["Opening Scene", "Scene Two"])
        XCTAssertEqual(visibleNovel.children?.last?.isHidden, true)

        controller.setDocumentHidden(scene2.id, hidden: false)
        XCTAssertFalse(controller.isDocumentHidden(scene2.id))
    }

    func testEmptyDocumentTrashPermanentlyRemovesTrashedDocuments() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "Novel")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)

        let scene1 = try XCTUnwrap(script.orderedChildren.first)
        let scene2 = try controller.addDocument(title: "Scene Two", kind: .text, parentID: script.id)
        let scene1ID = scene1.id
        let scene2ID = scene2.id

        controller.trashDocument(scene2ID)
        XCTAssertEqual(controller.trashedDocuments(in: project).count, 1)

        try controller.emptyTrash(for: project.id)

        XCTAssertEqual(controller.trashedDocuments(in: project).count, 0)
        XCTAssertNil(try controller.store.documents.fetch(id: scene2ID))
        XCTAssertNotNil(try controller.store.documents.fetch(id: scene1ID))
    }

    func testPermanentlyDeletesDocument() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        let sceneID = scene.id

        try controller.deleteDocumentPermanently(sceneID)

        XCTAssertNil(try controller.store.documents.fetch(id: sceneID))
    }

    func testGroupsStoryBibleEntriesUsingContractOntology() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")

        let character = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        let artifact = try controller.addStoryBibleEntry(named: "The Key", category: .artifacts)

        XCTAssertEqual(character.kind, SemanticEntityKind.character.rawValue)
        XCTAssertEqual(artifact.kind, SemanticEntityKind.object.rawValue)
        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let people = try XCTUnwrap(storyBible.children?.first { $0.title == "People" })
        let artifacts = try XCTUnwrap(storyBible.children?.first { $0.title == "Artifacts" })
        XCTAssertEqual(people.children?.map(\.title), ["Mara"])
        XCTAssertEqual(artifacts.children?.map(\.title), ["The Key"])
    }

    func testMovesDocumentIntoFolderAndRejectsHierarchyCycle() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Binder")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(script.orderedChildren.first)
        controller.selection = .document(script.id)
        let chapter = try controller.addDocument(
            title: "Chapter One",
            kind: .folder,
            parentID: script.id
        )

        try controller.moveDocument(scene.id, onto: chapter.id)

        XCTAssertEqual(scene.parent?.id, chapter.id)
        XCTAssertThrowsError(try controller.moveDocument(script.id, onto: scene.id)) { error in
            XCTAssertEqual(error.localizedDescription, WorkspaceError.invalidMove.localizedDescription)
        }
    }

    func testUpdatesDocumentTextThroughPersistenceContract() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        controller.selection = .document(scene.id)

        controller.updateDocument(
            title: "Arrival",
            synopsis: "The protagonist arrives.",
            plainText: "Rain covered the station."
        )

        let persisted = try controller.store.documents.require(id: scene.id)
        XCTAssertEqual(persisted.title, "Arrival")
        XCTAssertEqual(persisted.synopsis, "The protagonist arrives.")
        XCTAssertEqual(persisted.plainText, "Rain covered the station.")
    }

    func testWordCountRollsUpIncrementallyThroughAncestorsOnTextEdit() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(book.orderedChildren.first)
        controller.selection = .document(scene.id)

        controller.updateDocument(title: scene.title, synopsis: nil, plainText: "one two three four five")

        XCTAssertEqual(scene.ownWordCount, 5)
        XCTAssertEqual(scene.actualWordCount, 5)
        XCTAssertEqual(book.actualWordCount, 5)
        XCTAssertEqual(narrative.actualWordCount, 5)

        controller.updateDocument(title: scene.title, synopsis: nil, plainText: "one two")

        XCTAssertEqual(scene.actualWordCount, 2)
        XCTAssertEqual(book.actualWordCount, 2)
        XCTAssertEqual(narrative.actualWordCount, 2)
    }

    func testWordCountRollupMovesWithDocumentAndIsRemovedOnPermanentDelete() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(book.orderedChildren.first)
        controller.selection = .document(scene.id)
        controller.updateDocument(title: scene.title, synopsis: nil, plainText: "alpha beta gamma")
        let otherChapter = try controller.addDocument(title: "Chapter Two", kind: .folder, parentID: book.id)

        try controller.moveDocument(scene.id, onto: otherChapter.id)

        XCTAssertEqual(otherChapter.actualWordCount, 3)
        XCTAssertEqual(book.actualWordCount, 3)

        try controller.deleteDocumentPermanently(scene.id)

        XCTAssertEqual(otherChapter.actualWordCount, 0)
        XCTAssertEqual(book.actualWordCount, 0)
    }

    func testChapterNumbersAreComputedFromTreePosition() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        controller.setNarrativeType(book, to: .book)
        let existingScene = try XCTUnwrap(book.orderedChildren.first)
        let chapterOne = try controller.addDocument(title: "Chapter One", kind: .folder, parentID: book.id)
        controller.setNarrativeType(chapterOne, to: .chapter)
        try controller.moveDocument(existingScene.id, onto: chapterOne.id)
        let chapterTwo = try controller.addDocument(title: "Chapter Two", kind: .folder, parentID: book.id)
        controller.setNarrativeType(chapterTwo, to: .chapter)

        XCTAssertEqual(controller.computedNarrativeNumber(for: chapterOne), 1)
        XCTAssertEqual(controller.computedNarrativeNumber(for: chapterTwo), 2)
    }

    func testBinderIconFollowsNarrativeType() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)

        func icon(for documentID: UUID) throws -> String {
            let narrativeItem = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
            let item = try XCTUnwrap(narrativeItem.children?.first { $0.documentID == documentID })
            return item.systemImage
        }

        XCTAssertEqual(try icon(for: book.id), "folder")

        controller.setNarrativeType(book, to: .book)
        XCTAssertEqual(try icon(for: book.id), "book.closed")

        controller.setNarrativeType(book, to: .chapter)
        XCTAssertEqual(try icon(for: book.id), "doc.on.doc")

        controller.setNarrativeType(book, to: nil)
        XCTAssertEqual(try icon(for: book.id), "folder")
    }

    func testDoNotPublishIsInheritedFromAncestorsWithoutOverwritingChildValue() throws {        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(book.orderedChildren.first)

        XCTAssertFalse(scene.isPublishingExcluded)

        controller.setDoNotPublish(book, true)

        XCTAssertTrue(scene.isPublishingExcluded)
        XCTAssertNotNil(scene.inheritedPublishingExclusionSource)
        XCTAssertEqual(scene.inheritedPublishingExclusionSource?.id, book.id)

        controller.setDoNotPublish(book, false)

        XCTAssertFalse(scene.isPublishingExcluded)
    }

    func testNarrativeMetadataFieldsPersistPerDocumentType() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        controller.setNarrativeType(book, to: .book)

        let isbnField = try XCTUnwrap(
            NarrativeMetadataSchema.fields(for: .book).first { $0.key == "system.book.isbn" }
        )
        controller.setNarrativeFieldValue("978-0-000-00000-0", for: isbnField, on: book)

        XCTAssertEqual(controller.narrativeFieldValue(isbnField, on: book), "978-0-000-00000-0")

        let targetField = try XCTUnwrap(
            NarrativeMetadataSchema.fields(for: .book).first { $0.key == NarrativeMetadataSchema.targetWordCountKey }
        )
        controller.setNarrativeFieldValue("80000", for: targetField, on: book)
        XCTAssertEqual(controller.narrativeFieldValue(targetField, on: book), "80000")
    }

    func testAddsAndDeletesNativeGalleryImageForStoryBibleEntry() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")
        let place = try controller.addStoryBibleEntry(named: "Moon Harbor", category: .places)
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let item = try XCTUnwrap(
            controller.addGalleryImages(from: [imageURL], relatedTo: place).first
        )

        XCTAssertEqual(item.semanticEntity?.id, place.id)
        XCTAssertEqual(item.resource.data, imageData)
        XCTAssertEqual(item.resource.role, "galleryImage")
        XCTAssertTrue(place.galleryItems.contains(item))
        XCTAssertEqual(controller.galleryItems.count, 1)

        controller.deleteGalleryItem(item)

        XCTAssertEqual(try controller.store.galleryItems.count(), 0)
        XCTAssertEqual(try controller.store.resources.count(), 0)
        XCTAssertEqual(controller.selection, .semanticEntity(place.id))
    }

    func testResolvesScrivPackageAndScrivxSource() throws {
        let controller = try makeController()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).scriv", isDirectory: true)
        let filesURL = packageURL.appendingPathComponent("Files", isDirectory: true)
        let scrivxURL = packageURL.appendingPathComponent("Novel.scrivx")
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        try Data("<ScrivenerProject/>".utf8).write(to: scrivxURL)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let packageSource = try controller.scrivenerSource(from: packageURL)
        XCTAssertEqual(packageSource.xml.standardizedFileURL, scrivxURL.standardizedFileURL)
        XCTAssertEqual(packageSource.files.standardizedFileURL, filesURL.standardizedFileURL)

        let fileSource = try controller.scrivenerSource(from: scrivxURL)
        XCTAssertEqual(fileSource.xml.standardizedFileURL, scrivxURL.standardizedFileURL)
        XCTAssertEqual(fileSource.files.standardizedFileURL, filesURL.standardizedFileURL)
    }

    func testSeparatesImportedStoryBibleRootsFromNarrative() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Imported")
        let existing = Array(project.documents)
        for document in existing {
            controller.store.context.delete(document)
        }
        let characters = controller.store.documents.create {
            $0.sourceIdentifier = "characters"
            $0.title = "Characters"
            $0.kind = DocumentKind.folder.rawValue
            $0.orderIndex = 1
            $0.project = project
        }
        controller.store.documents.create {
            $0.sourceIdentifier = "character"
            $0.title = "Mara"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 0
            $0.project = project
            $0.parent = characters
        }
        controller.store.documents.create {
            $0.sourceIdentifier = "draft"
            $0.title = "Novel"
            $0.kind = DocumentKind.draftFolder.rawValue
            $0.orderIndex = 0
            $0.project = project
        }
        try controller.store.save()
        controller.refresh()

        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let people = try XCTUnwrap(storyBible.children?.first { $0.title == "People" })
        let narrative = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        XCTAssertEqual(people.children?.map(\.title), ["Characters"])
        XCTAssertEqual(narrative.children?.map(\.title), ["Novel"])
    }

    func testRearrangeNarrativeScenesBeforeAndAfter() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Narrative Flow")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)

        let scene1 = try XCTUnwrap(script.orderedChildren.first) // "Opening Scene"
        let scene2 = try controller.addDocument(title: "Middle Scene", kind: .text, parentID: script.id)
        let scene3 = try controller.addDocument(title: "Climax Scene", kind: .text, parentID: script.id)
        let scene4 = try controller.addDocument(title: "Ending Scene", kind: .text, parentID: script.id)

        XCTAssertEqual(
            script.orderedChildren.map(\.title),
            ["Opening Scene", "Middle Scene", "Climax Scene", "Ending Scene"]
        )

        // Move scene4 BEFORE scene2: [Opening Scene, Ending Scene, Middle Scene, Climax Scene]
        try controller.moveDocument(scene4.id, relativeTo: scene2.id, position: .before)
        XCTAssertEqual(
            script.orderedChildren.map(\.title),
            ["Opening Scene", "Ending Scene", "Middle Scene", "Climax Scene"]
        )

        // Move scene1 AFTER scene3 (to the end): [Ending Scene, Middle Scene, Climax Scene, Opening Scene]
        try controller.moveDocument(scene1.id, relativeTo: scene3.id, position: .after)
        XCTAssertEqual(
            script.orderedChildren.map(\.title),
            ["Ending Scene", "Middle Scene", "Climax Scene", "Opening Scene"]
        )

        // Move scene3 BEFORE scene1: [Ending Scene, Middle Scene, Scene3, Opening Scene] -> same order
        // Move scene3 BEFORE scene2: [Ending Scene, Climax Scene, Middle Scene, Opening Scene]
        try controller.moveDocument(scene3.id, relativeTo: scene2.id, position: .before)
        XCTAssertEqual(
            script.orderedChildren.map(\.title),
            ["Ending Scene", "Climax Scene", "Middle Scene", "Opening Scene"]
        )
    }

    func testMoveScenesBetweenNarrativeChapters() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Multi Chapter")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)

        let chapter1 = try controller.addDocument(title: "Chapter 1", kind: .folder, parentID: script.id)
        let chapter2 = try controller.addDocument(title: "Chapter 2", kind: .folder, parentID: script.id)

        let c1Scene1 = try controller.addDocument(title: "Ch1 Scene 1", kind: .text, parentID: chapter1.id)
        let c1Scene2 = try controller.addDocument(title: "Ch1 Scene 2", kind: .text, parentID: chapter1.id)
        let c2Scene1 = try controller.addDocument(title: "Ch2 Scene 1", kind: .text, parentID: chapter2.id)

        // Move c1Scene2 into chapter 2 at end
        try controller.moveDocument(c1Scene2.id, relativeTo: chapter2.id, position: .inside)
        XCTAssertEqual(chapter1.orderedChildren.map(\.title), ["Ch1 Scene 1"])
        XCTAssertEqual(chapter2.orderedChildren.map(\.title), ["Ch2 Scene 1", "Ch1 Scene 2"])

        // Move c1Scene1 before c2Scene1 in chapter 2
        try controller.moveDocument(c1Scene1.id, relativeTo: c2Scene1.id, position: .before)
        XCTAssertEqual(chapter1.orderedChildren.map(\.title), [])
        XCTAssertEqual(chapter2.orderedChildren.map(\.title), ["Ch1 Scene 1", "Ch2 Scene 1", "Ch1 Scene 2"])
    }

    func testMoveSceneToNarrativeRoot() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Root Test")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(script.orderedChildren.first)

        let narrativeBinderItem = try XCTUnwrap(controller.binderItems.first { $0.title == "Narrative" })
        XCTAssertEqual(narrativeBinderItem.documentID, narrative.id)
        XCTAssertTrue(narrativeBinderItem.isContainer)

        // Drop scene onto Narrative folder
        try controller.moveDocument(scene.id, relativeTo: narrative.id, position: .inside)
        XCTAssertEqual(scene.parent?.id, narrative.id)
    }

    func testRichTextUpdateCreatesRTFResourceForNativeTextDocument() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Rich Text")
        let scene = try XCTUnwrap(project.documents.first { $0.kind == DocumentKind.text.rawValue })
        controller.selection = .document(scene.id)

        let data = Data(#"{\rtf1\ansi Hello}"#.utf8)
        controller.updateDocumentRichText(rtfData: data, plainText: "Hello")

        let resource = try XCTUnwrap(scene.resources.first {
            $0.role == "content" && $0.mediaType == "application/rtf"
        })
        XCTAssertEqual(scene.plainText, "Hello")
        XCTAssertEqual(resource.data, data)
        XCTAssertEqual(resource.textContent, "Hello")
        XCTAssertEqual(resource.byteCount, Int64(data.count))
        XCTAssertEqual(resource.document?.id, scene.id)
        XCTAssertEqual(resource.project.id, project.id)
        XCTAssertFalse(resource.isSourcePreserved)
    }

    private func makeController() throws -> WorkspaceController {
        WorkspaceController(store: try AuthorDataStore(inMemory: true))
    }
}
