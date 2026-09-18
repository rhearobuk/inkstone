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

        let resolvedMatches = existingEntityMatches(in: text, entities: existingEntities)
        let occupiedRanges = resolvedMatches.map(\.candidate.range)

        for resolved in resolvedMatches {
            createMention(resolved.candidate, source: Self.mentionSourcePrefix + "exactMatch", entity: resolved.entity, document: document)
        }

        for candidate in candidateMatches(in: text, excluding: occupiedRanges) {
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

    private func candidateMatches(in text: String, excluding occupiedRanges: [NSRange] = []) -> [CandidateMatch] {
        guard let regex = Self.candidateRegex else { return [] }
        let nsText = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard !occupiedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let candidate = cleanedCandidateMatch(in: nsText, range: match.range),
                  isUsefulCandidate(candidate.text) else {
                return nil
            }
            let dedupeKey = "\(candidate.range.location):\(normalized(candidate.text))"
            guard seen.insert(dedupeKey).inserted else { return nil }
            return candidate
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

    private func cleanedCandidateMatch(in text: NSString, range: NSRange) -> CandidateMatch? {
        var adjustedRange = range
        var raw = text.substring(with: adjustedRange).trimmingCharacters(in: .whitespacesAndNewlines)
        while let trailingRange = raw.range(of: #"\s+(?:of|the|and)$"#, options: .regularExpression) {
            let suffix = String(raw[trailingRange])
            raw.removeSubrange(trailingRange)
            adjustedRange.length -= (suffix as NSString).length
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !raw.isEmpty else { return nil }
        return CandidateMatch(
            text: raw,
            range: adjustedRange,
            context: mentionContext(in: text, range: adjustedRange)
        )
    }

    private func existingEntityMatches(in text: String, entities: [SemanticEntity]) -> [ResolvedCandidateMatch] {
        let nsText = text as NSString
        let searchRange = NSRange(location: 0, length: nsText.length)
        var occupiedRanges: [NSRange] = []
        var matches: [ResolvedCandidateMatch] = []
        let candidates = entities.flatMap { entity in
            ([entity.canonicalName] + entity.aliases.map(\.name)).map { (entity, $0) }
        }
        .sorted { lhs, rhs in
            let lhsLength = lhs.1.count
            let rhsLength = rhs.1.count
            if lhsLength != rhsLength { return lhsLength > rhsLength }
            return lhs.1.localizedCaseInsensitiveCompare(rhs.1) == .orderedAscending
        }

        for (entity, name) in candidates {
            guard let regex = existingEntityRegex(for: name, entity: entity) else { continue }
            for match in regex.matches(in: text, range: searchRange) {
                guard !occupiedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let candidate = cleanedCandidateMatch(in: nsText, range: match.range) else {
                    continue
                }
                occupiedRanges.append(candidate.range)
                matches.append(ResolvedCandidateMatch(candidate: candidate, entity: entity))
            }
        }

        return matches.sorted { $0.candidate.range.location < $1.candidate.range.location }
    }

    private func existingEntityRegex(for value: String, entity: SemanticEntity) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        let allowsLeadingArticle = entity.kind == SemanticEntityKind.character.rawValue ||
            supportsLeadingArticleVariant(for: value, kindHint: entity.kind)
        let pattern = allowsLeadingArticle
            ? #"\b(?:(?:[Tt]he)\s+)?"# + escaped + #"\b"#
            : #"\b"# + escaped + #"\b"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
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

    private struct ResolvedCandidateMatch {
        let candidate: CandidateMatch
        let entity: SemanticEntity
    }
}
