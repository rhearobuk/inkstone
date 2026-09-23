import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The narrative level selected as the root of an export.
public enum ExportScope: String, Sendable {
    case book
    case section
    case chapter
    case scene

    public var narrativeType: NarrativeType {
        NarrativeType(rawValue: rawValue)!
    }

    public var displayName: String {
        rawValue.capitalized
    }
}

/// Controls which document subtree is compiled.
public struct ExportRequest: Sendable {
    public let projectID: UUID
    public let rootDocumentID: UUID
    public let scope: ExportScope
    public let includesExcludedDocuments: Bool
    public let contactInformation: ExportContactInformation

    public init(
        projectID: UUID,
        rootDocumentID: UUID,
        scope: ExportScope,
        includesExcludedDocuments: Bool = false,
        contactInformation: ExportContactInformation = .init()
    ) {
        self.projectID = projectID
        self.rootDocumentID = rootDocumentID
        self.scope = scope
        self.includesExcludedDocuments = includesExcludedDocuments
        self.contactInformation = contactInformation
    }
}

public enum ExportCompilerError: LocalizedError, Equatable {
    case projectNotFound(UUID)
    case rootDocumentNotFound(UUID)
    case rootDoesNotBelongToProject(documentID: UUID, projectID: UUID)
    case invalidScope(expected: ExportScope, actual: String?)
    case malformedRichText(documentID: UUID, resourceID: UUID)

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "The export project \(id) was not found."
        case .rootDocumentNotFound(let id):
            return "The export root document \(id) was not found."
        case .rootDoesNotBelongToProject(let documentID, let projectID):
            return "Document \(documentID) does not belong to project \(projectID)."
        case .invalidScope(let expected, let actual):
            return "A \(expected.rawValue) export requires a \(expected.rawValue) root, not \(actual ?? "an untyped document")."
        case .malformedRichText(let documentID, let resourceID):
            return "Rich text resource \(resourceID) for document \(documentID) could not be decoded."
        }
    }
}

public struct ExportDiagnostic: Sendable, Hashable {
    public enum Kind: String, Sendable {
        case richTextFallback
    }

    public let kind: Kind
    public let documentID: UUID
    public let resourceID: UUID
    public let message: String
}

public struct ExportPublication: Sendable {
    public let scope: ExportScope
    public let rootDocumentID: UUID
    public let project: ExportProjectMetadata
    /// The containing Book, retained even for section, chapter, and scene exports.
    public let book: ExportBook?
    public let documents: [ExportDocument]
    public let diagnostics: [ExportDiagnostic]
}

public struct ExportContactInformation: Sendable {
    public let author: String?
    public let authorAddress: String?
    public let authorPhone: String?
    public let authorEmail: String?
    public let agentName: String?
    public let agency: String?
    public let agentAddress: String?
    public let agentPhone: String?
    public let agentEmail: String?

    public init(
        author: String? = nil,
        authorAddress: String? = nil,
        authorPhone: String? = nil,
        authorEmail: String? = nil,
        agentName: String? = nil,
        agency: String? = nil,
        agentAddress: String? = nil,
        agentPhone: String? = nil,
        agentEmail: String? = nil
    ) {
        self.author = author
        self.authorAddress = authorAddress
        self.authorPhone = authorPhone
        self.authorEmail = authorEmail
        self.agentName = agentName
        self.agency = agency
        self.agentAddress = agentAddress
        self.agentPhone = agentPhone
        self.agentEmail = agentEmail
    }
}

public struct ExportProjectMetadata: Sendable {
    public let title: String
    public let creator: String?
    public let author: String?
    public let createdAt: Date
    public let modifiedAt: Date
    public let contactInformation: ExportContactInformation

    public init(
        title: String,
        creator: String?,
        author: String?,
        createdAt: Date,
        modifiedAt: Date,
        contactInformation: ExportContactInformation = .init()
    ) {
        self.title = title
        self.creator = creator
        self.author = author
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contactInformation = contactInformation
    }
}

