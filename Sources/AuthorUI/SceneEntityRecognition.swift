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
    private static let candidateTokenPattern =
        #"(?:Mc[A-Z][a-z]+|[A-Z][a-z]+(?:['’-][A-Z][a-z]+)?|[A-Z]{2,}|(?:[A-Z]\.){2,})"#
    private static let candidateRegex = try? NSRegularExpression(
        pattern: #"\b(?:(?:[Tt]he)\s+)?"# + candidateTokenPattern + #"(?:\s+(?:"# + candidateTokenPattern + #"|of|the|and))*"#
    )
    private static let ignoredSingleWordMatches = Set([
        "A", "An", "And", "But", "For", "He", "Her", "His", "I", "It", "Its", "Mr", "Mrs",
        "Ms", "No", "Nor", "Or", "She", "So", "That", "The", "Their", "There", "They", "We",
        "You"
    ])
    private static let locationKeywords = Set([
        "Abbey", "Bay", "Bridge", "Castle", "City", "Garden", "Gate", "Harbor",
        "Harbour", "Hill", "Inn", "Island", "Keep", "Lake", "Manor", "Market",
        "Mountain", "Palace", "Park", "Port", "River", "Road", "Square", "Street", "Temple",
        "Tower", "Valley", "Village", "Wood"
    ])
    private static let organizationKeywords = Set([
        "Agency", "Alliance", "Brotherhood", "Circle", "Collective", "Company", "Council",
        "Court", "Family", "Guild", "House", "Legion", "Network", "Order", "Society", "Union"
    ])
    private static let nonCharacterKeywords = Set([
        "Amulet", "Battle", "Blade", "Book", "Case", "Crown", "Cup", "Dagger", "Festival",
        "Gem", "Journal", "Key", "Letter", "Map", "Medallion", "Orb", "Ring", "Scroll",
        "Ship", "Siege", "Storm", "Sword", "Treaty", "Trial", "War"
    ])

    let store: AuthorDataStore

    func refreshSceneLinks(for documentID: UUID, saveChanges: Bool = true) throws {
        guard let document = try store.documents.fetch(id: documentID),
              document.narrativeType == NarrativeType.scene.rawValue else {
            return
        }

        removeRecognizedMentions(from: document)
        guard let text = document.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            if saveChanges {
                try store.save()
            }
            return
        }

        let existingEntities = document.project.semanticEntities
        var entitiesByNormalizedName: [String: SemanticEntity] = [:]
        for entity in existingEntities {
            index(entity, in: &entitiesByNormalizedName)
        }

        for candidate in candidateMatches(in: text) {
            let lookupKeys = normalizedLookupKeys(for: candidate.text)
            guard !lookupKeys.isEmpty else { continue }
            let entity: SemanticEntity
            let source: String
            if let existing = lookupKeys.lazy.compactMap({ entitiesByNormalizedName[$0] }).first {
                entity = existing
                source = Self.mentionSourcePrefix + "exactMatch"
            } else {
                entity = try createEntity(
                    named: candidate.text,
                    in: document.project,
                    kind: inferredKind(for: candidate.text)
                )
                source = Self.mentionSourcePrefix + "autoCreated"
            }
            index(entity, in: &entitiesByNormalizedName)
            createMention(candidate, source: source, entity: entity, document: document)
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
            $0.confidence = NSNumber(value: source.hasSuffix("autoCreated") ? 0.75 : 0.95)
            $0.document = document
            $0.semanticEntity = entity
        }
    }

    private func createEntity(
        named name: String,
        in project: WritingProject,
        kind: SemanticEntityKind
    ) throws -> SemanticEntity {
        createStoryBibleEntity(
            in: store,
            project: project,
            name: name,
            kind: kind,
            source: .automation
        ).entity
    }

    private func index(_ entity: SemanticEntity, in lookup: inout [String: SemanticEntity]) {
        for key in normalizedLookupKeys(for: entity.canonicalName, kindHint: entity.kind) where lookup[key] == nil {
            lookup[key] = entity
        }
        for alias in entity.aliases {
            for key in normalizedLookupKeys(for: alias.name) where lookup[key] == nil {
                lookup[key] = entity
            }
        }
    }

    private func candidateMatches(in text: String) -> [CandidateMatch] {
        guard let regex = Self.candidateRegex else { return [] }
        let nsText = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let raw = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulCandidate(raw) else { return nil }
            let dedupeKey = "\(match.range.location):\(normalized(raw))"
            guard seen.insert(dedupeKey).inserted else { return nil }
            return CandidateMatch(
                text: raw,
                range: match.range,
                context: mentionContext(in: nsText, range: match.range)
            )
        }
    }

    private func isUsefulCandidate(_ value: String) -> Bool {
        let words = value.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        if words.count == 1, Self.ignoredSingleWordMatches.contains(value) {
            return false
        }
        return words.contains { word in
            word.first?.isUppercase == true
        }
    }

    private func mentionContext(in text: NSString, range: NSRange) -> String {
        let lowerBound = max(0, range.location - 24)
        let upperBound = min(text.length, range.location + range.length + 24)
        return text.substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferredKind(for name: String) -> SemanticEntityKind {
        let words = name.split(separator: " ").map(String.init)
        if words.contains(where: { Self.organizationKeywords.contains($0) }) {
            return .organization
        }
        if words.contains(where: { Self.locationKeywords.contains($0) }) {
            return .location
        }
        if isLikelyCharacterName(words) {
            return .character
        }
        return .other
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private func normalizedLookupKeys(for value: String, kindHint: String? = nil) -> [String] {
        let normalizedValue = normalized(value)
        guard !normalizedValue.isEmpty else { return [] }
        if normalizedValue.hasPrefix("the ") {
            return [normalizedValue, String(normalizedValue.dropFirst(4))]
        }
        if supportsLeadingArticleVariant(for: value, kindHint: kindHint) {
            return [normalizedValue, normalized("the \(value)")]
        }
        return [normalizedValue]
    }

    private func supportsLeadingArticleVariant(for value: String, kindHint: String?) -> Bool {
        if kindHint == SemanticEntityKind.organization.rawValue {
            return true
        }
        let words = value.split(separator: " ").map(String.init)
        return words.contains(where: { Self.organizationKeywords.contains($0) })
    }

    private func isLikelyCharacterName(_ words: [String]) -> Bool {
        guard !words.isEmpty, words.count <= 3 else { return false }
        guard !words.contains(where: { Self.nonCharacterKeywords.contains($0) }) else { return false }
        let significantWords = words.filter { !["of", "the", "and"].contains($0.lowercased()) }
        guard !significantWords.isEmpty else { return false }
        if significantWords.count == 1 {
            return false
        }
        return significantWords.allSatisfy { $0.first?.isUppercase == true }
    }

    private struct CandidateMatch {
        let text: String
        let range: NSRange
        let context: String
    }
}
