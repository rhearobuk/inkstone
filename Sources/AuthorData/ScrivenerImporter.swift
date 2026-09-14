import CoreData
import CryptoKit
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum ScrivenerImportError: LocalizedError {
    case projectXMLNotFound(URL)
    case filesDirectoryNotFound(URL)
    case unreadableFile(URL, Error)
    case malformedXML(URL, String)
    case missingProjectIdentifier
    case duplicateDocumentIdentifier(String)
    case invalidDocumentIdentifier(String)
    case unsafeSourcePath(String)
    case validationFailed([String])

    public var errorDescription: String? {
        switch self {
        case .projectXMLNotFound(let url): "No Scrivener project XML exists at \(url.path)."
        case .filesDirectoryNotFound(let url): "The expected Files directory is missing at \(url.path)."
        case .unreadableFile(let url, let error): "Could not read \(url.path): \(error.localizedDescription)"
        case .malformedXML(let url, let detail): "Malformed XML at \(url.path): \(detail)"
        case .missingProjectIdentifier: "The project XML has no stable Identifier."
        case .duplicateDocumentIdentifier(let value): "Duplicate binder UUID: \(value)."
        case .invalidDocumentIdentifier(let value): "Invalid binder UUID: \(value)."
        case .unsafeSourcePath(let value): "A source path escaped the project root: \(value)."
        case .validationFailed(let errors): "Imported data failed validation: \(errors.joined(separator: "; "))."
        }
    }
}

public struct ImportWarning: Equatable, Sendable {
    public let code: String
    public let message: String
    public let sourceIdentifier: String?
}

public struct ScrivenerImportResult: Sendable {
    public let projectID: UUID
    public let importRunID: UUID
    public let insertedCount: Int
    public let updatedCount: Int
    public let documentCount: Int
    public let resourceCount: Int
    public let linkCount: Int
    public let warnings: [ImportWarning]
}

@MainActor
public final class ScrivenerImporter {
    private let store: AuthorDataStore
    private let fileManager: FileManager

