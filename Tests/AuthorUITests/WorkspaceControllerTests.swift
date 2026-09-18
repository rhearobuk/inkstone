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
        let narrative = try XCTUnwrap(project.documents.first(where: { $0.title == "Narrative" }))
        let novel = try XCTUnwrap(narrative.orderedChildren.first)
        XCTAssertEqual(novel.title, "Untitled Novel")
        XCTAssertEqual(novel.narrativeType, NarrativeType.book.rawValue)
    }

    func testMigratesExistingNativeScriptToBook() throws {
        let store = try AuthorDataStore(inMemory: true)
        let controller = WorkspaceController(store: store)
        let project = try controller.createProject(title: "The Long Road")
        let narrative = try XCTUnwrap(project.documents.first(where: { $0.title == "Narrative" }))
        let novel = try XCTUnwrap(narrative.orderedChildren.first)
        novel.narrativeType = nil
        try store.save()

        _ = WorkspaceController(store: store)

        XCTAssertEqual(novel.narrativeType, NarrativeType.book.rawValue)
    }

    func testAddsResearchDocumentToResearchCategory() throws {
        let controller = try makeController()
        _ = try controller.createProject(title: "Research")

        let document = try controller.addResearchDocument(title: "Sources")

        XCTAssertEqual(document.kind, DocumentKind.folder.rawValue)
        XCTAssertEqual(document.sectionTypeIdentifier, "storyBible.research")
        XCTAssertEqual(controller.storyBibleCategory(for: document), .research)
        XCTAssertEqual(controller.storyBibleDocuments(in: .research).map(\.id), [document.id])
        XCTAssertFalse(controller.storyBibleDocuments(in: .worldbuilding).contains { $0.id == document.id })
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
        let organization = try controller.addStoryBibleEntry(
            named: "The Guild",
            category: .organizations
        )
        let artifact = try controller.addStoryBibleEntry(named: "The Key", category: .artifacts)

        XCTAssertEqual(character.kind, SemanticEntityKind.character.rawValue)
        XCTAssertEqual(organization.kind, SemanticEntityKind.organization.rawValue)
        XCTAssertEqual(artifact.kind, SemanticEntityKind.object.rawValue)
        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let people = try XCTUnwrap(storyBible.children?.first { $0.title == "People" })
        let organizations = try XCTUnwrap(storyBible.children?.first { $0.title == "Organizations" })
        let artifacts = try XCTUnwrap(storyBible.children?.first { $0.title == "Artifacts" })
        XCTAssertEqual(people.children?.map(\.title), ["Mara"])
        XCTAssertEqual(organizations.children?.map(\.title), ["The Guild"])
        XCTAssertEqual(artifacts.children?.map(\.title), ["The Key"])
    }

    func testStoryBibleCardsPersistTypedCharacterLinksAndNotes() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")
        let character = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        let place = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)
        let card = try XCTUnwrap(place.storyBibleCard)
        let profile = try XCTUnwrap(character.characterProfile)

        card.details = "A silver arch at the city edge."
        card.streetAddress = "1 Moon Gate Way\nLume, LX 10001"
        card.gpsCoordinates = "51.5074, -0.1278"
        controller.setCharacters([profile], for: card, relationship: .place)
        try controller.addStoryBibleNote(title: "Continuity", body: "It only opens at dawn.", to: card)

        let persisted = try controller.store.storyBibleCards.require(id: card.id)
        XCTAssertEqual(persisted.details, "A silver arch at the city edge.")
        XCTAssertEqual(persisted.relatedCharacters.map(\.id), [profile.id])
        XCTAssertEqual(persisted.notes.first?.body, "It only opens at dawn.")
    }

    func testSceneSaveAutoCreatesStoryBibleEntitiesAndMentions() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "Mara Venn met The Lantern Society beneath Moon Gate."
        )
        controller.flushPendingChanges()

        let entities = project.semanticEntities
        XCTAssertEqual(Set(entities.map(\.canonicalName)), ["Mara Venn", "The Lantern Society", "Moon Gate"])
        XCTAssertEqual(project.semanticEntities.first { $0.canonicalName == "Mara Venn" }?.kind, SemanticEntityKind.character.rawValue)
        XCTAssertNotNil(project.semanticEntities.first { $0.canonicalName == "Mara Venn" }?.storyBibleCard)
        XCTAssertNotNil(project.semanticEntities.first { $0.canonicalName == "Mara Venn" }?.characterProfile)
        XCTAssertEqual(project.semanticEntities.first { $0.canonicalName == "The Lantern Society" }?.kind, SemanticEntityKind.organization.rawValue)
        XCTAssertEqual(project.semanticEntities.first { $0.canonicalName == "Moon Gate" }?.kind, SemanticEntityKind.location.rawValue)
        XCTAssertEqual(scene.mentions.count, 3)

        controller.refreshSceneEntityLinks(for: scene.id)

        XCTAssertEqual(project.semanticEntities.count, 3)
        XCTAssertEqual(scene.mentions.count, 3)
    }

    func testLinkedScenesReturnsSceneBacklinksForStoryBibleEntry() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "Mara Venn met The Lantern Society beneath Moon Gate."
        )
        controller.flushPendingChanges()

        let entity = try XCTUnwrap(project.semanticEntities.first { $0.canonicalName == "Moon Gate" })
        let linkedScenes = controller.linkedScenes(for: entity)

        XCTAssertEqual(linkedScenes.map(\.documentTitle), [scene.title])
        XCTAssertEqual(linkedScenes.first?.mentionCount, 1)
        XCTAssertEqual(linkedScenes.first?.matchedTexts, ["Moon Gate"])
    }

    func testSceneSaveReusesExistingAliasInsteadOfCreatingDuplicateEntity() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })
        let entity = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)
        controller.selection = .document(scene.id)

        let alias = controller.store.entityAliases.create {
            $0.name = "The Gate"
            $0.normalizedName = "the gate"
            $0.semanticEntity = entity
        }
        try controller.store.save()
        XCTAssertEqual(alias.semanticEntity.id, entity.id)

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "The Gate opened, and Moon Gate answered."
        )
        controller.flushPendingChanges()

        XCTAssertEqual(project.semanticEntities.filter { $0.kind == SemanticEntityKind.location.rawValue }.count, 1)
        XCTAssertEqual(scene.mentions.count, 2)
        XCTAssertEqual(Set(scene.mentions.map(\.semanticEntity.id)), [entity.id])
    }

    func testSceneSaveReusesCanonicalOrganizationWhenSceneAddsLeadingThe() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })
        let entity = try controller.addStoryBibleEntry(named: "Harbor Council", category: .organizations)

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "the Harbor Council summoned Mara Venn."
        )
        controller.flushPendingChanges()

        XCTAssertEqual(project.semanticEntities.filter { $0.kind == SemanticEntityKind.organization.rawValue }.count, 1)
        XCTAssertEqual(scene.mentions.first { $0.surfaceText == "the Harbor Council" }?.semanticEntity.id, entity.id)
    }

    func testSceneSaveRecognizesLowercaseLeadingOrganizationReference() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "the Harbor Council summoned Mara Venn."
        )
        controller.flushPendingChanges()

        XCTAssertEqual(project.semanticEntities.first { $0.canonicalName == "the Harbor Council" }?.kind, SemanticEntityKind.organization.rawValue)
        XCTAssertEqual(project.semanticEntities.first { $0.canonicalName == "Mara Venn" }?.kind, SemanticEntityKind.character.rawValue)
    }

    func testSceneSaveRecognizesInitialsAcronymsAndInternalCaps() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "R.J. met NASA beside McAllister Square."
        )
        controller.flushPendingChanges()

        XCTAssertNotNil(project.semanticEntities.first { $0.canonicalName == "R.J." })
        XCTAssertNotNil(project.semanticEntities.first { $0.canonicalName == "NASA" })
        XCTAssertNotNil(project.semanticEntities.first { $0.canonicalName == "McAllister Square" })
    }

    func testFlushPendingChangesRefreshesSceneLinksForAllEditedScenes() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let scenes = project.documents
            .filter { $0.narrativeType == NarrativeType.scene.rawValue }
            .sorted { $0.title < $1.title }
        let firstScene = try XCTUnwrap(scenes.first)
        let secondScene = try controller.addDocument(title: "Second Scene", kind: .text, parentID: firstScene.parent?.id)

        controller.updateDocument(
            documentID: firstScene.id,
            title: firstScene.title,
            synopsis: firstScene.synopsis,
            plainText: "Captain Ilex arrived at Dawn Harbor."
        )
        controller.updateDocument(
            documentID: secondScene.id,
            title: secondScene.title,
            synopsis: secondScene.synopsis,
            plainText: "Mara Venn met the Harbor Council."
        )

        controller.flushPendingChanges()

        XCTAssertEqual(firstScene.mentions.map(\.surfaceText).sorted(), ["Captain Ilex", "Dawn Harbor"])
        XCTAssertEqual(secondScene.mentions.map(\.surfaceText).sorted(), ["Harbor Council", "Mara Venn"])
    }

    func testLinkedScenesOmitsTrashedScenes() throws {
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "WorkspaceControllerTests.\(UUID().uuidString)"))
        let controller = WorkspaceController(
            store: try AuthorDataStore(inMemory: true),
            projectListPreferences: preferences
        )
        let project = try controller.createProject(title: "World")
        let scene = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "Mara Venn met The Lantern Society beneath Moon Gate."
        )
        controller.flushPendingChanges()
        controller.trashDocument(scene.id)

        let entity = try XCTUnwrap(project.semanticEntities.first { $0.canonicalName == "Moon Gate" })
        XCTAssertTrue(controller.linkedScenes(for: entity).isEmpty)
    }

    func testDeletingCharacterRemovesItsProfileEntityAndImportedSourceEntry() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let character = try controller.addStoryBibleEntry(named: "Mara", category: .people)
        let profile = try XCTUnwrap(character.characterProfile)
        let source = try controller.addDocument(title: "Mara Source", kind: .text, parentID: nil)
        let profileID = profile.id
        let sourceID = source.id
        let entityID = character.id
        profile.sourceDocument = source
        try controller.store.save()

        controller.deleteCharacterProfile(profile)

        XCTAssertNil(try controller.store.characterProfiles.fetch(id: profileID))
        XCTAssertNil(try controller.store.semanticEntities.fetch(id: entityID))
        XCTAssertNil(try controller.store.documents.fetch(id: sourceID))
        XCTAssertEqual(controller.selection, .storyBibleCategory(projectID: project.id, category: .people))
    }

    func testStoryBibleRelationshipsAreSharedByBothEndpoints() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")
        let organization = try controller.addStoryBibleEntry(
            named: "The Guild",
            category: .organizations
        )
        let artifact = try controller.addStoryBibleEntry(
            named: "The Key",
            category: .artifacts
        )

        try controller.addStoryBibleRelationship(
            kind: "owns",
            notes: "Held in the archive.",
            from: organization,
            to: artifact
        )

        let relationship = try XCTUnwrap(organization.outgoingStoryBibleRelationships.first)
        XCTAssertEqual(relationship.targetEntity.id, artifact.id)
        XCTAssertEqual(artifact.incomingStoryBibleRelationships.map(\.id), [relationship.id])
        XCTAssertEqual(relationship.kind, "owns")
    }

    func testOrganizationMembersAppearAsSharedCharacterRelationships() throws {
        let controller = try makeController()
        try controller.createProject(title: "World")
        let character = try controller.addStoryBibleEntry(named: "Aidan", category: .people)
        let organization = try controller.addStoryBibleEntry(
            named: "The Guild",
            category: .organizations
        )
        let profile = try XCTUnwrap(character.characterProfile)
        let card = try XCTUnwrap(organization.storyBibleCard)

        controller.setCharacters([profile], for: card, relationship: .organization)

        let link = try XCTUnwrap(organization.outgoingStoryBibleRelationships.first)
        XCTAssertEqual(link.kind, "member")
        XCTAssertEqual(link.targetEntity.id, character.id)
        XCTAssertEqual(character.incomingStoryBibleRelationships.map(\.id), [link.id])
    }

    func testOpeningLegacyOrganizationCreatesItsCardTemplate() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "World")
        let organization = controller.store.semanticEntities.create {
            $0.canonicalName = "The Guild"
            $0.kind = SemanticEntityKind.organization.rawValue
            $0.source = ProvenanceAgent.sourceImport.rawValue
            $0.createdAt = Date()
            $0.modifiedAt = Date()
            $0.project = project
        }
        try controller.store.save()

        controller.openStoryBibleCard(for: organization)

        let card = try XCTUnwrap(organization.storyBibleCard)
        XCTAssertEqual(card.semanticEntity.id, organization.id)
        XCTAssertEqual(controller.selection, .storyBibleCard(card.id))
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

        func testImportedTextContainerAcceptsChildrenAsAFolder() throws {
            let controller = try makeController()
            let project = try controller.createProject(title: "Imported")
            let group = controller.store.documents.create {
                $0.sourceIdentifier = "legacy-group"
                $0.title = "Leads"
                $0.kind = DocumentKind.text.rawValue
                $0.orderIndex = 2
                $0.project = project
            }
            let existing = controller.store.documents.create {
                $0.sourceIdentifier = "legacy-character"
                $0.title = "Existing"
                $0.kind = DocumentKind.text.rawValue
                $0.orderIndex = 0
                $0.project = project
                $0.parent = group
            }
            let moved = try controller.addDocument(title: "Moved", kind: .text, parentID: nil)
            try controller.store.save()

            try controller.moveDocument(moved.id, onto: group.id)

            XCTAssertEqual(moved.parent?.id, group.id)
            XCTAssertEqual(group.orderedChildren.map(\.id), [existing.id, moved.id])
        }
    }

    func testMovesSceneOutOfFolderToItsParentLevel() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Binder")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let novel = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(novel.orderedChildren.first)
        let chapter = try controller.addDocument(title: "Chapter One", kind: .folder, parentID: novel.id)

        try controller.moveDocument(scene.id, onto: chapter.id)
        try controller.moveDocument(scene.id, relativeTo: novel.id, position: .inside)

        XCTAssertEqual(scene.parent?.id, novel.id)
        XCTAssertEqual(novel.orderedChildren.map(\.id), [chapter.id, scene.id])
    }

    func testUpdatesDocumentTextThroughPersistenceContract() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        controller.selection = .document(scene.id)

        controller.updateDocument(
            documentID: scene.id,
            title: "Arrival",
            synopsis: "The protagonist arrives.",
            plainText: "Rain covered the station."
        )

        let persisted = try controller.store.documents.require(id: scene.id)
        XCTAssertEqual(persisted.title, "Arrival")
        XCTAssertEqual(persisted.synopsis, "The protagonist arrives.")
        XCTAssertEqual(persisted.plainText, "Rain covered the station.")
    }

    func testProjectTextReplacementSupportsEscapedNewLines() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: nil,
            plainText: "First line\nSecond line\nFirst line\nSecond line"
        )

        let summary = try controller.replaceProjectText(
            searchText: "first line\\nsecond line",
            with: "Opening\\nClosing"
        )

        XCTAssertEqual(summary, ProjectTextReplacementSummary(documentCount: 1, replacementCount: 2))
        XCTAssertEqual(scene.plainText, "Opening\nClosing\nOpening\nClosing")
    }

    func testBinderFindShowsOnlyMatchingDocuments() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let manuscript = try XCTUnwrap(narrative.orderedChildren.first)
        let firstScene = try XCTUnwrap(manuscript.orderedChildren.first)
        let secondScene = try controller.addDocument(
            title: "Second Scene",
            kind: .text,
            parentID: manuscript.id
        )
        controller.updateDocument(
            documentID: firstScene.id,
            title: "Arrival",
            synopsis: nil,
            plainText: "Rain covered the station."
        )
        controller.updateDocument(
            documentID: secondScene.id,
            title: "Departure",
            synopsis: nil,
            plainText: "Sunlight filled the platform."
        )

        controller.binderSearchText = "station"

        XCTAssertEqual(controller.displayedBinderItems.map(\.title), ["Arrival"])
        XCTAssertTrue(controller.displayedBinderItems.allSatisfy { $0.children == nil })
    }

    func testBinderFindIncludesStoryBibleEntries() throws {
        let controller = try makeController()
        try controller.createProject(title: "Draft")
        _ = try controller.addStoryBibleEntry(named: "Mara Venn", category: .people)

        controller.binderSearchText = "mara"

        XCTAssertEqual(controller.displayedBinderItems.map(\.title), ["Mara Venn"])
        XCTAssertEqual(controller.displayedBinderItems.first?.kind, .characterProfile)
    }

    func testStatusFilterDeduplicatesTitlesAndMatchesDuplicateIdentifiers() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let manuscript = try XCTUnwrap(narrative.orderedChildren.first)
        let firstScene = try XCTUnwrap(manuscript.orderedChildren.first)
        let secondScene = try controller.addDocument(
            title: "Second Scene",
            kind: .text,
            parentID: manuscript.id
        )
        let firstDraft = try XCTUnwrap(controller.addStatus(title: "First Draft"))
        let duplicateFirstDraft = try XCTUnwrap(controller.addStatus(title: "First Draft"))
        firstScene.statusIdentifier = firstDraft.sourceIdentifier
        secondScene.statusIdentifier = duplicateFirstDraft.sourceIdentifier
        try controller.store.save()
        controller.refresh()

        XCTAssertEqual(
            controller.filterStatusDefinitions.filter { $0.title == "First Draft" }.count,
            1
        )
        controller.statusFilter = firstDraft.sourceIdentifier

        let narrativeItem = try XCTUnwrap(
            controller.displayedBinderItems.first { $0.kind == .narrative }
        )
        let manuscriptItem = try XCTUnwrap(narrativeItem.children?.first)
        XCTAssertEqual(manuscriptItem.children?.map(\.title), ["Opening Scene", "Second Scene"])
    }

    func testFlushPendingChangesPersistsDebouncedDocumentEdit() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let scene = try XCTUnwrap(
            project.documents.first { $0.kind == DocumentKind.text.rawValue }
        )
        controller.selection = .document(scene.id)

        controller.updateDocument(
            documentID: scene.id,
            title: scene.title,
            synopsis: scene.synopsis,
            plainText: "Saved when leaving the editor."
        )

        XCTAssertTrue(controller.store.context.hasChanges)
        controller.flushPendingChanges()
        XCTAssertFalse(controller.store.context.hasChanges)
        XCTAssertEqual(
            try controller.store.documents.require(id: scene.id).plainText,
            "Saved when leaving the editor."
        )
    }

    func testWordCountRollsUpIncrementallyThroughAncestorsOnTextEdit() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        let scene = try XCTUnwrap(book.orderedChildren.first)
        controller.selection = .document(scene.id)

        controller.updateDocument(documentID: scene.id, title: scene.title, synopsis: nil, plainText: "one two three four five")

        XCTAssertEqual(scene.ownWordCount, 5)
        XCTAssertEqual(scene.actualWordCount, 5)
        XCTAssertEqual(book.actualWordCount, 5)
        XCTAssertEqual(narrative.actualWordCount, 5)

        controller.updateDocument(documentID: scene.id, title: scene.title, synopsis: nil, plainText: "one two")

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
        controller.updateDocument(documentID: scene.id, title: scene.title, synopsis: nil, plainText: "alpha beta gamma")
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

        controller.addBookISBN(for: .hardback, on: book)
        controller.addBookISBN(for: .ebook, on: book)
        controller.setBookISBN("978-0-000-00000-0", for: .hardback, on: book)
        controller.setBookISBN("978-0-000-00000-1", for: .ebook, on: book)

        let isbnEntries = controller.bookISBNs(on: book)
        XCTAssertEqual(isbnEntries.map(\.format), [.hardback, .ebook])
        XCTAssertEqual(isbnEntries.first?.number, "978-0-000-00000-0")
        XCTAssertEqual(isbnEntries.last?.number, "978-0-000-00000-1")
        XCTAssertFalse(NarrativeMetadataSchema.fields(for: .book).contains { $0.key == "system.book.isbn" })
        XCTAssertFalse(NarrativeMetadataSchema.fields(for: .book).contains { $0.key == "system.book.author" })
        XCTAssertFalse(NarrativeMetadataSchema.fields(for: .book).contains { $0.key == "system.book.agentName" })
        controller.removeBookISBN(for: .hardback, on: book)
        XCTAssertEqual(controller.bookISBNs(on: book).map(\.format), [.ebook])

        let legacyISBN = NarrativeFieldDescriptor(
            key: "system.book.isbn",
            displayName: "ISBN",
            valueKind: .text
        )
        controller.setNarrativeFieldValue("978-0-000-00000-2", for: legacyISBN, on: book)
        XCTAssertEqual(
            controller.bookISBNs(on: book).first { $0.format == .unspecified }?.number,
            "978-0-000-00000-2"
        )

        let targetField = try XCTUnwrap(
            NarrativeMetadataSchema.fields(for: .book).first { $0.key == NarrativeMetadataSchema.targetWordCountKey }
        )
        controller.setNarrativeFieldValue("80000", for: targetField, on: book)
        XCTAssertEqual(controller.narrativeFieldValue(targetField, on: book), "80000")
    }

    func testNarrativeTextFieldsPreserveWhitespaceWhileTypingAndAfterReload() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let document = try XCTUnwrap(narrative.orderedChildren.first)

        for type in NarrativeType.allCases {
            for field in NarrativeMetadataSchema.fields(for: type)
                where field.valueKind == .text || field.valueKind == .longText {
                var expected = ""
                for character in " A  B\nC \n" {
                    expected.append(character)
                    let input = controller.narrativeFieldValue(field, on: document) + String(character)
                    controller.setNarrativeFieldValue(input, for: field, on: document)
                    XCTAssertEqual(controller.narrativeFieldValue(field, on: document), expected, field.key)
                }
                controller.store.context.refreshAllObjects()
                XCTAssertEqual(controller.narrativeFieldValue(field, on: document), expected, field.key)
                XCTAssertNil(controller.lastError)

                controller.setNarrativeFieldValue("", for: field, on: document)
                XCTAssertEqual(controller.narrativeFieldValue(field, on: document), "")
                XCTAssertNil(NarrativeMetadataStore.value(for: field, on: document))
            }
        }
    }

    func testBookISBNPreservesSpacesWhileTypingAndAfterReload() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        controller.addBookISBN(for: .paperback, on: book)

        var expected = ""
        for character in " 978  0 123456 47 2 " {
            expected.append(character)
            let input = try XCTUnwrap(controller.bookISBNs(on: book).first?.number) + String(character)
            controller.setBookISBN(input, for: .paperback, on: book)
            XCTAssertEqual(controller.bookISBNs(on: book).first?.number, expected)
        }
        controller.store.context.refreshAllObjects()
        XCTAssertEqual(controller.bookISBNs(on: book).first?.number, expected)
        XCTAssertNil(controller.lastError)

        controller.setBookISBN("", for: .paperback, on: book)
        XCTAssertEqual(controller.bookISBNs(on: book).map(\.format), [.paperback])
        XCTAssertEqual(controller.bookISBNs(on: book).first?.number, "")
    }

    func testNarrativeNumberAndDateFieldsStillNormalizeWhitespace() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        let fields = NarrativeMetadataSchema.fields(for: .book)
        let number = try XCTUnwrap(fields.first { $0.valueKind == .number })
        let date = try XCTUnwrap(fields.first { $0.valueKind == .date })

        controller.setNarrativeFieldValue(" 80000 \n", for: number, on: book)
        XCTAssertEqual(controller.narrativeFieldValue(number, on: book), "80000")
        controller.setNarrativeFieldValue(" 2026-09-17T12:00:00Z \n", for: date, on: book)
        XCTAssertEqual(controller.narrativeFieldValue(date, on: book), "2026-09-17T12:00:00Z")

        for field in [number, date] {
            controller.setNarrativeFieldValue(" \n", for: field, on: book)
            XCTAssertNil(NarrativeMetadataStore.value(for: field, on: book))
        }
        XCTAssertNil(controller.lastError)
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

    func testStoresOneNamedCoverForEachBookCoverSlot() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Draft")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let book = try XCTUnwrap(narrative.orderedChildren.first)
        controller.setNarrativeType(book, to: .book)
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try imageData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        try controller.setBookCover(from: imageURL, kind: .front, on: book)
        try controller.setBookCover(from: imageURL, kind: .back, on: book)
        let frontCoverID = try XCTUnwrap(controller.bookCover(.front, on: book)?.id)
        XCTAssertEqual(controller.bookCover(.front, on: book)?.resource.data, imageData)
        XCTAssertEqual(controller.bookCover(.front, on: book)?.resource.role, "bookCover.front")
        XCTAssertEqual(controller.bookCover(.back, on: book)?.resource.role, "bookCover.back")

        try controller.setBookCover(from: imageURL, kind: .front, on: book)
        XCTAssertNotEqual(controller.bookCover(.front, on: book)?.id, frontCoverID)
        XCTAssertEqual(book.sourceGalleryItems.filter { $0.resource.role == "bookCover.front" }.count, 1)

        controller.removeBookCover(.back, on: book)
        XCTAssertNil(controller.bookCover(.back, on: book))
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
        let jacob = controller.store.documents.create {
            $0.sourceIdentifier = "character"
            $0.title = "Jacob"
            $0.kind = DocumentKind.text.rawValue
            $0.orderIndex = 2
            $0.project = project
        }
        let jacobEntity = controller.store.semanticEntities.create {
            $0.canonicalName = "Jacob"
            $0.kind = SemanticEntityKind.character.rawValue
            $0.source = ProvenanceAgent.sourceImport.rawValue
            $0.createdAt = Date()
            $0.modifiedAt = Date()
            $0.project = project
        }
        let jacobProfile = controller.store.characterProfiles.create {
            $0.firstName = "Jacob"
            $0.source = ProvenanceAgent.sourceImport.rawValue
            $0.createdAt = Date()
            $0.modifiedAt = Date()
            $0.project = project
            $0.semanticEntity = jacobEntity
            $0.sourceDocument = jacob
        }
        let leads = controller.store.documents.create {
            $0.sourceIdentifier = "leads"
            $0.title = "Leads"
            $0.kind = DocumentKind.folder.rawValue
            $0.orderIndex = 1
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
        XCTAssertEqual(people.children?.map(\.title), ["Characters", "Jacob"])
        XCTAssertEqual(narrative.children?.map(\.title), ["Novel"])
        XCTAssertEqual(controller.storyBibleCategory(for: characters), .people)
        try controller.moveDocument(jacob.id, onto: leads.id)
        XCTAssertEqual(jacob.parent?.id, leads.id)
        XCTAssertEqual(controller.storyBibleCategory(for: jacob), .people)
        XCTAssertTrue(jacob.sourceCharacterProfiles.contains(jacobProfile))

        try controller.moveDocument(leads.id, toStoryBibleCategory: .people)
        XCTAssertNil(leads.parent)
        XCTAssertEqual(controller.storyBibleCategory(for: leads), .people)

        leads.sectionTypeIdentifier = nil
        try controller.moveDocument(leads.id, relativeTo: characters.id, position: .after)
        XCTAssertNil(leads.parent)
        XCTAssertEqual(leads.sectionTypeIdentifier, "storyBible.people")
        XCTAssertEqual(controller.storyBibleCategory(for: leads), .people)
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
        controller.updateDocumentRichText(documentID: scene.id, rtfData: data, plainText: "Hello")

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

    func testRichTextUpdateDoesNotOverwriteSourcePreservedResource() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Imported Text")
        let scene = try XCTUnwrap(project.documents.first { $0.kind == DocumentKind.text.rawValue })
        let originalData = Data(#"{\rtf1\ansi Imported original}"#.utf8)
        let sourceResource = controller.store.resources.create {
            $0.sourcePath = "Files/Data/original.rtf"
            $0.role = "content"
            $0.mediaType = "application/rtf"
            $0.byteCount = Int64(originalData.count)
            $0.sha256 = "original"
            $0.isSourcePreserved = true
            $0.data = originalData
            $0.textContent = "Imported original"
            $0.project = project
            $0.document = scene
        }
        let editedData = Data(#"{\rtf1\ansi Edited text}"#.utf8)

        controller.updateDocumentRichText(
            documentID: scene.id,
            rtfData: editedData,
            plainText: "Edited text"
        )

        XCTAssertEqual(sourceResource.data, originalData)
        XCTAssertEqual(sourceResource.textContent, "Imported original")
        let nativeResource = try XCTUnwrap(scene.resources.first { !$0.isSourcePreserved })
        XCTAssertEqual(nativeResource.data, editedData)
        XCTAssertEqual(nativeResource.textContent, "Edited text")
    }

    func testDelayedRichTextUpdateTargetsOriginatingDocumentAfterSelectionChanges() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Delayed Edit")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let script = try XCTUnwrap(narrative.orderedChildren.first)
        let firstScene = try XCTUnwrap(script.orderedChildren.first)
        let secondScene = try controller.addDocument(title: "Second Scene", kind: .text, parentID: script.id)
        firstScene.plainText = "First original"
        secondScene.plainText = "Second original"

        controller.selection = .document(secondScene.id)
        let delayedData = Data(#"{\rtf1\ansi First edited}"#.utf8)
        controller.updateDocumentRichText(
            documentID: firstScene.id,
            rtfData: delayedData,
            plainText: "First edited"
        )

        XCTAssertEqual(firstScene.plainText, "First edited")
        XCTAssertEqual(secondScene.plainText, "Second original")
        XCTAssertEqual(firstScene.resources.first { $0.mediaType == "application/rtf" }?.data, delayedData)
        XCTAssertNil(secondScene.resources.first { $0.mediaType == "application/rtf" })
    }

    func testMurderBoardAppearsInStoryBibleOverviewAndBinder() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Murder Board Test")

        let board = try controller.createMurderBoard(named: "Main Relationships")

        XCTAssertEqual(controller.selection, .murderBoard(board.id))
        XCTAssertEqual(controller.murderBoards.map(\.title), ["Main Relationships"])
        let storyBible = try XCTUnwrap(controller.binderItems.first { $0.title == "Story Bible" })
        let murderBoardItem = try XCTUnwrap(storyBible.children?.first { $0.title == "Murder Board" })
        XCTAssertEqual(murderBoardItem.selection, .murderBoardOverview(project.id))
        XCTAssertEqual(murderBoardItem.children?.map(\.title), ["Main Relationships"])
    }

    func testMurderBoardStatePersistsAndDeletingBoardKeepsStoryBibleData() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Persistence")
        let mara = try controller.addStoryBibleEntry(named: "Mara Venn", category: .people)
        let moonGate = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)
        try controller.addStoryBibleRelationship(kind: "guards", notes: "Night watch", from: mara, to: moonGate)
        let board = try controller.createMurderBoard(named: "Guard Web")

        var state = MurderBoardState()
        state.selectedEntityID = mara.id
        state.connectedDepth = .twoHops
        state.hiddenRelationshipKinds = ["betrays"]
        state.nodeStates = [
            MurderBoardNodeState(entityID: mara.id, x: 120, y: -80, isPinned: true),
            MurderBoardNodeState(entityID: moonGate.id, x: -160, y: 90)
        ]

        controller.saveMurderBoardState(state, for: board)

        let persisted = controller.murderBoardState(for: board)
        XCTAssertEqual(persisted.selectedEntityID, mara.id)
        XCTAssertEqual(persisted.connectedDepth, .twoHops)
        XCTAssertEqual(persisted.nodeState(for: mara.id)?.x, 120)
        XCTAssertEqual(persisted.nodeState(for: mara.id)?.isPinned, true)
        XCTAssertEqual(persisted.hiddenRelationshipKinds, ["betrays"])

        controller.renameMurderBoard(board, title: "Night Watch")
        XCTAssertEqual(controller.murderBoards.map(\.title), ["Night Watch"])

        controller.deleteMurderBoard(board)

        XCTAssertEqual(controller.murderBoards.count, 0)
        XCTAssertEqual(controller.selection, .murderBoardOverview(project.id))
        XCTAssertEqual(controller.selectedProject?.semanticEntities.count, 2)
        XCTAssertEqual(mara.outgoingStoryBibleRelationships.count, 1)
    }

    func testMurderBoardGraphFiltersByBookDepthAndRelationshipType() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Scoped Graph")
        let board = try controller.createMurderBoard(named: "Scoped")
        let narrative = try XCTUnwrap(project.documents.first { $0.title == "Narrative" })
        let bookOne = try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.book.rawValue })
        let bookTwo = try controller.addDocument(title: "Book Two", kind: .folder, parentID: narrative.id)
        controller.setNarrativeType(bookTwo, to: .book)
        let sceneOne = try XCTUnwrap(bookOne.orderedChildren.first)
        let sceneTwo = try controller.addDocument(title: "Book Two Scene", kind: .text, parentID: bookTwo.id)

        let mara = try controller.addStoryBibleEntry(named: "Mara Venn", category: .people)
        let lantern = try controller.addStoryBibleEntry(named: "Lantern Society", category: .organizations)
        let gate = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)

        try controller.addStoryBibleRelationship(kind: "member of", notes: nil, from: mara, to: lantern)
        try controller.addStoryBibleRelationship(kind: "meets at", notes: nil, from: lantern, to: gate)

        controller.updateDocument(
            documentID: sceneOne.id,
            title: sceneOne.title,
            synopsis: sceneOne.synopsis,
            plainText: "Mara Venn met the Lantern Society."
        )
        controller.updateDocument(
            documentID: sceneTwo.id,
            title: sceneTwo.title,
            synopsis: sceneTwo.synopsis,
            plainText: "Lantern Society gathered at Moon Gate."
        )
        controller.flushPendingChanges()

        var state = MurderBoardState()
        state.selectedBookID = bookOne.id
        state.selectedEntityID = mara.id
        state.connectedDepth = .direct
        let scopedGraph = controller.murderBoardGraph(for: board, state: state)

        XCTAssertEqual(Set(scopedGraph.nodes.map(\.entity.canonicalName)), ["Mara Venn", "Lantern Society"])
        XCTAssertEqual(scopedGraph.edges.map(\.relationship.kind), ["member of"])

        state.hiddenRelationshipKinds = ["member of"]
        let hiddenGraph = controller.murderBoardGraph(for: board, state: state)
        XCTAssertTrue(hiddenGraph.edges.isEmpty)
    }

    func testMurderBoardGraphReflectsCanonicalRelationshipUpdates() throws {
        let controller = try makeController()
        _ = try controller.createProject(title: "Canonical Graph")
        let board = try controller.createMurderBoard(named: "Canonical")
        let mara = try controller.addStoryBibleEntry(named: "Mara Venn", category: .people)
        let gate = try controller.addStoryBibleEntry(named: "Moon Gate", category: .places)
        try controller.addStoryBibleRelationship(kind: "visits", notes: "Chapter 1", from: mara, to: gate)

        var graph = controller.murderBoardGraph(for: board, state: MurderBoardState())
        let relationship = try XCTUnwrap(graph.edges.first?.relationship)
        XCTAssertEqual(relationship.kind, "visits")

        relationship.kind = "guards"
        relationship.notes = "Updated"
        controller.saveStoryBibleRelationship(relationship)

        graph = controller.murderBoardGraph(for: board, state: MurderBoardState())
        XCTAssertEqual(graph.edges.first?.relationship.kind, "guards")
        XCTAssertEqual(graph.edges.first?.relationship.notes, "Updated")
    }

    private func makeController() throws -> WorkspaceController {
        WorkspaceController(store: try AuthorDataStore(inMemory: true))
    }
}
