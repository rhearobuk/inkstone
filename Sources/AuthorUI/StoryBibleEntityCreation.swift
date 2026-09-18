import AuthorData
import Foundation

struct StoryBibleEntityCreationResult {
    let entity: SemanticEntity
    let card: StoryBibleCard
    let profile: CharacterProfile?
}

@MainActor
func createStoryBibleEntity(
    in store: AuthorDataStore,
    project: WritingProject,
    name: String,
    kind: SemanticEntityKind,
    source: ProvenanceAgent,
    at now: Date = Date()
) -> StoryBibleEntityCreationResult {
    let entity = store.semanticEntities.create {
        $0.canonicalName = name
        $0.kind = kind.rawValue
        $0.source = source.rawValue
        $0.createdAt = now
        $0.modifiedAt = now
        $0.project = project
    }
    let card = store.storyBibleCards.create {
        $0.createdAt = now
        $0.modifiedAt = now
        $0.project = project
        $0.semanticEntity = entity
    }

    let profile: CharacterProfile?
    if kind == .character {
        let nameComponents = name.split(whereSeparator: \.isWhitespace).map(String.init)
        profile = store.characterProfiles.create {
            $0.firstName = nameComponents.first ?? name
            $0.middleName = nameComponents.count > 2
                ? nameComponents.dropFirst().dropLast().joined(separator: " ")
                : nil
            $0.lastName = nameComponents.count > 1 ? nameComponents.last : nil
            $0.source = source.rawValue
            $0.createdAt = now
            $0.modifiedAt = now
            $0.project = project
            $0.semanticEntity = entity
        }
    } else {
        profile = nil
    }

    project.modifiedAt = now
    return StoryBibleEntityCreationResult(entity: entity, card: card, profile: profile)
}