    public init(store: AuthorDataStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func importProject(xmlURL: URL, filesURL: URL) throws -> ScrivenerImportResult {
        guard fileManager.fileExists(atPath: xmlURL.path) else {
            throw ScrivenerImportError.projectXMLNotFound(xmlURL)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: filesURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScrivenerImportError.filesDirectoryNotFound(filesURL)
        }

        let xmlData = try read(xmlURL)
        let parsed = try ScrivenerXMLReader.parse(data: xmlData, url: xmlURL)
        guard !parsed.identifier.isEmpty else { throw ScrivenerImportError.missingProjectIdentifier }
        guard let projectID = UUID(uuidString: parsed.identifier) else {
            throw ScrivenerImportError.invalidDocumentIdentifier(parsed.identifier)
        }

        let duplicateIDs = Dictionary(grouping: parsed.items, by: \.identifier).filter { $0.value.count > 1 }
        if let duplicate = duplicateIDs.keys.sorted().first {
            throw ScrivenerImportError.duplicateDocumentIdentifier(duplicate)
        }
        for item in parsed.items where UUID(uuidString: item.identifier) == nil {
            throw ScrivenerImportError.invalidDocumentIdentifier(item.identifier)
        }

        let fingerprint = SHA256.hash(data: xmlData).hex
        let runID = UUID()
        let runStartedAt = Date()
        let run = store.importRuns.create(id: runID) {
            $0.sourceURL = xmlURL.path
            $0.sourceFingerprint = fingerprint
            $0.startedAt = runStartedAt
            $0.status = "running"
            $0.insertedCount = 0
            $0.updatedCount = 0
            $0.warningCount = 0
        }

        var inserted = 0
        var updated = 0
        var warnings: [ImportWarning] = []

        do {
            let project = try store.projects.upsert(id: projectID) { project, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                project.title = parsed.items.first(where: { $0.parentIdentifier == nil })?.title
                    ?? xmlURL.deletingPathExtension().lastPathComponent
                project.sourceIdentifier = parsed.identifier
                project.sourceFormat = "scrivener"
                project.sourceVersion = parsed.attributes["Version"]
                project.creator = parsed.attributes["Creator"]
                project.author = parsed.attributes["Author"]
                project.device = parsed.attributes["Device"]
                if isNew { project.createdAt = Date() }
                project.modifiedAt = Date()
                project.sourceModifiedAt = Self.parseDate(parsed.attributes["Modified"])
            }
            run.project = project

            let projectDefinitionPath = "Project/\(xmlURL.lastPathComponent)"
            let projectDefinitionID = DeterministicID.make(namespace: projectID, name: "resource:\(projectDefinitionPath)")
            _ = try store.resources.upsert(id: projectDefinitionID) { resource, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                resource.sourcePath = projectDefinitionPath
                resource.role = "projectDefinition"
                resource.mediaType = "application/xml"
                resource.byteCount = Int64(xmlData.count)
                resource.sha256 = fingerprint
                resource.data = xmlData
                resource.textContent = String(data: xmlData, encoding: .utf8)
                resource.isSourcePreserved = true
                resource.project = project
            }

            var documentsBySourceID: [String: Document] = [:]
            for item in parsed.items {
                let id = UUID(uuidString: item.identifier)!
                let document = try store.documents.upsert(id: id) { document, isNew in
                    if isNew { inserted += 1 } else { updated += 1 }
                    document.sourceIdentifier = item.identifier
                    document.title = item.title
                    document.kind = item.kind
                    document.orderIndex = Int64(item.orderIndex)
                    document.createdAt = Self.parseDate(item.created)
                    document.modifiedAt = Self.parseDate(item.modified)
                    document.includeInCompile = item.metadata["MetaData/IncludeInCompile"].map {
                        NSNumber(value: $0.caseInsensitiveCompare("yes") == .orderedSame)
                    }
                    document.labelIdentifier = item.metadata["MetaData/LabelID"]
                    document.statusIdentifier = item.metadata["MetaData/StatusID"]
                    document.sectionTypeIdentifier = item.metadata["MetaData/SectionType"]
                    document.selectedChildIdentifier = item.metadata["CorkboardAndOutliner/SelectedSubdocumentUUIDs"]
                    let selection = Self.selection(item.metadata["TextSettings/TextSelection"])
                    document.selectionLocation = selection.map { NSNumber(value: $0.0) }
                    document.selectionLength = selection.map { NSNumber(value: $0.1) }
                    document.project = project
                }
                documentsBySourceID[item.identifier] = document
            }

            for item in parsed.items {
                let document = documentsBySourceID[item.identifier]!
                document.parent = item.parentIdentifier.flatMap { documentsBySourceID[$0] }
                try upsertMetadata(item.metadata, item: item, document: document, project: project, inserted: &inserted, updated: &updated)
            }

            let sourceFiles = try recursivelyEnumeratedFiles(root: filesURL)
            var importedResourceCount = 1
            for fileURL in sourceFiles {
                let relativePath = try relativePath(fileURL, under: filesURL)
                let data = try read(fileURL)
                let pathComponents = relativePath.split(separator: "/").map(String.init)
                let sourceDocumentID = pathComponents.count >= 3 && pathComponents[0] == "Data"
                    ? pathComponents[1]
                    : nil
                let document = sourceDocumentID.flatMap { documentsBySourceID[$0] }
                let resourceID = DeterministicID.make(namespace: projectID, name: "resource:\(relativePath)")
                let role = Self.resourceRole(fileURL.lastPathComponent)
                let mediaType = Self.mediaType(fileURL.pathExtension)
                let textContent = Self.textContent(data: data, extension: fileURL.pathExtension)
                let digest = SHA256.hash(data: data).hex

                let resource = try store.resources.upsert(id: resourceID) { resource, isNew in
                    if isNew { inserted += 1 } else { updated += 1 }
                    resource.sourcePath = relativePath
                    resource.role = role
                    resource.mediaType = mediaType
                    resource.byteCount = Int64(data.count)
                    resource.sha256 = digest
                    resource.data = data
                    resource.textContent = textContent
                    resource.isSourcePreserved = true
                    resource.project = project
                    resource.document = document
                }
                importedResourceCount += 1

                if let document {
                    if role == "synopsis" { document.synopsis = textContent }
                    if role == "content", fileURL.pathExtension.lowercased() == "rtf" {
                        let plainText = Self.plainText(fromRTF: data)
                        document.plainText = plainText
                        resource.textContent = plainText
                        let revisionID = DeterministicID.make(namespace: document.id, name: "source-revision:\(digest)")
                        _ = try store.revisions.upsert(id: revisionID) { revision, isNew in
                            if isNew { inserted += 1 } else { updated += 1 }
                            revision.sequence = 0
                            revision.createdAt = document.modifiedAt ?? Date()
                            revision.author = parsed.attributes["Author"]
                            revision.source = "sourceImport"
                            revision.plainText = plainText
                            revision.contentHash = digest
                            revision.summary = "Imported source baseline"
                            revision.document = document
                        }
                    }
                    if role == "styleReferences", let styleIDs = textContent?.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
                        for (index, styleID) in styleIDs.enumerated() {
                            try upsertMetadata(
                                ["StyleReference/\(index)": String(styleID)],
                                item: parsed.items.first(where: { $0.identifier == document.sourceIdentifier })!,
                                document: document,
                                project: project,
                                inserted: &inserted,
                                updated: &updated
                            )
                        }
                    }
                } else if let sourceDocumentID, UUID(uuidString: sourceDocumentID) != nil {
                    warnings.append(.init(
                        code: "orphan-resource",
                        message: "\(relativePath) has no matching binder item.",
                        sourceIdentifier: sourceDocumentID
                    ))
                }
            }

            try importStyles(filesURL: filesURL, project: project, inserted: &inserted, updated: &updated, warnings: &warnings)
            let linkCount = try importLinks(
                items: parsed.items,
                documents: documentsBySourceID,
                projectID: projectID,
                warnings: &warnings,
                inserted: &inserted,
                updated: &updated
            )

            let provenanceID = DeterministicID.make(namespace: projectID, name: "import:\(fingerprint)")
            _ = try store.provenanceEvents.upsert(id: provenanceID) { event, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                event.eventType = "sourceImport"
                event.agent = "AuthorData.ScrivenerImporter"
                event.agentVersion = "1"
                event.timestamp = Date()
                event.sourceURI = xmlURL.path
                event.sourceIdentifier = parsed.identifier
                event.contentHash = fingerprint
                event.details = "Imported \(parsed.items.count) binder items and \(importedResourceCount) source resources."
                event.project = project
            }

            let validationErrors = try validate(project: project, expectedItems: parsed.items.count)
            if !validationErrors.isEmpty {
                throw ScrivenerImportError.validationFailed(validationErrors)
            }

            run.finishedAt = Date()
            run.status = "succeeded"
            run.insertedCount = Int64(inserted)
            run.updatedCount = Int64(updated)
            run.warningCount = Int64(warnings.count)
            try store.save()
            return ScrivenerImportResult(
                projectID: projectID,
                importRunID: runID,
                insertedCount: inserted,
                updatedCount: updated,
                documentCount: parsed.items.count,
                resourceCount: importedResourceCount,
                linkCount: linkCount,
                warnings: warnings
            )
        } catch {
            store.rollback()
            let failedRun = store.importRuns.create(id: runID) {
                $0.sourceURL = xmlURL.path
                $0.sourceFingerprint = fingerprint
                $0.startedAt = runStartedAt
                $0.finishedAt = Date()
                $0.status = "failed"
                $0.insertedCount = 0
                $0.updatedCount = 0
                $0.warningCount = Int64(warnings.count)
                $0.errorMessage = error.localizedDescription
            }
            _ = failedRun
            try? store.save()
            throw error
        }
    }