public struct ExportDocument: Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let narrativeType: NarrativeType
    public let depth: Int
    public let wordCount: Int64
    public let metadata: ExportDocumentMetadata
    public let prose: [ExportProseBlock]
}

public struct ExportDocumentMetadata: Sendable {
    public let subtitle: String?
    public let epigraph: String?
    public let povCharacter: String?
    public let location: String?
    public let storyDate: String?
    public let book: ExportBookMetadata?
}

public struct ExportBookMetadata: Sendable {
    public let subtitle: String?
    public let author: String?
    public let authorAddress: String?
    public let authorPhone: String?
    public let authorEmail: String?
    public let agentName: String?
    public let agentAddress: String?
    public let agentPhone: String?
    public let agentEmail: String?
    public let isbns: [ExportISBN]
    public let seriesName: String?
    public let volumeNumber: Int64?
    public let volumeCount: Int64?
    public let publisher: String?
    public let publicationDate: Date?
    public let copyright: String?
    public let language: String?
    public let edition: String?
    public let covers: [ExportCoverAsset]

    public init(
        subtitle: String? = nil,
        author: String? = nil,
        authorAddress: String? = nil,
        authorPhone: String? = nil,
        authorEmail: String? = nil,
        agentName: String? = nil,
        agentAddress: String? = nil,
        agentPhone: String? = nil,
        agentEmail: String? = nil,
        isbns: [ExportISBN] = [],
        seriesName: String? = nil,
        volumeNumber: Int64? = nil,
        volumeCount: Int64? = nil,
        publisher: String? = nil,
        publicationDate: Date? = nil,
        copyright: String? = nil,
        language: String? = nil,
        edition: String? = nil,
        covers: [ExportCoverAsset] = []
    ) {
        self.subtitle = subtitle
        self.author = author
        self.authorAddress = authorAddress
        self.authorPhone = authorPhone
        self.authorEmail = authorEmail
        self.agentName = agentName
        self.agentAddress = agentAddress
        self.agentPhone = agentPhone
        self.agentEmail = agentEmail
        self.isbns = isbns
        self.seriesName = seriesName
        self.volumeNumber = volumeNumber
        self.volumeCount = volumeCount
        self.publisher = publisher
        self.publicationDate = publicationDate
        self.copyright = copyright
        self.language = language
        self.edition = edition
        self.covers = covers
    }
}

public struct ExportISBN: Sendable, Hashable {
    public let format: BookFormat
    public let number: String
}

/// A portable book-artwork snapshot. Image bytes remain separate from template text and persistence.
public struct ExportCoverAsset: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: BookCoverKind
    public let sourcePath: String
    public let mediaType: String
    public let byteCount: Int64
    public let sha256: String
    public let data: Data?
}

public struct ExportBook: Sendable {
    public let id: UUID
    public let title: String
    public let metadata: ExportBookMetadata
}

/// Conservative formatting semantics portable across manuscript, EPUB, DOCX, and PDF renderers.
public struct ExportProseBlock: Sendable, Hashable {
    public let spans: [ExportTextSpan]

    public var plainText: String {
        spans.map(\.text).joined()
    }
}

public struct ExportTextSpan: Sendable, Hashable {
    public let text: String
    public let isBold: Bool
    public let isItalic: Bool

