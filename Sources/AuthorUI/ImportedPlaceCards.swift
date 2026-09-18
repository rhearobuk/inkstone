import AuthorData
import Foundation

private let importedPlaceEntityField = NarrativeFieldDescriptor(
    key: "system.storyBible.importedPlaceEntityID",
    displayName: "Imported place entity",
    valueKind: .text
)

private enum ImportedPlaceCardError: LocalizedError {
    case invalidLink(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink(let title):
            "The saved Story Bible link for imported place \"\(title)\" is invalid. Its original document has not been changed."
        }
    }
}

extension WorkspaceController {
    func normalizeImportedPlaceCards(in project: WritingProject? = nil) throws {
        let documents = try project.map { Array($0.documents) } ?? store.documents.fetchAll()
        for document in documents where !document.isDeleted {
            let savedID = NarrativeMetadataStore.stringValue(for: importedPlaceEntityField, on: document)
            if !savedID.isEmpty && importedPlaceCard(for: document) == nil {
                throw ImportedPlaceCardError.invalidLink(document.title)
            }
        }
        var changed = false
        for document in documents where !document.isDeleted {
            guard importedPlaceCard(for: document) == nil,
                  document.kind == DocumentKind.text.rawValue,
                  !document.sourceIdentifier.isEmpty,
                  !document.sourceIdentifier.hasPrefix("native."),
                  storyBibleCategory(for: document) == .places,
                  !document.ancestors.contains(where: {
                      ["templates", "template sheets"].contains($0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
                  }) else {
                continue
            }
            let creation = createStoryBibleEntity(
                in: store,
                project: document.project,
                name: document.title,
                kind: .location,
                source: .sourceImport
            )
            creation.card.details = document.plainText
            creation.entity.summary = document.synopsis
            NarrativeMetadataStore.setValue(
                creation.entity.id.uuidString,
                for: importedPlaceEntityField,
                on: document,
                store: store
            )
            for image in document.sourceGalleryItems where image.semanticEntity == nil {
                image.semanticEntity = creation.entity
            }
            changed = true
        }
        if changed { try store.save() }
    }

    func importedPlaceCard(for document: Document) -> StoryBibleCard? {
        guard !document.isDeleted,
              let id = UUID(uuidString: NarrativeMetadataStore.stringValue(for: importedPlaceEntityField, on: document)),
              let entity = document.project.semanticEntities.first(where: { !$0.isDeleted && $0.id == id }),
              entity.kind == SemanticEntityKind.location.rawValue else { return nil }
        return entity.storyBibleCard
    }

    func importedPlaceSource(for entity: SemanticEntity) -> Document? {
        guard !entity.isDeleted, entity.kind == SemanticEntityKind.location.rawValue else { return nil }
        return entity.project.documents.first {
            !$0.isDeleted &&
                NarrativeMetadataStore.stringValue(for: importedPlaceEntityField, on: $0) == entity.id.uuidString
        }
    }

    func isStoryBibleEntityAvailable(_ entity: SemanticEntity) -> Bool {
        guard !entity.isDeleted else { return false }
        return importedPlaceSource(for: entity).map { !isDocumentTrashed($0) } ?? true
    }

    func deleteImportedPlaceCards(in document: Document) {
        let sourceDocuments = document.project.documents.filter {
            !$0.isDeleted && ($0.id == document.id || $0.ancestors.contains { $0.id == document.id })
        }
        for source in sourceDocuments {
            if let card = importedPlaceCard(for: source) {
                if selection == .storyBibleCard(card.id) || selection == .semanticEntity(card.semanticEntity.id) {
                    selection = .trash(document.project.id)
                }
                store.context.delete(card.semanticEntity)
            }
        }
    }
}