    private func upsertMetadata(
        _ metadata: [String: String],
        item: BinderItemRecord,
        document: Document,
        project: WritingProject,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        let excluded = Set([
            "MetaData/IncludeInCompile", "MetaData/LabelID", "MetaData/StatusID",
            "MetaData/SectionType", "TextSettings/TextSelection",
            "CorkboardAndOutliner/SelectedSubdocumentUUIDs"
        ])
        for (key, value) in metadata where !excluded.contains(key) && !value.isEmpty {
            let normalizedKey = "scrivener.\(key.replacingOccurrences(of: "/", with: "."))"
            let fieldID = DeterministicID.make(namespace: project.id, name: "metadata-field:\(normalizedKey)")
            let field = try store.metadataFields.upsert(id: fieldID) { field, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                field.key = normalizedKey
                field.displayName = key.split(separator: "/").last.map(String.init) ?? key
                field.valueType = "string"
                field.semanticPurpose = Self.semanticPurpose(for: normalizedKey)
                field.isSourceDefined = true
                field.project = project
            }
            let valueID = DeterministicID.make(namespace: document.id, name: "metadata-value:\(normalizedKey)")
            _ = try store.metadataValues.upsert(id: valueID) { metadataValue, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                metadataValue.stringValue = value
                metadataValue.sourcePath = item.sourcePaths[key]
                metadataValue.field = field
                metadataValue.document = document
            }
        }
    }

