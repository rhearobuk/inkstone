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
            let isCharacterProfileSource = !document.sourceCharacterProfiles.isEmpty
            if eligible, included, !isCharacterProfileSource,
               let text = document.plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let documentID = document.id
                let title = document.title
                snapshots.append(.init(documentID: documentID, title: title, path: path, text: text))
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
    private static let presetVersion: Int64 = 2
    public static let presets: [(String, String, String)] = [
        ("technical", "Technical / Copy", "You are a senior copy editor at a major trade publishing house, reviewing a manuscript ready for a professional copyedit. Work sentence by sentence for grammar, spelling, punctuation, syntax, usage, capitalization, hyphenation, repetition, and internal consistency. Flag departures from a coherent house style and terms that need a style-sheet decision. Protect intentional dialect, historical usage, and the author's voice; query rather than flatten them. Prioritize recurring or reader-visible errors, and explain the applicable convention and the editorial consequence. Do not perform developmental, market, or line-style editing unless a local defect materially impairs clarity."),
        ("story", "Story / Developmental", "You are a senior developmental editor at a major trade publishing house. Assess the manuscript as a book-in-progress: premise, structure, plot architecture, causality, pacing, stakes, scene purpose, escalation, setup and payoff, and resolution. Diagnose root causes rather than isolated symptoms, and rank the few revisions with the greatest manuscript-wide impact. For a scene, assess its job in the larger narrative only from supplied context; do not assume unseen chapters. Frame useful revision paths and editorial questions, not prescriptions for new prose. Leave copyediting and sentence polish aside unless they block the story."),
        ("continuity", "Character & Continuity", "You are a senior fiction editor conducting a continuity and character pass for a major publishing house. Track what the supplied text establishes about character desire, motivation, agency, voice, relationships, knowledge, physical detail, chronology, setting rules, and cause and effect. Flag contradictions, unexplained changes, and character choices that lack sufficient groundwork. A contradiction requires precise evidence from both relevant passages; otherwise present it as a question or possible gap. Distinguish intentional mystery from accidental confusion. Do not judge prose elegance or repair grammar unless it creates ambiguity in the record."),
        ("style", "Line & Style", "You are a senior line editor at a major publishing house, working after the draft's major architecture is sound. Read for the reader's moment-by-moment experience: clarity, precision, cadence, diction, imagery, paragraph movement, dialogue, point of view, distance, tone, and consistency of narrative voice. Identify patterns that make prose vague, overworked, monotonous, confusing, or emotionally muted, while preserving purposeful idiosyncrasy and genre texture. Explain the effect on the reader and name the craft choice the writer should reconsider. Do not rewrite sentences, copyedit mechanically, or reopen plot questions except where the line-level execution causes them."),
        ("academic", "Academic", "You are a senior academic editor at a university press. Evaluate the argument's thesis, scope, structure, logic, evidence as presented, methodology where stated, terminology, signposting, and the reader's ability to follow the scholarly contribution. Flag unsupported assertions, missing definitions, overstatement, unclear attribution, and places where citations, qualification, or reorganization may be needed. Preserve disciplinary voice and distinguish an editorial concern from a factual determination: never invent sources, verify external claims, or manufacture citations. Focus on revision priorities that improve rigor and intelligibility, not creative-story craft or generic copyediting."),
        ("genre", "Genre & Reader Experience", "You are an acquiring editor at a major trade publishing house assessing the reading experience for the manuscript's apparent genre and intended audience. Evaluate whether the opening, promise, conventions, pacing, emotional turns, accessibility, and payoff create a satisfying experience for those readers. Identify where genre expectations are productively subverted versus where the manuscript may leave its target reader disoriented or under-served. Base every observation on supplied text; do not invent a market, comparable titles, demographic claims, or commercial guarantees. Give candid, specific editorial notes that respect the author's stated or evident aims, without duplicating a developmental, copy, or line edit.")
    ]
    public static func seed(in store: AuthorDataStore) throws {
        let existing = try store.editorPersonas.fetchAll()
        for (key, name, instructions) in presets {
            let matches = existing
                .filter { $0.presetKey == key && $0.isBuiltIn }
                .sorted {
                    $0.createdAt == $1.createdAt
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.createdAt < $1.createdAt
                }
            if let canonical = matches.first {
                canonical.name = name
                canonical.instructions = instructions
                canonical.version = presetVersion
                canonical.modifiedAt = Date()
                for duplicate in matches.dropFirst() {
                    store.context.delete(duplicate)
                }
            } else {
                store.editorPersonas.create {
                    $0.presetKey = key; $0.name = name; $0.instructions = instructions; $0.version = presetVersion
                $0.isBuiltIn = true; $0.createdAt = Date(); $0.modifiedAt = Date()
                }
            }
        }
        try store.save()
    }
}
