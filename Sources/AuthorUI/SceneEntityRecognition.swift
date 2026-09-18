import AuthorAI
import AuthorData
import Foundation

struct SceneEntityLinkSummary: Identifiable, Equatable {
    let documentID: UUID
    let documentTitle: String
    let mentionCount: Int
    let matchedTexts: [String]

    var id: UUID { documentID }
}

@MainActor
struct SceneEntityRecognitionService {
    private static let mentionSourcePrefix = "storyBible.entityReference."
    private static let supportedPassKinds: [SemanticEntityKind] = [
        .character, .organization, .location, .object, .event, .concept, .theme, .other
    ]
    private static let candidateBatchSize = 24
    private static let aliasesPerCandidate = 4

    let store: AuthorDataStore
    let recognitionClient: any StoryBibleEntityRecognitionClient

    init(
        store: AuthorDataStore,
        recognitionClient: any StoryBibleEntityRecognitionClient = AppleIntelligenceStoryBibleRecognitionClient()
    ) {
        self.store = store
        self.recognitionClient = recognitionClient
    }

    func refreshSceneLinks(for documentID: UUID, saveChanges: Bool = true) async throws {
        guard let document = try store.documents.fetch(id: documentID),
              document.narrativeType == NarrativeType.scene.rawValue else {
            return
        }

        guard let text = document.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            removeRecognizedMentions(from: document)
            if saveChanges {
                try store.save()
            }
            return
        }

        let entities = document.project.semanticEntities.filter { !$0.isDeleted }
        let matches = try await resolveMentions(in: text, entities: entities)

        removeRecognizedMentions(from: document)
        for match in matches {
            createMention(match.candidate, source: Self.mentionSourcePrefix + "appleIntelligence", entity: match.entity, document: document)
        }