    private func importLinks(
        items: [BinderItemRecord],
        documents: [String: Document],
        projectID: UUID,
        warnings: inout [ImportWarning],
        inserted: inout Int,
        updated: inout Int
    ) throws -> Int {
        var linkCount = 0
        for item in items {
            guard let source = documents[item.identifier] else { continue }
            var links = item.bookmarks.map { ("bookmark", $0, nil as Int?) }
            if let content = source.resources.first(where: { $0.role == "content" }),
               let linkSource = Self.linkSource(from: content) {
                let pattern = #"scrivlnk://([0-9A-Fa-f-]{36})"#
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(linkSource.startIndex..., in: linkSource)
                links += regex.matches(in: linkSource, range: range).compactMap { match in
                    guard let targetRange = Range(match.range(at: 1), in: linkSource) else { return nil }
                    return ("inline", String(linkSource[targetRange]), match.range.location)
                }
            }
            for (ordinal, link) in links.enumerated() {
                let target = documents[link.1]
                if target == nil {
                    warnings.append(.init(
                        code: "unresolved-link",
                        message: "\(link.0) link targets missing binder UUID \(link.1).",
                        sourceIdentifier: item.identifier
                    ))
                }
                let linkID = DeterministicID.make(
                    namespace: projectID,
                    name: "link:\(item.identifier):\(link.0):\(link.1):\(link.2 ?? ordinal)"
                )
                _ = try store.links.upsert(id: linkID) { object, isNew in
                    if isNew { inserted += 1 } else { updated += 1 }
                    object.kind = link.0
                    object.sourceLocation = link.2.map(NSNumber.init(value:))
                    object.sourceLength = link.2.map { _ in NSNumber(value: 36) }
                    object.unresolvedTargetIdentifier = target == nil ? link.1 : nil
                    object.sourceDocument = source
                    object.targetDocument = target
                }
                linkCount += 1
            }
        }
        return linkCount
    }

