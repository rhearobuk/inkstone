import Foundation
import CryptoKit

public enum EditorialScope: String, CaseIterable, Sendable {
    case document, chapter, novel
    public var label: String {
        switch self {
        case .document: "Scene / document"
        case .chapter: "Chapter / folder and descendants"
        case .novel: "Entire novel / manuscript root"
        }
    }
}

public struct ReviewInputSnapshot: Sendable, Equatable {
    public let documentID: UUID
    public let title: String
    public let path: String
    public let text: String
    public let role: String
    public var hash: String { Self.hash(text) }
    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public init(documentID: UUID, title: String, path: String, text: String, role: String = "manuscript") {
        self.documentID = documentID; self.title = title; self.path = path; self.text = text; self.role = role
    }
}

public enum ReviewScopeError: LocalizedError {
    case invalidHierarchy, empty
    public var errorDescription: String? {
        switch self {
        case .invalidHierarchy: "The selected scope contains an invalid hierarchy or a document from another project."
        case .empty: "The selected scope contains no reviewable text."
        }
    }
}

@MainActor
public enum ReviewScopeResolver {
    public static func resolve(root: Document, project: WritingProject, scope: EditorialScope,
                               includeExcluded: Bool = false) throws -> [ReviewInputSnapshot] {
        var visited = Set<UUID>()
        var snapshots: [ReviewInputSnapshot] = []
        func visit(_ document: Document, path: String) throws {
            guard document.project.id == project.id, visited.insert(document.id).inserted else {
                throw ReviewScopeError.invalidHierarchy
            }
            let path = path.isEmpty ? document.title : path + " / " + document.title
            let eligible = [DocumentKind.text.rawValue, DocumentKind.folder.rawValue, DocumentKind.draftFolder.rawValue].contains(document.kind)
            let included = scope == .document || includeExcluded || document.includeInCompile?.boolValue != false
            if eligible, included, document.sourceCharacterProfiles.isEmpty,
               let text = document.plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                snapshots.append(.init(documentID: document.id, title: document.title, path: path, text: text))
            }
            if scope != .document {
                for child in document.orderedChildren { try visit(child, path: path) }
            }
        }
        try visit(root, path: "")
        guard !snapshots.isEmpty else { throw ReviewScopeError.empty }
        return snapshots
    }
}

@MainActor
public enum EditorPersonaLibrary {
    public static let presets: [(String, String, String)] = [
        ("technical", "Technical / Copy", "Evaluate grammar, punctuation, clarity, repetition and consistency. Preserve intentional dialect and voice."),
        ("story", "Story / Developmental", "Evaluate plot, pacing, stakes, causality, structure and payoff. Distinguish questions from demonstrated problems."),
        ("continuity", "Character & Continuity", "Evaluate character motivation, voice, relationships, chronology and contradictions. Cite both passages for contradictions."),
        ("style", "Line & Style", "Evaluate rhythm, diction, point of view and tonal consistency. Explain the effect without supplying replacement prose."),
        ("academic", "Academic", "Evaluate argument, organization, terminology and evidential gaps. Never invent citations or claim to have verified external facts."),
        ("genre", "Genre & Reader Experience", "Evaluate reader comprehension, emotional effect and genre expectations while respecting the author's intended audience and tone.")
    ]
    public static func seed(in store: AuthorDataStore) throws {
        let existing = try store.editorPersonas.fetchAll()
        for (key, name, instructions) in presets where !existing.contains(where: { $0.presetKey == key && $0.isBuiltIn }) {
            store.editorPersonas.create {
                $0.presetKey = key; $0.name = name; $0.instructions = instructions; $0.version = 1
                $0.isBuiltIn = true; $0.createdAt = Date(); $0.modifiedAt = Date()
            }
        }
        try store.save()
    }
}