    public init(text: String, isBold: Bool = false, isItalic: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

/// Projects Core Data into a deterministic, renderer-independent publication snapshot.
@MainActor
public final class ExportCompiler {
    private let store: AuthorDataStore

    public init(store: AuthorDataStore) {
        self.store = store
    }

    public func compile(_ request: ExportRequest) throws -> ExportPublication {
        guard let project = try store.projects.fetch(id: request.projectID) else {
            throw ExportCompilerError.projectNotFound(request.projectID)
        }
        guard let root = try store.documents.fetch(id: request.rootDocumentID) else {
            throw ExportCompilerError.rootDocumentNotFound(request.rootDocumentID)
        }
        guard root.projectID == project.id else {
            throw ExportCompilerError.rootDoesNotBelongToProject(
                documentID: root.id,
                projectID: project.id
            )
        }
        guard root.narrativeType == request.scope.rawValue else {
            throw ExportCompilerError.invalidScope(expected: request.scope, actual: root.narrativeType)
        }

        var diagnostics: [ExportDiagnostic] = []
        var documents: [ExportDocument] = []
        try append(
            root,
            depth: 0,
            includingExcluded: request.includesExcludedDocuments,
            documents: &documents,
            diagnostics: &diagnostics
        )
        let book = containingBook(for: root).map { document in
            ExportBook(
                id: document.id,
                title: document.title,
                metadata: metadata(for: document, type: .book).book!
            )
        }
        return ExportPublication(
            scope: request.scope,
            rootDocumentID: root.id,
            project: ExportProjectMetadata(
                title: project.title,
                creator: project.creator,
                author: project.author,
                createdAt: project.createdAt,
                modifiedAt: project.modifiedAt,
                contactInformation: request.contactInformation
            ),
            book: book,
            documents: documents,
            diagnostics: diagnostics
        )
    }

    private func append(
        _ document: Document,
        depth: Int,
        includingExcluded: Bool,
        documents: inout [ExportDocument],
        diagnostics: inout [ExportDiagnostic]
    ) throws {
        guard includingExcluded || !document.isPublishingExcluded else { return }
        // Imported projects often preserve narrative containers but leave leaf text documents
        // untyped. Their prose is still part of the selected publication subtree.
        if let type = NarrativeType(rawValue: document.narrativeType ?? "")
            ?? (document.kind == DocumentKind.text.rawValue ? .scene : nil) {
            let prose = try prose(for: document, diagnostics: &diagnostics)
            let computedWordCount = WordCountService.count(
                in: prose.map(\.plainText).joined(separator: "\n")
            )
            documents.append(
                ExportDocument(
                    id: document.id,
                    title: document.title,
                    narrativeType: type,
                    depth: depth,
                    wordCount: max(document.ownWordCount, computedWordCount),
                    metadata: metadata(for: document, type: type),
                    prose: prose
                )
            )
        }
        for child in document.orderedChildren {
            try append(
                child,
                depth: depth + 1,
                includingExcluded: includingExcluded,
                documents: &documents,
                diagnostics: &diagnostics
            )
        }
    }

    private func metadata(for document: Document, type: NarrativeType) -> ExportDocumentMetadata {
        func string(_ key: String) -> String? {
            document.metadataValues.first { $0.field.key == key }?.stringValue
        }
        func integer(_ key: String) -> Int64? {
            document.metadataValues.first { $0.field.key == key }?.integerValue?.int64Value
        }
        func date(_ key: String) -> Date? {
            document.metadataValues.first { $0.field.key == key }?.dateValue
        }
        let subtitle = string("system.\(type.rawValue).subtitle")
        let epigraph = type == .section || type == .chapter ? string("system.\(type.rawValue).epigraph") : nil
        let book = type == .book ? ExportBookMetadata(
            subtitle: subtitle,
            author: string("system.book.author"),
            authorAddress: string("system.book.authorAddress"),
            authorPhone: string("system.book.authorPhone"),
            authorEmail: string("system.book.authorEmail"),
            agentName: string("system.book.agentName"),
            agentAddress: string("system.book.agentAddress"),
            agentPhone: string("system.book.agentPhone"),
            agentEmail: string("system.book.agentEmail"),
            isbns: BookFormat.allCases.compactMap { format in
                guard let number = string(format.isbnMetadataKey), !number.isEmpty else { return nil }
                return ExportISBN(format: format, number: number)
            },
            seriesName: string("system.book.seriesName"),
            volumeNumber: integer("system.book.volumeNumber"),
            volumeCount: integer("system.book.volumeCount"),
            publisher: string("system.book.publisher"),
            publicationDate: date("system.book.publicationDate"),
            copyright: string("system.book.copyright"),
            language: string("system.book.language"),
            edition: string("system.book.edition"),
            covers: BookCoverKind.allCases.compactMap { kind in
                guard let resource = document.sourceGalleryItems.first(where: {
                    $0.resource.role == kind.resourceRole
                })?.resource else {
                    return nil
                }
                return ExportCoverAsset(
                    id: resource.id,
                    kind: kind,
                    sourcePath: resource.sourcePath,
                    mediaType: resource.mediaType,
                    byteCount: resource.byteCount,
                    sha256: resource.sha256,
                    data: resource.data
                )
            }
        ) : nil
        return ExportDocumentMetadata(
            subtitle: subtitle,
            epigraph: epigraph,
            povCharacter: string("system.\(type.rawValue).povCharacter"),
            location: type == .scene ? string("system.scene.location") : nil,
            storyDate: type == .scene ? string("system.scene.storyDate") : nil,
            book: book
        )
    }

    private func containingBook(for document: Document) -> Document? {
        if document.narrativeType == NarrativeType.book.rawValue { return document }
        return document.ancestors.first { $0.narrativeType == NarrativeType.book.rawValue }
    }

    private func prose(
        for document: Document,
        diagnostics: inout [ExportDiagnostic]
    ) throws -> [ExportProseBlock] {
        guard let resource = richTextResource(for: document) else {
            return plainTextBlocks(document.plainText)
        }
        guard let data = resource.data,
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ) else {
            guard let plainText = document.plainText else {
                throw ExportCompilerError.malformedRichText(documentID: document.id, resourceID: resource.id)
            }
            diagnostics.append(ExportDiagnostic(
                kind: .richTextFallback,
                documentID: document.id,
                resourceID: resource.id,
                message: "The RTF resource could not be decoded; plain text was used instead."
            ))
            return plainTextBlocks(plainText)
        }
        return blocks(from: attributed)
    }

    private func richTextResource(for document: Document) -> ContentResource? {
        document.resources.first {
            $0.role == "content" && $0.mediaType == "application/rtf" && !$0.isSourcePreserved
        } ?? document.resources.first {
            $0.role == "content" && $0.mediaType == "application/rtf"
        }
    }

    private func plainTextBlocks(_ text: String?) -> [ExportProseBlock] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { ExportProseBlock(spans: [ExportTextSpan(text: String($0))]) }
    }