    private func importStyles(
        filesURL: URL,
        project: WritingProject,
        inserted: inout Int,
        updated: inout Int,
        warnings: inout [ImportWarning]
    ) throws {
        let stylesURL = filesURL.appendingPathComponent("styles.xml")
        guard fileManager.fileExists(atPath: stylesURL.path) else {
            warnings.append(.init(code: "styles-missing", message: "Files/styles.xml is missing.", sourceIdentifier: nil))
            return
        }
        let styles = try StyleXMLReader.parse(data: read(stylesURL), url: stylesURL)
        for style in styles {
            guard let sourceID = UUID(uuidString: style.identifier) else {
                warnings.append(.init(code: "invalid-style-id", message: "Invalid style UUID \(style.identifier).", sourceIdentifier: style.identifier))
                continue
            }
            _ = try store.styles.upsert(id: sourceID) { object, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                object.sourceIdentifier = style.identifier
                object.name = style.name
                object.kind = style.kind
                object.fontChange = style.fontChange
                object.shortcut = style.shortcut
                object.formatRTF = style.formatRTF
                object.project = project
            }
        }
    }

    private func validate(project: WritingProject, expectedItems: Int) throws -> [String] {
        var errors: [String] = []
        if project.documents.count != expectedItems {
            errors.append("expected \(expectedItems) documents, found \(project.documents.count)")
        }
        let roots = project.documents.filter { $0.parent == nil }
        if roots.isEmpty { errors.append("project has no root documents") }
        for document in project.documents {
            if document.project != project { errors.append("\(document.sourceIdentifier) has wrong project") }
            if document.parent === document { errors.append("\(document.sourceIdentifier) is its own parent") }
        }
        return errors
    }

    private func recursivelyEnumeratedFiles(root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScrivenerImportError.filesDirectoryNotFound(root)
        }
        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    private func relativePath(_ file: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            throw ScrivenerImportError.unsafeSourcePath(filePath)
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func read(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch { throw ScrivenerImportError.unreadableFile(url, error) }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: value)
    }

    private static func selection(_ value: String?) -> (Int64, Int64)? {
        guard let values = value?.split(separator: ",").compactMap({ Int64($0) }), values.count == 2 else { return nil }
        return (values[0], values[1])
    }

    private static func resourceRole(_ name: String) -> String {
        switch name.lowercased() {
        case "content.rtf", "content.pdf", "content.jpg": "content"
        case "synopsis.txt": "synopsis"
        case "notes.rtf": "notes"
        case "content.styles": "styleReferences"
        case "card-image.jpg": "cardImage"
        default: "sourceMetadata"
        }
    }