        if let documentModifiedAt = document.modifiedAt {
            let projectModifiedAt = document.project.modifiedAt ?? documentModifiedAt
            document.project.modifiedAt = max(projectModifiedAt, documentModifiedAt)
        }
        if saveChanges {
            try store.save()
        }
    }

    func linkedScenes(for entity: SemanticEntity, excludingDocumentIDs: Set<UUID> = []) -> [SceneEntityLinkSummary] {
        let grouped = Dictionary(grouping: entity.mentions.filter {
            $0.document.narrativeType == NarrativeType.scene.rawValue
                && !$0.document.isDeleted
                && $0.document.project.id == entity.project.id
                && !excludingDocumentIDs.contains($0.document.id)
                && $0.source.hasPrefix(Self.mentionSourcePrefix)
        }, by: { $0.document.id })

        return grouped.values.compactMap { mentions in
            guard let document = mentions.first?.document else { return nil }
            let matchedTexts = Array(Set(mentions.map(\.surfaceText))).sorted()
            return SceneEntityLinkSummary(
                documentID: document.id,
                documentTitle: document.title,
                mentionCount: mentions.count,
                matchedTexts: matchedTexts
            )
        }
        .sorted {
            if $0.documentTitle != $1.documentTitle {
                return $0.documentTitle.localizedCaseInsensitiveCompare($1.documentTitle) == .orderedAscending
            }
            return $0.documentID.uuidString < $1.documentID.uuidString
        }
    }

    private func removeRecognizedMentions(from document: Document) {
        let recognizedMentions = document.mentions.filter { $0.source.hasPrefix(Self.mentionSourcePrefix) }
        for mention in recognizedMentions {
            store.context.delete(mention)
        }
    }

    private func createMention(
        _ candidate: CandidateMatch,
        source: String,
        entity: SemanticEntity,
        document: Document
    ) {
        store.mentions.create {
            $0.location = Int64(candidate.range.location)
            $0.length = Int64(candidate.range.length)
            $0.surfaceText = candidate.text
            $0.context = candidate.context
            $0.source = source
            $0.confidence = NSNumber(value: 0.95)
            $0.document = document
            $0.semanticEntity = entity
        }
    }

    private func resolveMentions(in text: String, entities: [SemanticEntity]) async throws -> [ResolvedCandidateMatch] {
        let nsText = text as NSString
        let entityLookup = Dictionary(uniqueKeysWithValues: entities.map { ($0.id.uuidString, $0) })
        var occupiedRanges: [NSRange] = []
        var resolved: [ResolvedCandidateMatch] = []

        for kind in Self.supportedPassKinds {
            let candidates = recognitionCandidates(in: entities, kind: kind)
            guard !candidates.isEmpty else { continue }

            var start = 0
            while start < candidates.count {
                let end = min(start + Self.candidateBatchSize, candidates.count)
                let batch = Array(candidates[start..<end])
                start = end

                let request = StoryBibleRecognitionRequest(
                    sceneText: text,
                    passLabel: recognitionPassLabel(for: kind),
                    candidates: batch
                )
                let matches = try await recognitionClient.recognizeMentions(in: request)
                for match in matches {
                    guard let entity = entityLookup[match.entityID],
                          let candidate = exactOccurrenceMatch(
                            for: match.surfaceText,
                            occurrence: match.occurrence,
                            in: nsText,
                            occupiedRanges: &occupiedRanges
                          ) else {
                        continue
                    }
                    resolved.append(ResolvedCandidateMatch(candidate: candidate, entity: entity))
                }
            }
        }

        return resolved.sorted { $0.candidate.range.location < $1.candidate.range.location }
    }

    private func recognitionCandidates(in entities: [SemanticEntity], kind: SemanticEntityKind) -> [StoryBibleRecognitionCandidate] {
        entities
            .filter { $0.kind == kind.rawValue }
            .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
            .map { entity in
                StoryBibleRecognitionCandidate(
                    id: entity.id.uuidString,
                    name: entity.canonicalName,
                    aliases: recognitionAliases(for: entity),
                    kind: entity.kind
                )
            }
    }

    private func recognitionAliases(for entity: SemanticEntity) -> [String] {
        Array(
            Set(
                entity.aliases
                    .map(\.name)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        )
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        .prefix(Self.aliasesPerCandidate)
        .map { $0 }
    }

    private func recognitionPassLabel(for kind: SemanticEntityKind) -> String {
        switch kind {
        case .character: "Characters"
        case .organization: "Organizations"
        case .location: "Places"
        case .object: "Artifacts and objects"
        case .event: "Events"
        case .concept: "Concepts"
        case .theme: "Themes"
        case .other: "Other Story Bible entities"
        case .relationship: "Relationships"
        case .timeline: "Timeline entities"
        }
    }

    private func exactOccurrenceMatch(
        for surfaceText: String,
        occurrence: Int,
        in text: NSString,
        occupiedRanges: inout [NSRange]
    ) -> CandidateMatch? {
        let normalizedSurfaceText = surfaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSurfaceText.isEmpty, occurrence > 0 else { return nil }
        let matches = literalRanges(of: normalizedSurfaceText, in: text)
        guard occurrence <= matches.count else { return nil }
        let range = matches[occurrence - 1]
        guard !occupiedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return nil }
        occupiedRanges.append(range)
        return CandidateMatch(
            text: text.substring(with: range),
            range: range,
            context: mentionContext(in: text, range: range)
        )
    }

    private func literalRanges(of phrase: String, in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < text.length {
            let searchRange = NSRange(location: searchStart, length: text.length - searchStart)
            let foundRange = text.range(
                of: phrase,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchRange
            )
            guard foundRange.location != NSNotFound else { break }
            ranges.append(foundRange)
            searchStart = foundRange.location + max(1, foundRange.length)
        }
        return ranges
    }

    private func mentionContext(in text: NSString, range: NSRange) -> String {
        let lowerBound = max(0, range.location - 24)
        let upperBound = min(text.length, range.location + range.length + 24)
        return text.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct CandidateMatch {
        let text: String
        let range: NSRange
        let context: String
    }

    private struct ResolvedCandidateMatch {
        let candidate: CandidateMatch
        let entity: SemanticEntity
    }
}