    private func blocks(from attributed: NSAttributedString) -> [ExportProseBlock] {
        guard attributed.length > 0 else { return [] }
        let text = attributed.string as NSString
        var blocks: [ExportProseBlock] = []
        var location = 0
        while location < text.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let range = NSRange(location: start, length: contentsEnd - start)
            blocks.append(ExportProseBlock(spans: spans(from: attributed, range: range)))
            location = max(end, location + 1)
        }
        return blocks
    }

    private func spans(from attributed: NSAttributedString, range: NSRange) -> [ExportTextSpan] {
        guard range.length > 0 else { return [] }
        var spans: [ExportTextSpan] = []
        attributed.enumerateAttributes(in: range) { attributes, spanRange, _ in
            let traits = fontTraits(attributes[.font])
            let span = ExportTextSpan(
                text: attributed.attributedSubstring(from: spanRange).string,
                isBold: traits.bold,
                isItalic: traits.italic
            )
            if let last = spans.last, last.isBold == span.isBold, last.isItalic == span.isItalic {
                spans[spans.count - 1] = ExportTextSpan(
                    text: last.text + span.text,
                    isBold: last.isBold,
                    isItalic: last.isItalic
                )
            } else {
                spans.append(span)
            }
        }
        return spans
    }

    private func fontTraits(_ value: Any?) -> (bold: Bool, italic: Bool) {
        #if canImport(AppKit)
        guard let font = value as? NSFont else { return (false, false) }
        let traits = NSFontManager.shared.traits(of: font)
        return (traits.contains(.boldFontMask), traits.contains(.italicFontMask))
        #elseif canImport(UIKit)
        guard let font = value as? UIFont else { return (false, false) }
        let traits = font.fontDescriptor.symbolicTraits
        return (traits.contains(.traitBold), traits.contains(.traitItalic))
        #else
        return (false, false)
        #endif
    }
}