    private static func mediaType(_ extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "rtf": "application/rtf"
        case "txt": "text/plain"
        case "xml": "application/xml"
        case "jpg", "jpeg": "image/jpeg"
        case "pdf": "application/pdf"
        case "styles": "text/x-scrivener-style-references"
        default: "application/octet-stream"
        }
    }

    private static func textContent(data: Data, extension extensionName: String) -> String? {
        switch extensionName.lowercased() {
        case "txt", "xml", "styles", "indexes", "history", "checksum", "":
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        case "rtf":
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        default:
            return nil
        }
    }

    private static func linkSource(from resource: ContentResource) -> String? {
        if resource.mediaType == "application/rtf", let data = resource.data {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
        }
        return resource.textContent
    }

    private static func plainText(fromRTF data: Data) -> String? {
        #if canImport(AppKit) || canImport(UIKit)
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return fallbackPlainText(fromRTF: data)
    }

    private static func fallbackPlainText(fromRTF data: Data) -> String? {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252) else { return nil }
        var result = ""
        var index = source.startIndex
        var ignorableDepth = 0
        var depth = 0
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
                if source[source.index(after: index)...].hasPrefix("\\*") { ignorableDepth = depth }
                index = source.index(after: index)
            } else if character == "}" {
                if depth == ignorableDepth { ignorableDepth = 0 }
                depth = max(0, depth - 1)
                index = source.index(after: index)
            } else if character == "\\" {
                index = source.index(after: index)
                guard index < source.endIndex else { break }
                if source[index] == "'" {
                    let start = source.index(after: index)
                    let end = source.index(start, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                    if ignorableDepth == 0,
                       let byte = UInt8(source[start..<end], radix: 16),
                       let decoded = String(data: Data([byte]), encoding: .windowsCP1252) {
                        result.append(decoded)
                    }
                    index = end
                    continue
                }
                if source[index] == "\\" || source[index] == "{" || source[index] == "}" {
                    if ignorableDepth == 0 { result.append(source[index]) }
                    index = source.index(after: index)
                    continue
                }
                let wordStart = index
                while index < source.endIndex && source[index].isLetter {
                    index = source.index(after: index)
                }
                let word = source[wordStart..<index]
                var sign = 1
                if index < source.endIndex && source[index] == "-" {
                    sign = -1
                    index = source.index(after: index)
                }
                let numberStart = index
                while index < source.endIndex && source[index].isNumber {
                    index = source.index(after: index)
                }
                let number = Int(source[numberStart..<index]).map { $0 * sign }
                if index < source.endIndex && source[index] == " " { index = source.index(after: index) }
                guard ignorableDepth == 0 else { continue }
                switch word {
                case "par", "line": result.append("\n")
                case "tab": result.append("\t")
                case "emdash": result.append("—")
                case "endash": result.append("–")
                case "lquote", "rquote": result.append("'")
                case "ldblquote", "rdblquote": result.append("\"")
                case "u":
                    if let number, let scalar = UnicodeScalar((number < 0 ? number + 65_536 : number)) {
                        result.append(Character(scalar))
                    }
                default: break
                }
            } else {
                if ignorableDepth == 0 && character != "\n" && character != "\r" {
                    result.append(character)
                }
                index = source.index(after: index)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func semanticPurpose(for key: String) -> String? {
        switch key.lowercased() {
        case let value where value.contains("isbn"): "publicationIdentifier"
        case let value where value.contains("sexualcontent"): "contentRating"
        case let value where value.contains("fileextension"): "mediaType"
        case let value where value.contains("currentpdfpage"): "readingPosition"
        case let value where value.contains("iconfilename"): "presentationHint"
        case let value where value.contains("itemid"): "outlineState"
        default: "sourceMetadata"
        }
    }
}

private struct BinderItemRecord {
    let identifier: String
    let parentIdentifier: String?
    let kind: String
    let created: String?
    let modified: String?
    let title: String
    let orderIndex: Int
    let metadata: [String: String]
    let sourcePaths: [String: String]
    let bookmarks: [String]
}

private struct ParsedScrivenerProject {
    let identifier: String
    let attributes: [String: String]
    let items: [BinderItemRecord]
}

private final class ScrivenerXMLReader: NSObject, XMLParserDelegate {
    private struct Draft {
        let identifier: String
        let parentIdentifier: String?
        let kind: String
        let created: String?
        let modified: String?
        let orderIndex: Int
        var title = ""
        var metadata: [String: String] = [:]
        var sourcePaths: [String: String] = [:]
        var bookmarks: [String] = []
        var childCount = 0
    }

    private var projectAttributes: [String: String] = [:]
    private var items: [BinderItemRecord] = []
    private var stack: [Draft] = []
    private var elementPath: [String] = []
    private var text = ""
    private var parseError: Error?

    static func parse(data: Data, url: URL) throws -> ParsedScrivenerProject {
        let reader = ScrivenerXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw ScrivenerImportError.malformedXML(url, parser.parserError?.localizedDescription ?? "unknown parser error")
        }
        if let parseError = reader.parseError {
            throw ScrivenerImportError.malformedXML(url, parseError.localizedDescription)
        }
        return ParsedScrivenerProject(
            identifier: reader.projectAttributes["Identifier"] ?? "",
            attributes: reader.projectAttributes,
            items: reader.items
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementPath.append(elementName)
        text = ""
        if elementName == "ScrivenerProject" {
            projectAttributes = attributeDict
        } else if elementName == "BinderItem" {
            guard let identifier = attributeDict["UUID"] else {
                parseError = ScrivenerImportError.missingProjectIdentifier
                parser.abortParsing()
                return
            }
            let order = stack.last?.childCount ?? items.filter { $0.parentIdentifier == nil }.count
            if !stack.isEmpty { stack[stack.count - 1].childCount += 1 }
            stack.append(Draft(
                identifier: identifier,
                parentIdentifier: stack.last?.identifier,
                kind: attributeDict["Type"] ?? "unknown",
                created: attributeDict["Created"],
                modified: attributeDict["Modified"],
                orderIndex: order
            ))
        } else if elementName == "Bookmark", let target = attributeDict["BinderUUID"], !stack.isEmpty {
            stack[stack.count - 1].bookmarks.append(target)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            _ = elementPath.popLast()
            text = ""
        }
        guard !stack.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "Title" {
            stack[stack.count - 1].title = trimmed
        } else if elementName == "BinderItem" {
            let draft = stack.removeLast()
            items.append(BinderItemRecord(
                identifier: draft.identifier,
                parentIdentifier: draft.parentIdentifier,
                kind: draft.kind,
                created: draft.created,
                modified: draft.modified,
                title: draft.title,
                orderIndex: draft.orderIndex,
                metadata: draft.metadata,
                sourcePaths: draft.sourcePaths,
                bookmarks: draft.bookmarks
            ))
        } else if !trimmed.isEmpty,
                  let binderIndex = elementPath.lastIndex(of: "BinderItem"),
                  binderIndex + 1 < elementPath.count {
            let relative = elementPath[(binderIndex + 1)...].joined(separator: "/")
            if relative != "Title" && !relative.hasPrefix("Children/") {
                var key = relative
                if relative.hasSuffix("CustomMetaData/MetaDataItem/Value"),
                   let fieldID = stack.last?.metadata["MetaData/CustomMetaData/MetaDataItem/FieldID"] {
                    key = "MetaData/Custom/\(fieldID)"
                }
                stack[stack.count - 1].metadata[key] = trimmed
                stack[stack.count - 1].sourcePaths[key] = "/ScrivenerProject/Binder/\(relative)"
            }
        }
    }
}

private struct StyleRecord {
    let identifier: String
    let name: String
    let kind: String
    let fontChange: String?
    let shortcut: String?
    let formatRTF: String?
}

private final class StyleXMLReader: NSObject, XMLParserDelegate {
    private var records: [StyleRecord] = []
    private var currentAttributes: [String: String]?
    private var format = ""
    private var inFormat = false

    static func parse(data: Data, url: URL) throws -> [StyleRecord] {
        let reader = StyleXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw ScrivenerImportError.malformedXML(url, parser.parserError?.localizedDescription ?? "unknown parser error")
        }
        return reader.records
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "Style" {
            currentAttributes = attributeDict
            format = ""
        } else if elementName == "Format" {
            inFormat = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inFormat { format += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inFormat { format += String(data: CDATABlock, encoding: .utf8) ?? "" }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Format" {
            inFormat = false
        } else if elementName == "Style", let attributes = currentAttributes {
            records.append(StyleRecord(
                identifier: attributes["ID"] ?? "",
                name: attributes["Name"] ?? "",
                kind: attributes["Type"] ?? "unknown",
                fontChange: attributes["FontChange"],
                shortcut: attributes["Shortcut"],
                formatRTF: format.isEmpty ? nil : format
            ))
            currentAttributes = nil
        }
    }
}

private enum DeterministicID {
    static func make(namespace: UUID, name: String) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        namespaceBytes.append(Data(name.utf8))
        var bytes = Array(SHA256.hash(data: namespaceBytes).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
