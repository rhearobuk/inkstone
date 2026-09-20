import AuthorData
import CoreData
import XCTest
@testable import AuthorUI

@MainActor
final class ContentManagementTests: XCTestCase {
    func testDeletesEverySemanticKindAndOwnedGraphButPreservesRelatedContentAndGallery() throws {
        for kind in SemanticEntityKind.allCases {
            let controller = try makeController()
            let project = try controller.createProject(title: "Synthetic \(kind.rawValue)")
            let category = try XCTUnwrap(StoryBibleCategory.allCases.first { $0.contains(kind: kind.rawValue) })
            let entry = try controller.addStoryBibleEntry(named: "Entry", category: category, kind: kind)
            let survivor = try controller.addStoryBibleEntry(named: "Survivor", category: .people)
            let survivorProfile = try XCTUnwrap(survivor.characterProfile)
            let card = try XCTUnwrap(entry.storyBibleCard)
            let scene = try narrativeScene(in: project)
            scene.plainText = "Synthetic text must survive entry deletion."
            card.relatedCharacters = [survivorProfile]
            card.owners = [survivorProfile]
            card.linkedCharacters = [survivorProfile]
            try controller.addStoryBibleNote(title: "Owned note", body: "Synthetic note", to: card)
            let noteID = try XCTUnwrap(card.notes.first?.id)
            let alias = controller.store.entityAliases.create {
                $0.name = "Synthetic alias"
                $0.normalizedName = "synthetic alias"
                $0.semanticEntity = entry
            }
            let mention = controller.store.mentions.create {
                $0.location = 0
                $0.length = 9
                $0.surfaceText = "Synthetic"
                $0.source = "human"
                $0.document = scene
                $0.semanticEntity = entry
            }
            try controller.addStoryBibleRelationship(kind: "outgoing", notes: nil, from: entry, to: survivor)
            try controller.addStoryBibleRelationship(kind: "incoming", notes: nil, from: survivor, to: entry)
            let relationshipIDs = entry.outgoingStoryBibleRelationships.union(entry.incomingStoryBibleRelationships).map(\.id)
            let gallery = makeGalleryItem(in: controller, project: project, entity: entry)
            let entryID = entry.id
            let cardID = card.id
            let aliasID = alias.id
            let mentionID = mention.id
            let profileID = entry.characterProfile?.id
            let galleryID = gallery.id
            let resourceID = gallery.resource.id
            let sceneID = scene.id
            let survivorID = survivor.id
            let survivorProfileID = survivorProfile.id
            try controller.store.save()
            controller.selection = .storyBibleCard(cardID)

            try controller.deleteSemanticEntity(entryID)

            XCTAssertNil(try controller.store.semanticEntities.fetch(id: entryID), kind.rawValue)
            XCTAssertNil(try controller.store.storyBibleCards.fetch(id: cardID), kind.rawValue)
            XCTAssertNil(try controller.store.storyBibleNotes.fetch(id: noteID), kind.rawValue)
            XCTAssertNil(try controller.store.entityAliases.fetch(id: aliasID), kind.rawValue)
            XCTAssertNil(try controller.store.mentions.fetch(id: mentionID), kind.rawValue)
            for id in relationshipIDs {
                XCTAssertNil(try controller.store.storyBibleRelationships.fetch(id: id), kind.rawValue)
            }
            if let profileID {
                XCTAssertNil(try controller.store.characterProfiles.fetch(id: profileID))
            }
            XCTAssertNotNil(try controller.store.semanticEntities.fetch(id: survivorID))
            XCTAssertNotNil(try controller.store.characterProfiles.fetch(id: survivorProfileID))
            XCTAssertTrue(survivorProfile.placeCards.isEmpty)
            XCTAssertTrue(survivorProfile.artifactCards.isEmpty)
            XCTAssertTrue(survivorProfile.organizationCards.isEmpty)
            XCTAssertEqual(try controller.store.documents.require(id: sceneID).plainText,
                           "Synthetic text must survive entry deletion.")
            let survivingGallery = try controller.store.galleryItems.require(id: galleryID)
            XCTAssertNil(survivingGallery.semanticEntity)
            XCTAssertEqual(survivingGallery.resource.id, resourceID)
            XCTAssertEqual(try controller.store.resources.require(id: resourceID).data, Data([1, 2, 3, 4]))
            XCTAssertEqual(controller.selection, .storyBibleCategory(projectID: project.id, category: category))
            XCTAssertFalse(allItems(controller.binderItems).contains { $0.semanticEntityID == entryID })
        }
    }

    func testImportedCharacterDeletionRemovesSourceAndOwnedRecordsWithoutDeletingRelatedCharacters() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Imported synthetic character")
        let imported = try makeImportedCharacter(in: controller, project: project)
        let survivor = try controller.addStoryBibleEntry(named: "Una Vale", category: .people)
        let survivorProfile = try XCTUnwrap(survivor.characterProfile)
        let place = try controller.addStoryBibleEntry(named: "Synthetic Harbor", category: .places)
        let placeCard = try XCTUnwrap(place.storyBibleCard)
        placeCard.relatedCharacters = [imported.profile, survivorProfile]
        try controller.addAlias("The Visitor", to: imported.profile)
        try controller.addMeasurement(name: "Height", value: "170", unit: "cm", to: imported.profile)
        try controller.addCharacterNote(title: nil, body: "An owned character note", to: imported.profile)
        try controller.addCharacterRelationship(kind: "friend", notes: nil, from: imported.profile, to: survivorProfile)
        try controller.addCharacterRelationship(kind: "rival", notes: nil, from: survivorProfile, to: imported.profile)
        try controller.addCharacterConflict(title: "Owned conflict", summary: nil, kind: "external",
                                            relatedCharacter: survivorProfile, to: imported.profile)
        try controller.addCharacterConflict(title: "Surviving conflict", summary: nil, kind: "external",
                                            relatedCharacter: imported.profile, to: survivorProfile)
        let ownedConflictID = try XCTUnwrap(imported.profile.conflicts.first?.id)
        let survivingConflictID = try XCTUnwrap(survivorProfile.conflicts.first?.id)
        let noteID = try XCTUnwrap(imported.profile.notes.first?.id)
        let measurementID = try XCTUnwrap(imported.profile.measurements.first?.id)
        let aliasID = try XCTUnwrap(imported.entity.aliases.first?.id)
        let relationshipIDs = imported.profile.outgoingRelationships.union(imported.profile.incomingRelationships).map(\.id)
        let scene = try narrativeScene(in: project)
        scene.plainText = "The visitor crossed the synthetic harbor."
        let gallery = makeGalleryItem(in: controller, project: project, entity: imported.entity,
                                      sourceDocument: imported.document)
        let sourceID = imported.document.id
        let profileID = imported.profile.id
        let entityID = imported.entity.id
        let galleryID = gallery.id
        let sceneID = scene.id
        try controller.store.save()

        XCTAssertEqual(controller.contentTarget(for: imported.entity), .document(sourceID))
        try controller.deleteSemanticEntity(entityID)

        XCTAssertNil(try controller.store.documents.fetch(id: sourceID))
        XCTAssertNil(try controller.store.characterProfiles.fetch(id: profileID))
        XCTAssertNil(try controller.store.semanticEntities.fetch(id: entityID))
        XCTAssertNil(try controller.store.characterNotes.fetch(id: noteID))
        XCTAssertNil(try controller.store.characterMeasurements.fetch(id: measurementID))
        XCTAssertNil(try controller.store.entityAliases.fetch(id: aliasID))
        XCTAssertNil(try controller.store.characterConflicts.fetch(id: ownedConflictID))
        for id in relationshipIDs {
            XCTAssertNil(try controller.store.characterRelationships.fetch(id: id))
        }
        let survivingConflict = try controller.store.characterConflicts.require(id: survivingConflictID)
        XCTAssertTrue(survivingConflict.relatedCharacters.isEmpty)
        XCTAssertEqual(survivingConflict.characterProfile.id, survivorProfile.id)
        XCTAssertEqual(placeCard.relatedCharacters.map(\.id), [survivorProfile.id])
        XCTAssertNotNil(try controller.store.semanticEntities.fetch(id: survivor.id))
        XCTAssertEqual(try controller.store.documents.require(id: sceneID).plainText,
                       "The visitor crossed the synthetic harbor.")
        let survivingGallery = try controller.store.galleryItems.require(id: galleryID)
        XCTAssertNil(survivingGallery.semanticEntity)
        XCTAssertNil(survivingGallery.sourceDocument)
        XCTAssertEqual(survivingGallery.resource.data, Data([1, 2, 3, 4]))
        XCTAssertEqual(controller.selection, .storyBibleCategory(projectID: project.id, category: .people))
    }

    func testRejectsForeignMissingAndTrashedTargetsWithoutMutatingThem() throws {
        let controller = try makeController()
        let foreignProject = try controller.createProject(title: "Other project")
        let foreignEntity = try controller.addStoryBibleEntry(named: "Foreign", category: .places)
        let foreignDocument = try narrativeScene(in: foreignProject)
        let foreignLabel = try XCTUnwrap(controller.addLabel(title: "Foreign label"))
        let foreignStatus = try XCTUnwrap(controller.addStatus(title: "Foreign status"))
        let project = try controller.createProject(title: "Current project")
        let local = try controller.addStoryBibleEntry(named: "Local", category: .places)
        let imported = try makeImportedCharacter(in: controller, project: project)
        let label = try XCTUnwrap(controller.addLabel(title: "Local label"))
        let status = try XCTUnwrap(controller.addStatus(title: "Local status"))
        controller.trashDocument(imported.document.id)

        for target in [BinderContentTarget.document(foreignDocument.id), .semanticEntity(foreignEntity.id),
                       .document(imported.document.id), .semanticEntity(imported.entity.id)] {
            assertContentError(.unavailableTarget) { try controller.setContentLabel(label.sourceIdentifier, for: target) }
            assertContentError(.unavailableTarget) { try controller.setContentStatus(status.sourceIdentifier, for: target) }
            assertContentError(.unavailableTarget) {
                try controller.moveContent(target, relativeTo: .semanticEntity(local.id), position: .before)
            }
            assertContentError(.unavailableTarget) { try controller.moveContent(target, toStoryBibleCategory: .places) }
        }
        assertContentError(.unavailableTarget) { try controller.deleteSemanticEntity(foreignEntity.id) }
        assertContentError(.unavailableTarget) { try controller.deleteSemanticEntity(imported.entity.id) }
        assertContentError(.unavailableTarget) {
            try controller.moveContent(.semanticEntity(local.id), relativeTo: .document(foreignDocument.id), position: .after)
        }
        for target in [BinderContentTarget.document(UUID()), .semanticEntity(UUID())] {
            XCTAssertThrowsError(try controller.contentMetadata(for: target))
            XCTAssertThrowsError(try controller.setContentLabel(nil, for: target))
            XCTAssertThrowsError(try controller.setContentStatus(nil, for: target))
            XCTAssertThrowsError(try controller.moveContent(target, toStoryBibleCategory: .places))
        }
        XCTAssertThrowsError(try controller.deleteSemanticEntity(UUID()))
        for identifier in [foreignLabel.sourceIdentifier, "missing-label"] {
            assertContentError(.foreignDefinition) {
                try controller.setContentLabel(identifier, for: .semanticEntity(local.id))
            }
        }
        for identifier in [foreignStatus.sourceIdentifier, "missing-status"] {
            assertContentError(.foreignDefinition) {
                try controller.setContentStatus(identifier, for: .semanticEntity(local.id))
            }
        }
        XCTAssertNotNil(try controller.store.semanticEntities.fetch(id: imported.entity.id))
        XCTAssertNotNil(try controller.store.semanticEntities.fetch(id: foreignEntity.id))
        XCTAssertNil(local.labelIdentifier)
        XCTAssertNil(local.statusIdentifier)
        XCTAssertNil(foreignDocument.labelIdentifier)
        XCTAssertNil(foreignEntity.statusIdentifier)
    }

    func testTrashAncestorRejectsImportedCharacterMutationAndDeletion() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Trashed ancestor")
        let folder = try makeDocument(in: controller, project: project, title: "People folder", category: .people)
        let imported = try makeImportedCharacter(in: controller, project: project)
        try controller.moveContent(.document(imported.document.id), relativeTo: .document(folder.id), position: .inside)
        let label = try XCTUnwrap(controller.addLabel(title: "Kept label"))
        try controller.setContentLabel(label.sourceIdentifier, for: .semanticEntity(imported.entity.id))
        controller.trashDocument(folder.id)

        assertContentError(.unavailableTarget) { try controller.setContentLabel(nil, for: .semanticEntity(imported.entity.id)) }
        assertContentError(.unavailableTarget) { try controller.deleteSemanticEntity(imported.entity.id) }
        XCTAssertEqual(try controller.contentMetadata(for: .semanticEntity(imported.entity.id)).labelIdentifier,
                       label.sourceIdentifier)
        XCTAssertNotNil(try controller.store.characterProfiles.fetch(id: imported.profile.id))
        controller.restoreDocument(folder.id)
        try controller.setContentLabel(nil, for: .semanticEntity(imported.entity.id))
        XCTAssertNil(imported.document.labelIdentifier)
    }

    func testAssignChangeAndClearMetadataOnDocumentsAndEveryNativeEntityKind() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Metadata coverage")
        let scene = try narrativeScene(in: project)
        let research = try controller.addResearchDocument(title: "Synthetic research")
        let folder = try XCTUnwrap(scene.parent)
        var targets: [BinderContentTarget] = [.document(scene.id), .document(folder.id), .document(research.id)]
        for kind in SemanticEntityKind.allCases {
            let category = try XCTUnwrap(StoryBibleCategory.allCases.first { $0.contains(kind: kind.rawValue) })
            let entity = try controller.addStoryBibleEntry(named: kind.rawValue, category: category, kind: kind)
            targets.append(.semanticEntity(entity.id))
        }
        let firstLabel = try XCTUnwrap(controller.addLabel(title: "First label", color: (0.1, 0.2, 0.3)))
        let secondLabel = try XCTUnwrap(controller.addLabel(title: "Second label"))
        let firstStatus = try XCTUnwrap(controller.addStatus(title: "First status"))
        let secondStatus = try XCTUnwrap(controller.addStatus(title: "Second status"))

        for target in targets {
            XCTAssertNil(try controller.contentMetadata(for: target).labelIdentifier)
            XCTAssertNil(try controller.contentMetadata(for: target).statusIdentifier)
            for (label, status) in [(firstLabel, firstStatus), (secondLabel, secondStatus)] {
                try controller.setContentLabel(label.sourceIdentifier, for: target)
                try controller.setContentStatus(status.sourceIdentifier, for: target)
                let metadata = try controller.contentMetadata(for: target)
                XCTAssertEqual(metadata.labelIdentifier, label.sourceIdentifier)
                XCTAssertEqual(metadata.statusIdentifier, status.sourceIdentifier)
                let item = try XCTUnwrap(allItems(controller.binderItems).first { $0.contentTarget == target })
                XCTAssertEqual(item.labelIdentifier, label.sourceIdentifier)
                XCTAssertEqual(item.statusIdentifier, status.sourceIdentifier)
                XCTAssertEqual(item.labelTitle, label.title)
                XCTAssertEqual(item.statusTitle, status.title)
                if label === firstLabel { XCTAssertNotNil(item.labelColor) }
            }
            try controller.setContentLabel(nil, for: target)
            XCTAssertNil(try controller.contentMetadata(for: target).labelIdentifier)
            XCTAssertEqual(try controller.contentMetadata(for: target).statusIdentifier, secondStatus.sourceIdentifier)
            try controller.setContentStatus(nil, for: target)
            XCTAssertNil(try controller.contentMetadata(for: target).statusIdentifier)
        }
    }

    func testImportedCharacterMetadataUsesCanonicalSourceDocumentForBothTargets() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Canonical metadata")
        let imported = try makeImportedCharacter(in: controller, project: project)
        let label = try XCTUnwrap(controller.addLabel(title: "Label one"))
        let changedLabel = try XCTUnwrap(controller.addLabel(title: "Label two"))
        let status = try XCTUnwrap(controller.addStatus(title: "Status one"))
        let changedStatus = try XCTUnwrap(controller.addStatus(title: "Status two"))
        let entityTarget = BinderContentTarget.semanticEntity(imported.entity.id)
        let documentTarget = BinderContentTarget.document(imported.document.id)
        XCTAssertEqual(controller.contentTarget(for: imported.entity), documentTarget)

        for (target, label, status) in [(entityTarget, label, status), (documentTarget, changedLabel, changedStatus)] {
            try controller.setContentLabel(label.sourceIdentifier, for: target)
            try controller.setContentStatus(status.sourceIdentifier, for: target)
            XCTAssertEqual(imported.document.labelIdentifier, label.sourceIdentifier)
            XCTAssertEqual(imported.document.statusIdentifier, status.sourceIdentifier)
            for aliasTarget in [documentTarget, entityTarget] {
                XCTAssertEqual(try controller.contentMetadata(for: aliasTarget).labelIdentifier, label.sourceIdentifier)
                XCTAssertEqual(try controller.contentMetadata(for: aliasTarget).statusIdentifier, status.sourceIdentifier)
            }
            XCTAssertNil(imported.entity.labelIdentifier)
            XCTAssertNil(imported.entity.statusIdentifier)
            let items = allItems(controller.binderItems).filter { $0.contentTarget == documentTarget }
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.labelTitle, label.title)
            XCTAssertEqual(items.first?.statusTitle, status.title)
        }
        try controller.setContentLabel(nil, for: entityTarget)
        try controller.setContentStatus(nil, for: entityTarget)
        XCTAssertNil(imported.document.labelIdentifier)
        XCTAssertNil(imported.document.statusIdentifier)
    }

    func testDefinitionRenameRefreshesBadgesWithoutChangingIdentifiers() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Rename definitions")
        let document = try narrativeScene(in: project)
        let entity = try controller.addStoryBibleEntry(named: "Entry", category: .artifacts)
        let label = try XCTUnwrap(controller.addLabel(title: "Old label"))
        let status = try XCTUnwrap(controller.addStatus(title: "Old status"))
        let labelID = label.sourceIdentifier
        let statusID = status.sourceIdentifier
        let targets: [BinderContentTarget] = [.document(document.id), .semanticEntity(entity.id)]
        for target in targets {
            try controller.setContentLabel(labelID, for: target)
            try controller.setContentStatus(statusID, for: target)
        }

        controller.updateLabel(label, title: "Renamed label", color: (0.5, 0.4, 0.3))
        controller.renameStatus(status, title: "Renamed status")

        for target in targets {
            let item = try XCTUnwrap(allItems(controller.binderItems).first { $0.contentTarget == target })
            XCTAssertEqual(item.labelIdentifier, labelID)
            XCTAssertEqual(item.statusIdentifier, statusID)
            XCTAssertEqual(item.labelTitle, "Renamed label")
            XCTAssertEqual(item.statusTitle, "Renamed status")
            XCTAssertNotNil(item.labelColor)
        }
    }

    func testDefinitionDeletionClearsExactReferencesIncludingTrashButPreservesDuplicateTitlesAndOtherProjects() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Delete definitions")
        let label = try XCTUnwrap(controller.addLabel(title: "Shared title"))
        let duplicateLabel = try XCTUnwrap(controller.addLabel(title: "Shared title"))
        let status = try XCTUnwrap(controller.addStatus(title: "Shared status"))
        let duplicateStatus = try XCTUnwrap(controller.addStatus(title: "Shared status"))
        let labelID = label.id
        let statusID = status.id
        let labelIdentifier = label.sourceIdentifier
        let statusIdentifier = status.sourceIdentifier
        let document = try narrativeScene(in: project)
        let trashed = try controller.addResearchDocument(title: "To trash")
        let imported = try makeImportedCharacter(in: controller, project: project)
        let entity = try controller.addStoryBibleEntry(named: "Exact refs", category: .places)
        let duplicateEntity = try controller.addStoryBibleEntry(named: "Other refs", category: .places)
        let duplicateDocument = try controller.addResearchDocument(title: "Other document refs")
        for target in [BinderContentTarget.document(document.id), .document(trashed.id),
                       .semanticEntity(imported.entity.id), .semanticEntity(entity.id)] {
            try controller.setContentLabel(labelIdentifier, for: target)
            try controller.setContentStatus(statusIdentifier, for: target)
        }
        for target in [BinderContentTarget.semanticEntity(duplicateEntity.id), .document(duplicateDocument.id)] {
            try controller.setContentLabel(duplicateLabel.sourceIdentifier, for: target)
            try controller.setContentStatus(duplicateStatus.sourceIdentifier, for: target)
        }
        controller.trashDocument(trashed.id)
        let foreignProject = try controller.createProject(title: "Independent definitions")
        let foreignEntity = try controller.addStoryBibleEntry(named: "Foreign", category: .places)
        let foreignDocument = try narrativeScene(in: foreignProject)
        foreignEntity.labelIdentifier = labelIdentifier
        foreignEntity.statusIdentifier = statusIdentifier
        foreignDocument.labelIdentifier = labelIdentifier
        foreignDocument.statusIdentifier = statusIdentifier
        try controller.store.save()
        controller.selectProject(project.id)
        controller.labelFilter = labelIdentifier
        controller.statusFilter = statusIdentifier

        controller.deleteLabel(label)
        controller.deleteStatus(status)

        XCTAssertNil(controller.lastError)
        XCTAssertNil(controller.labelFilter)
        XCTAssertNil(controller.statusFilter)
        XCTAssertNil(try controller.store.labelDefinitions.fetch(id: labelID))
        XCTAssertNil(try controller.store.statusDefinitions.fetch(id: statusID))
        for document in [document, trashed, imported.document] {
            XCTAssertNil(document.labelIdentifier)
            XCTAssertNil(document.statusIdentifier)
        }
        XCTAssertNil(entity.labelIdentifier)
        XCTAssertNil(entity.statusIdentifier)
        XCTAssertEqual(duplicateEntity.labelIdentifier, duplicateLabel.sourceIdentifier)
        XCTAssertEqual(duplicateEntity.statusIdentifier, duplicateStatus.sourceIdentifier)
        XCTAssertEqual(duplicateDocument.labelIdentifier, duplicateLabel.sourceIdentifier)
        XCTAssertEqual(duplicateDocument.statusIdentifier, duplicateStatus.sourceIdentifier)
        XCTAssertEqual(foreignEntity.labelIdentifier, labelIdentifier)
        XCTAssertEqual(foreignEntity.statusIdentifier, statusIdentifier)
        XCTAssertEqual(foreignDocument.labelIdentifier, labelIdentifier)
        XCTAssertEqual(foreignDocument.statusIdentifier, statusIdentifier)
        XCTAssertTrue(controller.isDocumentTrashed(trashed.id))
    }

    func testMetadataFiltersIncludeNativeAndImportedEntriesAndKeepMatchingDocumentAncestors() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Filter fixtures")
        let scene = try narrativeScene(in: project)
        let parent = try XCTUnwrap(scene.parent)
        let entity = try controller.addStoryBibleEntry(named: "Matching place", category: .places)
        let excluded = try controller.addStoryBibleEntry(named: "Excluded place", category: .places)
        let imported = try makeImportedCharacter(in: controller, project: project)
        let label = try XCTUnwrap(controller.addLabel(title: "Blue"))
        let equivalentLabel = try XCTUnwrap(controller.addLabel(title: "Blue"))
        let status = try XCTUnwrap(controller.addStatus(title: "Ready"))
        let equivalentStatus = try XCTUnwrap(controller.addStatus(title: "Ready"))
        for target in [BinderContentTarget.document(scene.id), .semanticEntity(entity.id)] {
            try controller.setContentLabel(label.sourceIdentifier, for: target)
            try controller.setContentStatus(status.sourceIdentifier, for: target)
        }
        try controller.setContentLabel(equivalentLabel.sourceIdentifier, for: .semanticEntity(imported.entity.id))
        try controller.setContentStatus(equivalentStatus.sourceIdentifier, for: .semanticEntity(imported.entity.id))
        try controller.setContentLabel(label.sourceIdentifier, for: .semanticEntity(excluded.id))
        controller.labelFilter = label.sourceIdentifier
        controller.statusFilter = status.sourceIdentifier

        let targets = Set(allItems(controller.displayedBinderItems).compactMap(\.contentTarget))
        XCTAssertTrue(targets.contains(.document(scene.id)))
        XCTAssertTrue(targets.contains(.document(parent.id)))
        XCTAssertTrue(targets.contains(.document(imported.document.id)))
        XCTAssertTrue(targets.contains(.semanticEntity(entity.id)))
        XCTAssertFalse(targets.contains(.semanticEntity(excluded.id)))
        controller.statusFilter = nil
        XCTAssertTrue(allItems(controller.displayedBinderItems).contains { $0.contentTarget == .semanticEntity(excluded.id) })
        controller.labelFilter = nil
        XCTAssertEqual(allItems(controller.displayedBinderItems).count, allItems(controller.binderItems).count)
    }

    func testLegacyOrderThenEntityReorderingAndNewEntryAppend() throws {
        let controller = try makeController()
        _ = try controller.createProject(title: "Entity ordering")
        let zulu = try controller.addStoryBibleEntry(named: "Zulu", category: .places)
        let alpha = try controller.addStoryBibleEntry(named: "Alpha", category: .places)
        let middle = try controller.addStoryBibleEntry(named: "Middle", category: .places)
        XCTAssertEqual(targets(in: .places, controller), [.semanticEntity(alpha.id), .semanticEntity(middle.id), .semanticEntity(zulu.id)])
        XCTAssertTrue([zulu, alpha, middle].allSatisfy { $0.storyBibleOrderIndex == nil })

        try controller.moveContent(.semanticEntity(zulu.id), offset: -1)
        try controller.moveContent(.semanticEntity(zulu.id), offset: -1)
        XCTAssertEqual(targets(in: .places, controller), [.semanticEntity(zulu.id), .semanticEntity(alpha.id), .semanticEntity(middle.id)])
        try controller.moveContent(.semanticEntity(zulu.id), offset: 1)
        XCTAssertEqual(targets(in: .places, controller), [.semanticEntity(alpha.id), .semanticEntity(zulu.id), .semanticEntity(middle.id)])
        XCTAssertEqual([alpha, zulu, middle].map { $0.storyBibleOrderIndex?.int64Value }, [0, 1, 2])
        middle.canonicalName = "AAA renamed"
        try controller.store.save()
        controller.refresh()
        XCTAssertEqual(targets(in: .places, controller), [.semanticEntity(alpha.id), .semanticEntity(zulu.id), .semanticEntity(middle.id)])
        let appended = try controller.addStoryBibleEntry(named: "A new entry", category: .places)
        XCTAssertEqual(targets(in: .places, controller).last, .semanticEntity(appended.id))
        XCTAssertEqual(appended.storyBibleOrderIndex?.int64Value, 3)
    }

    func testMixedDocumentEntityReorderingInterleavesAndPreservesDocumentSiblingOrder() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Mixed category")
        let beta = try controller.addStoryBibleEntry(named: "Beta", category: .places)
        let alpha = try controller.addStoryBibleEntry(named: "Alpha", category: .places)
        let first = try makeDocument(in: controller, project: project, title: "First document", category: .places)
        let second = try makeDocument(in: controller, project: project, title: "Second document", category: .places)
        let originalOrders = [first.orderIndex, second.orderIndex]
        XCTAssertEqual(targets(in: .places, controller), [.semanticEntity(alpha.id), .semanticEntity(beta.id), .document(first.id), .document(second.id)])

        try controller.moveContent(.document(second.id), relativeTo: .semanticEntity(alpha.id), position: .before)
        try controller.moveContent(.document(first.id), relativeTo: .semanticEntity(alpha.id), position: .after)

        XCTAssertEqual(targets(in: .places, controller), [.document(second.id), .semanticEntity(alpha.id), .document(first.id), .semanticEntity(beta.id)])
        XCTAssertEqual([second.storyBibleOrderIndex, alpha.storyBibleOrderIndex, first.storyBibleOrderIndex, beta.storyBibleOrderIndex].map { $0?.int64Value },
                       [0, 1, 2, 3])
        XCTAssertEqual([first.orderIndex, second.orderIndex], originalOrders)
        controller.refresh()
        XCTAssertEqual(targets(in: .places, controller), [.document(second.id), .semanticEntity(alpha.id), .document(first.id), .semanticEntity(beta.id)])
    }

    func testImportedCharacterOrderingUsesDocumentExactlyOnce() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Imported ordering")
        let native = try controller.addStoryBibleEntry(named: "Native", category: .people)
        let imported = try makeImportedCharacter(in: controller, project: project)
        XCTAssertEqual(targets(in: .people, controller), [.semanticEntity(native.id), .document(imported.document.id)])

        try controller.moveContent(.semanticEntity(imported.entity.id), relativeTo: .semanticEntity(native.id), position: .before)

        XCTAssertEqual(targets(in: .people, controller), [.document(imported.document.id), .semanticEntity(native.id)])
        XCTAssertEqual(imported.document.storyBibleOrderIndex?.int64Value, 0)
        XCTAssertNil(imported.entity.storyBibleOrderIndex)
        try controller.moveContent(controller.contentTarget(for: imported.entity), offset: 1)
        XCTAssertEqual(targets(in: .people, controller), [.semanticEntity(native.id), .document(imported.document.id)])
    }

    func testEntityCategoryAndNestingRestrictionsDoNotMutateOrderOrKind() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Invalid moves")
        let place = try controller.addStoryBibleEntry(named: "Place", category: .places)
        let otherPlace = try controller.addStoryBibleEntry(named: "Other place", category: .places)
        let character = try controller.addStoryBibleEntry(named: "Character", category: .people)
        let folder = try makeDocument(in: controller, project: project, title: "Place folder", category: .places)
        let before = targets(in: .places, controller)
        for position in [DropPosition.before, .after, .inside] {
            XCTAssertThrowsError(try controller.moveContent(.semanticEntity(place.id), relativeTo: .semanticEntity(character.id), position: position))
        }
        XCTAssertThrowsError(try controller.moveContent(.semanticEntity(place.id), relativeTo: .document(folder.id), position: .inside))
        XCTAssertThrowsError(try controller.moveContent(.document(folder.id), relativeTo: .semanticEntity(place.id), position: .inside))
        XCTAssertThrowsError(try controller.moveContent(.semanticEntity(place.id), relativeTo: .semanticEntity(place.id), position: .before))
        for category in StoryBibleCategory.allCases where category != .places {
            XCTAssertThrowsError(try controller.moveContent(.semanticEntity(place.id), toStoryBibleCategory: category))
        }
        XCTAssertEqual(targets(in: .places, controller), before)
        XCTAssertEqual(place.kind, SemanticEntityKind.location.rawValue)
        XCTAssertNil(place.storyBibleOrderIndex)
        try controller.moveContent(.semanticEntity(otherPlace.id), toStoryBibleCategory: .places)
        XCTAssertEqual(targets(in: .places, controller).last, .semanticEntity(otherPlace.id))
    }

    func testOffsetBoundariesAndInvalidOffsetsRejectWithoutReordering() throws {
        let controller = try makeController()
        _ = try controller.createProject(title: "Movement boundaries")
        let first = try controller.addStoryBibleEntry(named: "Alpha", category: .places)
        let last = try controller.addStoryBibleEntry(named: "Zulu", category: .places)
        let firstTarget = BinderContentTarget.semanticEntity(first.id)
        let lastTarget = BinderContentTarget.semanticEntity(last.id)
        XCTAssertFalse(controller.canMoveContent(firstTarget, offset: -1))
        XCTAssertTrue(controller.canMoveContent(firstTarget, offset: 1))
        XCTAssertTrue(controller.canMoveContent(lastTarget, offset: -1))
        XCTAssertFalse(controller.canMoveContent(lastTarget, offset: 1))
        assertContentError(.movementBoundary) { try controller.moveContent(firstTarget, offset: -1) }
        assertContentError(.movementBoundary) { try controller.moveContent(lastTarget, offset: 1) }
        for offset in [0, 2, -2, Int.max] {
            XCTAssertFalse(controller.canMoveContent(firstTarget, offset: offset))
            assertContentError(.movementBoundary) { try controller.moveContent(firstTarget, offset: offset) }
        }
        XCTAssertFalse(controller.canMoveContent(.semanticEntity(UUID()), offset: 1))
        assertContentError(.movementBoundary) { try controller.moveContent(.document(UUID()), offset: 1) }
        XCTAssertEqual(targets(in: .places, controller), [firstTarget, lastTarget])
        XCTAssertNil(first.storyBibleOrderIndex)
        XCTAssertNil(last.storyBibleOrderIndex)
    }

    func testOffsetIntegerMinimumIsRejectedWithoutOverflow() throws {
        let controller = try makeController()
        _ = try controller.createProject(title: "Extreme offset")
        let entity = try controller.addStoryBibleEntry(named: "Entry", category: .places)
        let target = BinderContentTarget.semanticEntity(entity.id)
        XCTAssertFalse(controller.canMoveContent(target, offset: Int.min))
        assertContentError(.movementBoundary) { try controller.moveContent(target, offset: Int.min) }
    }

    func testAllMovementEntryPointsRejectSearchAndMetadataFiltersButMetadataRemainsEditable() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Filtered movement")
        let first = try controller.addStoryBibleEntry(named: "Alpha", category: .places)
        let second = try controller.addStoryBibleEntry(named: "Beta", category: .places)
        let document = try makeDocument(in: controller, project: project, title: "Folder", category: .places)
        let label = try XCTUnwrap(controller.addLabel(title: "Filter label"))
        let status = try XCTUnwrap(controller.addStatus(title: "Filter status"))
        for filter in 0..<3 {
            controller.binderSearchText = filter == 0 ? "Alpha" : ""
            controller.labelFilter = filter == 1 ? label.sourceIdentifier : nil
            controller.statusFilter = filter == 2 ? status.sourceIdentifier : nil
            XCTAssertFalse(controller.canReorderBinder)
            XCTAssertFalse(controller.canMoveContent(.semanticEntity(first.id), offset: 1))
            assertContentError(.filteredMovement) { try controller.moveContent(.semanticEntity(first.id), offset: 1) }
            assertContentError(.filteredMovement) {
                try controller.moveContent(.semanticEntity(first.id), relativeTo: .semanticEntity(second.id), position: .after)
            }
            assertContentError(.filteredMovement) {
                try controller.moveContent(.document(document.id), toStoryBibleCategory: .research)
            }
            assertContentError(.filteredMovement) {
                try controller.moveDocument(document.id, relativeTo: document.id, position: .inside)
            }
            try controller.setContentLabel(label.sourceIdentifier, for: .semanticEntity(first.id))
            try controller.setContentStatus(status.sourceIdentifier, for: .semanticEntity(first.id))
            XCTAssertNil(first.storyBibleOrderIndex)
        }
        controller.binderSearchText = " \n\t "
        controller.labelFilter = nil
        controller.statusFilter = nil
        XCTAssertTrue(controller.canReorderBinder)
        XCTAssertTrue(controller.canMoveContent(.semanticEntity(first.id), offset: 1))
    }

    func testDocumentNestingReorderingAndCyclePreventionPreserveWordTotals() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Hierarchy")
        let scene = try narrativeScene(in: project)
        let novel = try XCTUnwrap(scene.parent)
        let chapter = try controller.addDocument(title: "Chapter", kind: .folder, parentID: novel.id)
        let second = try controller.addDocument(title: "Second", kind: .text, parentID: novel.id)
        scene.plainText = "one two three"
        scene.ownWordCount = 3
        scene.actualWordCount = 3
        second.plainText = "four five"
        second.ownWordCount = 2
        second.actualWordCount = 2
        novel.actualWordCount = 5
        novel.parent?.actualWordCount = 5
        try controller.store.save()
        controller.refresh()
        controller.selection = .document(scene.id)

        try controller.moveContent(.document(scene.id), relativeTo: .document(chapter.id), position: .inside)
        XCTAssertEqual(scene.parent?.id, chapter.id)
        XCTAssertEqual(chapter.actualWordCount, 3)
        XCTAssertEqual(novel.actualWordCount, 5)
        XCTAssertEqual(controller.selection, .document(scene.id))
        XCTAssertThrowsError(try controller.moveContent(.document(chapter.id), relativeTo: .document(scene.id), position: .inside))
        XCTAssertThrowsError(try controller.moveContent(.document(novel.id), relativeTo: .document(chapter.id), position: .inside))
        XCTAssertEqual(scene.parent?.id, chapter.id)
        XCTAssertEqual(chapter.parent?.id, novel.id)
        try controller.moveContent(.document(scene.id), relativeTo: .document(second.id), position: .before)
        XCTAssertEqual(scene.parent?.id, novel.id)
        XCTAssertEqual(novel.orderedChildren.map(\.id), [chapter.id, scene.id, second.id])
        XCTAssertEqual(chapter.actualWordCount, 0)
        XCTAssertEqual(novel.actualWordCount, 5)
        try controller.moveContent(.document(scene.id), offset: 1)
        XCTAssertEqual(novel.orderedChildren.map(\.id), [chapter.id, second.id, scene.id])
        XCTAssertEqual(novel.orderedChildren.map(\.orderIndex), [0, 1, 2])
        XCTAssertEqual(scene.plainText, "one two three")
    }

    func testDocumentCategoryTransitionsClearStaleMarkersAndRollups() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Category transitions")
        let scene = try narrativeScene(in: project)
        let novel = try XCTUnwrap(scene.parent)
        scene.plainText = "one two three"
        scene.ownWordCount = 3
        scene.actualWordCount = 3
        novel.actualWordCount = 3
        novel.parent?.actualWordCount = 3
        let place = try controller.addStoryBibleEntry(named: "Place", category: .places)
        try controller.store.save()

        try controller.moveContent(.document(scene.id), relativeTo: .semanticEntity(place.id), position: .before)
        XCTAssertNil(scene.parent)
        XCTAssertEqual(controller.storyBibleCategory(for: scene), .places)
        XCTAssertEqual(novel.actualWordCount, 0)
        XCTAssertEqual(targets(in: .places, controller), [.document(scene.id), .semanticEntity(place.id)])
        try controller.moveContent(.document(scene.id), toStoryBibleCategory: .research)
        XCTAssertEqual(controller.storyBibleCategory(for: scene), .research)
        XCTAssertFalse(targets(in: .places, controller).contains(.document(scene.id)))
        XCTAssertTrue(targets(in: .research, controller).contains(.document(scene.id)))
        try controller.moveContent(.document(scene.id), relativeTo: .document(novel.id), position: .inside)
        XCTAssertEqual(scene.parent?.id, novel.id)
        XCTAssertNil(scene.sectionTypeIdentifier)
        XCTAssertNil(scene.storyBibleOrderIndex)
        XCTAssertNil(controller.storyBibleCategory(for: scene))
        XCTAssertFalse(targets(in: .research, controller).contains(.document(scene.id)))
        XCTAssertEqual(novel.actualWordCount, 3)
        XCTAssertEqual(novel.parent?.actualWordCount, 3)
        XCTAssertEqual(scene.actualWordCount, 3)
    }

    func testDocumentOnlyCategoryReorderingAndAppendingPreserveHierarchy() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Research ordering")
        let first = try controller.addResearchDocument(title: "First")
        let second = try controller.addResearchDocument(title: "Second")
        let child = try makeDocument(in: controller, project: project, title: "Child", parent: first)
        try controller.moveContent(.document(second.id), relativeTo: .document(first.id), position: .before)
        XCTAssertEqual(targets(in: .research, controller), [.document(second.id), .document(first.id)])
        XCTAssertEqual(child.parent?.id, first.id)
        XCTAssertEqual(first.orderedChildren.map(\.id), [child.id])
        let third = try controller.addResearchDocument(title: "Third")
        XCTAssertEqual(targets(in: .research, controller), [.document(second.id), .document(first.id), .document(third.id)])
        controller.trashDocument(second.id)
        XCTAssertFalse(targets(in: .research, controller).contains(.document(second.id)))
        controller.restoreDocument(second.id)
        XCTAssertEqual(targets(in: .research, controller), [.document(second.id), .document(first.id), .document(third.id)])
    }

    func testNestedDocumentMovesBetweenCategoryRootsAndBackToNarrativeRoot() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Root transitions")
        let scene = try narrativeScene(in: project)
        let narrative = try XCTUnwrap(scene.ancestors.last)
        let research = try controller.addResearchDocument(title: "Research folder")
        let places = try makeDocument(in: controller, project: project, title: "Places folder", category: .places)
        let nested = try makeDocument(in: controller, project: project, title: "Nested folder", parent: research)
        let descendant = try makeDocument(in: controller, project: project, title: "Descendant", parent: nested)
        XCTAssertEqual(controller.storyBibleCategory(for: nested), .research)

        try controller.moveContent(.document(nested.id), relativeTo: .document(places.id), position: .before)
        XCTAssertNil(nested.parent)
        XCTAssertEqual(controller.storyBibleCategory(for: nested), .places)
        XCTAssertEqual(controller.storyBibleCategory(for: descendant), .places)
        XCTAssertEqual(targets(in: .places, controller), [.document(nested.id), .document(places.id)])
        XCTAssertTrue(research.children.isEmpty)
        try controller.moveContent(.document(nested.id), relativeTo: .document(narrative.id), position: .after)
        XCTAssertNil(nested.parent)
        XCTAssertNil(controller.storyBibleCategory(for: nested))
        XCTAssertNil(controller.storyBibleCategory(for: descendant))
        XCTAssertNil(nested.storyBibleOrderIndex)
        XCTAssertFalse(targets(in: .places, controller).contains(.document(nested.id)))
        XCTAssertEqual(descendant.parent?.id, nested.id)
        let narrativeItem = try XCTUnwrap(controller.binderItems.first { $0.kind == .narrative })
        XCTAssertTrue(allItems(narrativeItem.children ?? []).contains { $0.contentTarget == .document(nested.id) })
    }

    func testEqualExplicitPositionsUseStableUUIDTieBreaker() throws {
        let controller = try makeController()
        let project = try controller.createProject(title: "Stable order")
        let entity = try controller.addStoryBibleEntry(named: "Same title", category: .places)
        let document = try makeDocument(in: controller, project: project, title: "Same title", category: .places)
        entity.storyBibleOrderIndex = 7
        document.storyBibleOrderIndex = 7
        try controller.store.save()
        controller.refresh()
        let initial = targets(in: .places, controller)
        let expected: [BinderContentTarget] = [.semanticEntity(entity.id), .document(document.id)]
            .sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(initial, expected)
        entity.canonicalName = "A changed name"
        document.title = "Z changed title"
        try controller.store.save()
        controller.refresh()
        XCTAssertEqual(targets(in: .places, controller), expected)
    }

    func testMetadataMixedOrderAndDeletionPersistAfterClosingAndReopeningDiskStore() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/content-management-tests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("content.sqlite")
        let preferences = try makePreferences()
        let originalStore = try AuthorDataStore(storeURL: url)
        defer { try? close(originalStore) }
        let controller = WorkspaceController(store: originalStore, projectListPreferences: preferences)
        let project = try controller.createProject(title: "Persistent synthetic project")
        let projectID = project.id
        let entity = try controller.addStoryBibleEntry(named: "Place", category: .places)
        let document = try makeDocument(in: controller, project: project, title: "Place notes", category: .places)
        let imported = try makeImportedCharacter(in: controller, project: project)
        let deletedImported = try makeImportedCharacter(in: controller, project: project)
        let deletedImportedEntityID = deletedImported.entity.id
        let deletedImportedProfileID = deletedImported.profile.id
        let deletedImportedDocumentID = deletedImported.document.id
        let deleted = try controller.addStoryBibleEntry(named: "Deleted entry", category: .artifacts)
        let deletedID = deleted.id
        let deletedCardID = try XCTUnwrap(deleted.storyBibleCard?.id)
        let gallery = makeGalleryItem(in: controller, project: project, entity: deleted)
        let galleryID = gallery.id
        let label = try XCTUnwrap(controller.addLabel(title: "Persisted label"))
        let status = try XCTUnwrap(controller.addStatus(title: "Persisted status"))
        let labelIdentifier = label.sourceIdentifier
        let statusIdentifier = status.sourceIdentifier
        let entityID = entity.id
        let documentID = document.id
        let importedEntityID = imported.entity.id
        let importedDocumentID = imported.document.id
        for target in [BinderContentTarget.semanticEntity(entityID), .document(documentID), .semanticEntity(importedEntityID)] {
            try controller.setContentLabel(labelIdentifier, for: target)
            try controller.setContentStatus(statusIdentifier, for: target)
        }
        try controller.moveContent(.document(documentID), relativeTo: .semanticEntity(entityID), position: .before)
        try controller.deleteSemanticEntity(deletedID)
        try controller.deleteSemanticEntity(deletedImportedEntityID)
        controller.flushPendingChanges()
        try close(originalStore)

        let reopenedStore = try AuthorDataStore(storeURL: url)
        defer { try? close(reopenedStore) }
        let reopened = WorkspaceController(store: reopenedStore, projectListPreferences: preferences)
        reopened.selectProject(projectID)
        XCTAssertEqual(targets(in: .places, reopened), [.document(documentID), .semanticEntity(entityID)])
        for target in [BinderContentTarget.semanticEntity(entityID), .document(documentID), .semanticEntity(importedEntityID)] {
            XCTAssertEqual(try reopened.contentMetadata(for: target).labelIdentifier, labelIdentifier)
            XCTAssertEqual(try reopened.contentMetadata(for: target).statusIdentifier, statusIdentifier)
        }
        XCTAssertEqual(try reopenedStore.documents.require(id: importedDocumentID).labelIdentifier, labelIdentifier)
        XCTAssertNil(try reopenedStore.semanticEntities.require(id: importedEntityID).labelIdentifier)
        XCTAssertNil(try reopenedStore.semanticEntities.fetch(id: deletedID))
        XCTAssertNil(try reopenedStore.storyBibleCards.fetch(id: deletedCardID))
        XCTAssertNil(try reopenedStore.semanticEntities.fetch(id: deletedImportedEntityID))
        XCTAssertNil(try reopenedStore.characterProfiles.fetch(id: deletedImportedProfileID))
        XCTAssertNil(try reopenedStore.documents.fetch(id: deletedImportedDocumentID))
        XCTAssertNil(try reopenedStore.galleryItems.require(id: galleryID).semanticEntity)
        XCTAssertEqual(try reopenedStore.galleryItems.require(id: galleryID).resource.data, Data([1, 2, 3, 4]))
        try reopened.setContentLabel(nil, for: .semanticEntity(entityID))
        try reopened.setContentStatus(nil, for: .document(documentID))
        try close(reopenedStore)

        let finalStore = try AuthorDataStore(storeURL: url)
        defer { try? close(finalStore) }
        XCTAssertNil(try finalStore.semanticEntities.require(id: entityID).labelIdentifier)
        XCTAssertEqual(try finalStore.semanticEntities.require(id: entityID).statusIdentifier, statusIdentifier)
        XCTAssertNil(try finalStore.documents.require(id: documentID).statusIdentifier)
        XCTAssertEqual(try finalStore.documents.require(id: documentID).labelIdentifier, labelIdentifier)
    }

    func testTypedDragPayloadRoundTripsBothTargetsAndCodableRepresentation() throws {
        let projectID = UUID()
        let id = UUID()
        for target in [BinderContentTarget.document(id), .semanticEntity(id)] {
            let payload = BinderDragPayload(projectID: projectID, target: target)
            let decoded = try BinderDragPayload.decode(payload.encoded)
            XCTAssertEqual(decoded.projectID, projectID)
            XCTAssertEqual(decoded.target, target)
            XCTAssertEqual(decoded.target.id, id)
            XCTAssertEqual(decoded.encoded, payload.encoded)
            let json = try JSONEncoder().encode(payload)
            let jsonDecoded = try JSONDecoder().decode(BinderDragPayload.self, from: json)
            XCTAssertEqual(jsonDecoded.projectID, projectID)
            XCTAssertEqual(jsonDecoded.target, target)
        }
        XCTAssertNotEqual(BinderContentTarget.document(id), .semanticEntity(id))
        XCTAssertEqual(Set([BinderContentTarget.document(id), .semanticEntity(id)]).count, 2)
    }

    func testTypedDragPayloadRejectsMalformedValues() throws {
        let project = UUID().uuidString
        let item = UUID().uuidString
        let valid = "inkstone:\(project):document:\(item)"
        let malformed = [
            "", item, "inkstone", "other:\(project):document:\(item)",
            "inkstone:bad:document:\(item)", "inkstone:\(project):document:bad",
            "inkstone:\(project):unknown:\(item)", "inkstone:\(project):Document:\(item)",
            "inkstone:\(project):document", "\(valid):extra",
            ":\(valid)", "\(valid):", "inkstone::\(project):document:\(item)",
            "inkstone:\(project)::document:\(item)", "inkstone:\(project):document::\(item)",
            "inkstone:\(project):document:", "inkstone::document:\(item)"
        ]
        for value in malformed {
            assertContentError(.invalidDrag, message: value) { _ = try BinderDragPayload.decode(value) }
        }
        XCTAssertThrowsError(try JSONDecoder().decode(BinderDragPayload.self, from: Data("{}".utf8)))
    }

    private func makePreferences() throws -> UserDefaults {
        let name = "ContentManagementTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return preferences
    }

    private func makeController() throws -> WorkspaceController {
        WorkspaceController(store: try AuthorDataStore(inMemory: true), projectListPreferences: try makePreferences())
    }

    private func narrativeScene(in project: WritingProject) throws -> Document {
        try XCTUnwrap(project.documents.first { $0.narrativeType == NarrativeType.scene.rawValue })
    }

    private func makeDocument(
        in controller: WorkspaceController,
        project: WritingProject,
        title: String,
        category: StoryBibleCategory? = nil,
        parent: Document? = nil
    ) throws -> Document {
        let document = controller.store.documents.create {
            $0.sourceIdentifier = "synthetic.\(UUID().uuidString)"
            $0.title = title
            $0.kind = DocumentKind.folder.rawValue
            $0.orderIndex = Int64(project.documents.count)
            $0.createdAt = Date()
            $0.modifiedAt = Date()
            $0.project = project
            $0.parent = parent
            $0.sectionTypeIdentifier = category.map { "storyBible.\($0.id)" }
        }
        try controller.store.save()
        controller.refresh()
        return document
    }

    private func makeImportedCharacter(
        in controller: WorkspaceController,
        project: WritingProject
    ) throws -> (entity: SemanticEntity, profile: CharacterProfile, document: Document) {
        let entity = try controller.addStoryBibleEntry(named: "Ira Finch", category: .people)
        let profile = try XCTUnwrap(entity.characterProfile)
        let document = try makeDocument(in: controller, project: project, title: "Ira Finch", category: .people)
        document.kind = DocumentKind.text.rawValue
        document.plainText = "An original synthetic character dossier."
        entity.source = ProvenanceAgent.sourceImport.rawValue
        profile.source = ProvenanceAgent.sourceImport.rawValue
        profile.sourceDocument = document
        try controller.store.save()
        controller.refresh()
        return (entity, profile, document)
    }

    private func makeGalleryItem(
        in controller: WorkspaceController,
        project: WritingProject,
        entity: SemanticEntity,
        sourceDocument: Document? = nil
    ) -> GalleryItem {
        let resource = controller.store.resources.create {
            $0.project = project
            $0.sourcePath = "synthetic-image.png"
            $0.role = "gallery"
            $0.mediaType = "image/png"
            $0.byteCount = 4
            $0.sha256 = "synthetic"
            $0.data = Data([1, 2, 3, 4])
        }
        return controller.store.galleryItems.create {
            $0.title = "Synthetic gallery image"
            $0.source = "human"
            $0.createdAt = Date()
            $0.modifiedAt = Date()
            $0.project = project
            $0.resource = resource
            $0.semanticEntity = entity
            $0.sourceDocument = sourceDocument
        }
    }

    private func allItems(_ items: [BinderItem]) -> [BinderItem] {
        items.flatMap { [$0] + allItems($0.children ?? []) }
    }

    private func targets(in category: StoryBibleCategory, _ controller: WorkspaceController) -> [BinderContentTarget] {
        controller.storyBibleItems(in: category).compactMap(\.contentTarget)
    }

    private func assertContentError(
        _ expected: ContentManagementError,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), message, file: file, line: line) { error in
            XCTAssertTrue(error is ContentManagementError, "\(error)", file: file, line: line)
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription, message, file: file, line: line)
        }
    }

    private func close(_ store: AuthorDataStore) throws {
        store.context.reset()
        for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
            try store.container.persistentStoreCoordinator.remove(persistentStore)
        }
    }
}
