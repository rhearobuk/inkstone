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

                if mediaType.hasPrefix("image/") {
                    try upsertGalleryItem(
                        resource: resource,
                        sourceDocument: document,
                        title: document?.title ?? fileURL.deletingPathExtension().lastPathComponent,
                        orderIndex: Int64(importedResourceCount - 1),
                        project: project,
                        inserted: &inserted,
                        updated: &updated
                    )
                }

                if let document {
                    if role == "synopsis" { document.synopsis = textContent }
                    if role == "content", fileURL.pathExtension.lowercased() == "rtf" {
                        let plainText = Self.plainText(fromRTF: data)
                        document.plainText = plainText
                        resource.textContent = plainText
                        try importEmbeddedImages(
                            from: data,
                            sourceDocument: document,
                            project: project,
                            startingOrderIndex: Int64(importedResourceCount),
                            importedResourceCount: &importedResourceCount,
                            inserted: &inserted,
                            updated: &updated
                        )
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

            try importProjectSettings(parsed, project: project, inserted: &inserted, updated: &updated)
            try importCharacterDossiers(
                items: parsed.items,
                documents: documentsBySourceID,
                project: project,
                inserted: &inserted,
                updated: &updated
            )
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

    /// Persists the project-level vocabulary definitions (`SectionTypes`, `LabelSettings`,
    /// `StatusSettings`, `CustomMetaDataSettings`) parsed from the Scrivener project XML so they
    /// can be surfaced and edited in a project preferences UI. Runs after per-document metadata
    /// import so authoritative display names/types from these settings win over placeholder
    /// values inferred from raw metadata keys.
    private func importProjectSettings(
        _ parsed: ParsedScrivenerProject,
        project: WritingProject,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        for (index, sectionType) in parsed.sectionTypes.enumerated() {
            let id = DeterministicID.make(namespace: project.id, name: "section-type:\(sectionType.id)")
            _ = try store.sectionTypeDefinitions.upsert(id: id) { definition, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                definition.sourceIdentifier = sectionType.id
                definition.title = sectionType.title
                definition.orderIndex = Int64(index)
                definition.project = project
            }
        }

        for (index, label) in parsed.labels.enumerated() {
            let id = DeterministicID.make(namespace: project.id, name: "label:\(label.id)")
            let components = Self.colorComponents(label.color)
            _ = try store.labelDefinitions.upsert(id: id) { definition, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                definition.sourceIdentifier = label.id
                definition.title = label.title
                definition.colorRed = components.map { NSNumber(value: $0.0) }
                definition.colorGreen = components.map { NSNumber(value: $0.1) }
                definition.colorBlue = components.map { NSNumber(value: $0.2) }
                definition.isDefault = label.id == parsed.defaultLabelID
                definition.orderIndex = Int64(index)
                definition.project = project
            }
        }

        for (index, status) in parsed.statuses.enumerated() {
            let id = DeterministicID.make(namespace: project.id, name: "status:\(status.id)")
            _ = try store.statusDefinitions.upsert(id: id) { definition, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                definition.sourceIdentifier = status.id
                definition.title = status.title
                definition.isDefault = status.id == parsed.defaultStatusID
                definition.orderIndex = Int64(index)
                definition.project = project
            }
        }

        for (index, field) in parsed.customFields.enumerated() {
            let key = "scrivener.MetaData.Custom.\(field.id)"
            let fieldID = DeterministicID.make(namespace: project.id, name: "metadata-field:\(key)")
            _ = try store.metadataFields.upsert(id: fieldID) { metadataField, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                metadataField.key = key
                metadataField.displayName = field.title
                metadataField.valueType = field.type.lowercased()
                metadataField.sourceIdentifier = field.id
                metadataField.isSourceDefined = true
                metadataField.orderIndex = Int64(index)
                metadataField.project = project
            }
        }
    }

    private static func colorComponents(_ raw: String?) -> (Double, Double, Double)? {
        guard let raw else { return nil }
        let parts = raw.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2])
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

    private func importCharacterDossiers(
        items: [BinderItemRecord],
        documents: [String: Document],
        project: WritingProject,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.identifier, $0) })
        let characterRootIDs = Set(items.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Characters") == .orderedSame
        }.map(\.identifier))
        guard !characterRootIDs.isEmpty else { return }

        func belongsToCharacters(_ item: BinderItemRecord) -> Bool {
            var parentID = item.parentIdentifier
            while let currentID = parentID {
                if characterRootIDs.contains(currentID) { return true }
                parentID = itemByID[currentID]?.parentIdentifier
            }
            return false
        }

        var imported: [(profile: CharacterProfile, card: CharacterCard, isNew: Bool)] = []
        for item in items where belongsToCharacters(item) {
            guard let document = documents[item.identifier],
                  let sourceText = document.plainText,
                  CharacterCard.looksLikeCard(sourceText) else {
                continue
            }
            let card = CharacterCard(text: sourceText, fallbackName: item.title)
            let entityID = DeterministicID.make(
                namespace: project.id,
                name: "character-entity:\(item.identifier)"
            )
            let profileID = DeterministicID.make(
                namespace: project.id,
                name: "character-profile:\(item.identifier)"
            )
            let shouldMapSource = try store.characterProfiles.fetch(id: profileID) == nil
            let entity = try store.semanticEntities.upsert(id: entityID) { entity, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                if shouldMapSource {
                    entity.canonicalName = card.fullName
                    entity.kind = SemanticEntityKind.character.rawValue
                    entity.summary = card.sections["Role in Story"]
                    entity.source = ProvenanceAgent.sourceImport.rawValue
                    entity.createdAt = document.createdAt ?? Date()
                    entity.modifiedAt = document.modifiedAt ?? Date()
                }
                entity.project = project
            }

            for aliasName in shouldMapSource ? card.aliases : [] {
                let normalizedName = Self.normalizedName(aliasName)
                let aliasID = DeterministicID.make(
                    namespace: entityID,
                    name: "alias:\(normalizedName)"
                )
                _ = try store.entityAliases.upsert(id: aliasID) { alias, isNew in
                    if isNew { inserted += 1 } else { updated += 1 }
                    alias.name = aliasName
                    alias.normalizedName = normalizedName
                    alias.semanticEntity = entity
                }
            }

            let profile = try store.characterProfiles.upsert(id: profileID) { profile, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                if shouldMapSource {
                    profile.firstName = card.firstName
                    profile.middleName = card.middleName
                    profile.lastName = card.lastName
                    profile.age = card.age.map(NSNumber.init(value:))
                    profile.ageText = card.ageText
                    profile.location = card.location
                    profile.height = card.height
                    profile.weight = card.weight
                    profile.physicalDescription = card.sections["Physical Description"]
                    profile.biography = card.sections["Background"]
                    profile.source = ProvenanceAgent.sourceImport.rawValue
                    profile.createdAt = document.createdAt ?? Date()
                    profile.modifiedAt = document.modifiedAt ?? Date()
                }
                profile.project = project
                profile.semanticEntity = entity
                profile.sourceDocument = document
            }
            for galleryItem in document.sourceGalleryItems {
                galleryItem.semanticEntity = entity
            }

            if shouldMapSource {
                try upsertCharacterNotes(
                    card: card,
                    profile: profile,
                    inserted: &inserted,
                    updated: &updated
                )
                try upsertCharacterMeasurements(
                    card: card,
                    profile: profile,
                    inserted: &inserted,
                    updated: &updated
                )
                try upsertCharacterConflicts(
                    card: card,
                    profile: profile,
                    inserted: &inserted,
                    updated: &updated
                )
            }
            imported.append((profile, card, shouldMapSource))
        }

        try upsertCharacterRelationships(
            imported,
            inserted: &inserted,
            updated: &updated
        )
        resolveConflictParticipants(imported)
    }

    private func upsertCharacterNotes(
        card: CharacterCard,
        profile: CharacterProfile,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        let mappings = [
            ("Role in Story", "role"),
            ("Goal", "goal"),
            ("Narrative Function", "narrativeFunction"),
            ("Skills", "skills"),
            ("Personality", "personality"),
            ("Occupation", "occupation"),
            ("Habits/Mannerisms", "mannerisms"),
            ("Key Relationships", "relationships"),
            ("Notes", "general")
        ]
        for (index, mapping) in mappings.enumerated() {
            guard let body = card.sections[mapping.0], !body.isEmpty else { continue }
            let noteID = DeterministicID.make(namespace: profile.id, name: "note:\(mapping.1)")
            _ = try store.characterNotes.upsert(id: noteID) { note, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                note.title = mapping.0
                note.body = body
                note.kind = mapping.1
                note.source = ProvenanceAgent.sourceImport.rawValue
                note.orderIndex = Int64(index)
                if isNew { note.createdAt = profile.createdAt }
                note.modifiedAt = profile.modifiedAt
                note.characterProfile = profile
            }
        }
        if let body = card.unmappedText, !body.isEmpty {
            let noteID = DeterministicID.make(namespace: profile.id, name: "note:importRemainder")
            _ = try store.characterNotes.upsert(id: noteID) { note, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                note.title = "Imported Notes"
                note.body = body
                note.kind = "importRemainder"
                note.source = ProvenanceAgent.sourceImport.rawValue
                note.orderIndex = Int64(mappings.count)
                if isNew { note.createdAt = profile.createdAt }
                note.modifiedAt = profile.modifiedAt
                note.characterProfile = profile
            }
        }
    }

    private func upsertCharacterMeasurements(
        card: CharacterCard,
        profile: CharacterProfile,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        for (index, measurement) in card.measurements.enumerated() {
            let measurementID = DeterministicID.make(
                namespace: profile.id,
                name: "measurement:\(index):\(Self.normalizedName(measurement.value))"
            )
            _ = try store.characterMeasurements.upsert(id: measurementID) { object, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                object.name = measurement.name
                object.value = measurement.value
                object.unit = measurement.unit
                object.notes = measurement.notes
                object.orderIndex = Int64(index)
                object.characterProfile = profile
            }
        }
    }

    private func upsertCharacterConflicts(
        card: CharacterCard,
        profile: CharacterProfile,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        for (title, kind) in [("Internal Conflicts", "internal"), ("External Conflicts", "external")] {
            guard let summary = card.sections[title], !summary.isEmpty else { continue }
            let conflictID = DeterministicID.make(namespace: profile.id, name: "conflict:\(kind)")
            _ = try store.characterConflicts.upsert(id: conflictID) { conflict, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                conflict.title = title
                conflict.summary = summary
                conflict.kind = kind
                conflict.status = "active"
                conflict.source = ProvenanceAgent.sourceImport.rawValue
                if isNew { conflict.createdAt = profile.createdAt }
                conflict.modifiedAt = profile.modifiedAt
                conflict.characterProfile = profile
            }
        }
    }

    private func upsertCharacterRelationships(
        _ imported: [(profile: CharacterProfile, card: CharacterCard, isNew: Bool)],
        inserted: inout Int,
        updated: inout Int
    ) throws {
        for source in imported where source.isNew {
            let relationshipText = [
                source.card.sections["Role in Story"],
                source.card.sections["Key Relationships"]
            ].compactMap { $0 }.joined(separator: "\n")
            guard !relationshipText.isEmpty else { continue }

            for target in imported where target.profile.id != source.profile.id {
                let names = [
                    target.profile.semanticEntity.canonicalName,
                    target.profile.firstName,
                    target.profile.lastName
                ].compactMap { $0 } +
                    target.profile.semanticEntity.aliases.map(\.name)
                guard names.contains(where: {
                    $0.count >= 3 && relationshipText.localizedCaseInsensitiveContains($0)
                }) else {
                    continue
                }
                let relationshipID = DeterministicID.make(
                    namespace: source.profile.id,
                    name: "relationship:\(target.profile.id.uuidString)"
                )
                _ = try store.characterRelationships.upsert(id: relationshipID) { relationship, isNew in
                    if isNew { inserted += 1 } else { updated += 1 }
                    relationship.kind = Self.relationshipKind(relationshipText)
                    relationship.label = nil
                    relationship.notes = relationshipText
                    relationship.source = ProvenanceAgent.sourceImport.rawValue
                    if isNew { relationship.createdAt = source.profile.createdAt }
                    relationship.modifiedAt = source.profile.modifiedAt
                    relationship.sourceCharacter = source.profile
                    relationship.targetCharacter = target.profile
                }
            }
        }
    }

    private func resolveConflictParticipants(
        _ imported: [(profile: CharacterProfile, card: CharacterCard, isNew: Bool)]
    ) {
        for source in imported where source.isNew {
            for conflict in source.profile.conflicts {
                guard let text = conflict.summary else { continue }
                conflict.relatedCharacters = Set(imported.compactMap { target in
                    guard target.profile.id != source.profile.id else { return nil }
                    let names = [
                        target.profile.semanticEntity.canonicalName,
                        target.profile.firstName,
                        target.profile.lastName
                    ].compactMap { $0 } +
                        target.profile.semanticEntity.aliases.map(\.name)
                    return names.contains(where: {
                        $0.count >= 3 && text.localizedCaseInsensitiveContains($0)
                    }) ? target.profile : nil
                })
            }
        }
    }

    private static func relationshipKind(_ text: String) -> String {
        let lowercased = text.lowercased()
        if lowercased.contains("romantic") || lowercased.contains("love") { return "romantic" }
        if lowercased.contains("friend") { return "friend" }
        if lowercased.contains("coworker") || lowercased.contains("colleague") { return "colleague" }
        if lowercased.contains("family") || lowercased.contains("father") ||
            lowercased.contains("mother") || lowercased.contains("brother") ||
            lowercased.contains("sister") {
            return "family"
        }
        if lowercased.contains("antagonist") || lowercased.contains("enemy") { return "antagonist" }
        if lowercased.contains("mentor") || lowercased.contains("master") { return "mentor" }
        return "other"
    }

    private static func normalizedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private func upsertGalleryItem(
        resource: ContentResource,
        sourceDocument: Document?,
        title: String,
        orderIndex: Int64,
        project: WritingProject,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        let itemID = DeterministicID.make(namespace: project.id, name: "gallery:\(resource.id)")
        _ = try store.galleryItems.upsert(id: itemID) { item, isNew in
            if isNew { inserted += 1 } else { updated += 1 }
            if isNew {
                item.title = title
                item.source = ProvenanceAgent.sourceImport.rawValue
                item.orderIndex = orderIndex
                item.createdAt = sourceDocument?.createdAt ?? Date()
                item.modifiedAt = sourceDocument?.modifiedAt ?? Date()
            }
            item.project = project
            item.resource = resource
            item.sourceDocument = sourceDocument
        }
    }

    private func importEmbeddedImages(
        from rtfData: Data,
        sourceDocument: Document,
        project: WritingProject,
        startingOrderIndex: Int64,
        importedResourceCount: inout Int,
        inserted: inout Int,
        updated: inout Int
    ) throws {
        let images = Self.embeddedImages(fromRTF: rtfData)

        for (index, image) in images.enumerated() {
            let sourcePath = "Embedded/\(sourceDocument.id.uuidString)/\(index).\(image.extensionName)"
            let resourceID = DeterministicID.make(namespace: project.id, name: "resource:\(sourcePath)")
            let digest = SHA256.hash(data: image.data).hex
            let resource = try store.resources.upsert(id: resourceID) { resource, isNew in
                if isNew { inserted += 1 } else { updated += 1 }
                resource.sourcePath = sourcePath
                resource.role = "embeddedImage"
                resource.mediaType = image.mediaType
                resource.byteCount = Int64(image.data.count)
                resource.sha256 = digest
                resource.data = image.data
                resource.isSourcePreserved = false
                resource.project = project
                resource.document = sourceDocument
            }
            try upsertGalleryItem(
                resource: resource,
                sourceDocument: sourceDocument,
                title: images.count == 1
                    ? sourceDocument.title
                    : "\(sourceDocument.title) \(index + 1)",
                orderIndex: startingOrderIndex + Int64(index),
                project: project,
                inserted: &inserted,
                updated: &updated
            )
            importedResourceCount += 1
        }
    }

    private static func embeddedImages(
        fromRTF data: Data
    ) -> [(data: Data, mediaType: String, extensionName: String)] {
        guard let source = String(data: data, encoding: .ascii) else { return [] }
        let formats: [(controlWord: String, mediaType: String, extensionName: String)] = [
            ("jpegblip", "image/jpeg", "jpg"),
            ("pngblip", "image/png", "png")
        ]
        return formats.flatMap { format -> [(data: Data, mediaType: String, extensionName: String)] in
            let (controlWord, mediaType, extensionName) = format
            let pattern = #"\\\#(controlWord)\s+([0-9a-fA-F\s]+)"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(source.startIndex..., in: source)
            return expression.matches(in: source, range: range).compactMap { match in
                guard let hexRange = Range(match.range(at: 1), in: source) else { return nil }
                let hex = source[hexRange].filter(\.isHexDigit)
                guard hex.count.isMultiple(of: 2) else { return nil }
                var imageData = Data(capacity: hex.count / 2)
                var index = hex.startIndex
                while index < hex.endIndex {
                    let next = hex.index(index, offsetBy: 2)
                    guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
                    imageData.append(byte)
                    index = next
                }
                return (imageData, mediaType, extensionName)
            }
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

private struct CharacterCard {
    struct Measurement {
        let name: String
        let value: String
        let unit: String?
        let notes: String?
    }

    static let headings = [
        "Character Name", "Age • Location", "Role in Story", "Narrative Function",
        "Goal", "Skills", "Physical Description", "Personality", "Occupation",
        "Habits/Mannerisms", "Background", "Internal Conflicts",
        "External Conflicts", "Key Relationships", "Notes"
    ]

    let fullName: String
    let firstName: String
    let middleName: String?
    let lastName: String?
    let aliases: [String]
    let age: Int?
    let ageText: String?
    let location: String?
    let height: String?
    let weight: String?
    let sections: [String: String]
    let measurements: [Measurement]
    let unmappedText: String?

    static func looksLikeCard(_ text: String) -> Bool {
        let normalized = clean(text)
        return headings.filter { normalized.localizedCaseInsensitiveContains($0) }.count >= 3
    }

    init(text: String, fallbackName: String) {
        let cleaned = Self.clean(text)
        var preamble: [String] = []
        var values: [String: [String]] = [:]
        var currentHeading: String?

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let match = Self.headingMatch(line) {
                currentHeading = match.heading
                if !match.value.isEmpty {
                    values[match.heading, default: []].append(match.value)
                }
            } else if let currentHeading {
                values[currentHeading, default: []].append(line)
            } else {
                preamble.append(line)
            }
        }

        sections = values.mapValues { $0.joined(separator: "\n") }
        let remainder = preamble.dropFirst(2).joined(separator: "\n")
        unmappedText = remainder.isEmpty ? nil : remainder
        let rawName = sections["Character Name"] ?? preamble.first ?? fallbackName
        let nameParts = rawName.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("Character Name") != .orderedSame }
        let selectedName = nameParts.first(where: { $0.split(separator: " ").count >= 2 })
            ?? nameParts.first
            ?? fallbackName
        let components = selectedName.split(whereSeparator: \.isWhitespace).map(String.init)
        firstName = components.first ?? selectedName
        lastName = components.count > 1 ? components.last : nil
        middleName = components.count > 2
            ? components.dropFirst().dropLast().joined(separator: " ")
            : nil
        fullName = selectedName
        aliases = Array(Set(nameParts.filter {
            $0.caseInsensitiveCompare(selectedName) != .orderedSame
        })).sorted()

        let ageLocation = sections["Age • Location"] ?? preamble.dropFirst().first
        let ageLocationParts = ageLocation?.components(separatedBy: "•") ?? []
        let rawAge = ageLocationParts.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Age:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ageText = rawAge?.isEmpty == false ? rawAge : nil
        if let rawAge,
           let match = rawAge.range(of: #"^\d{1,3}$"#, options: .regularExpression) {
            age = Int(rawAge[match])
        } else {
            age = nil
        }
        location = ageLocationParts.count > 1
            ? ageLocationParts.dropFirst().joined(separator: "•")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        let physical = sections["Physical Description"] ?? ""
        height = Self.firstMatch(
            in: physical,
            pattern: #"\b\d+(?:\.\d+)?\s*(?:cm|centimet(?:er|re)s?|feet|ft)\b|\b\d+\s*[’']\s*\d+(?:\s*[”"])?\b"#
        )
        weight = Self.firstMatch(
            in: physical,
            pattern: #"\b\d+(?:\.\d+)?\s*(?:kg|kilograms?|lbs?|pounds?)\b"#
        )
        measurements = Self.measurements(in: physical)
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<[^>]*Scr[^>]*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func headingMatch(_ line: String) -> (heading: String, value: String)? {
        for heading in headings.sorted(by: { $0.count > $1.count }) {
            guard line.range(of: heading, options: [.anchored, .caseInsensitive]) != nil else {
                continue
            }
            var remainder = String(line.dropFirst(heading.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.first == ":" {
                remainder.removeFirst()
                remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (heading, remainder)
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let range = text.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        return String(text[range])
    }

    private static func measurements(in physicalDescription: String) -> [Measurement] {
        let unitPattern = #"\b\d+(?:\.\d+)?\s*(?:cm|mm|kg|lbs?|inches?|feet|ft)\b|\b\d+\s*[’']\s*\d+"#
        var result: [Measurement] = []
        for line in physicalDescription.components(separatedBy: .newlines) {
            guard line.range(of: unitPattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String
            if let separator = trimmed.firstIndex(of: ":") {
                name = String(trimmed[..<separator])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-* \t"))
            } else if trimmed.localizedCaseInsensitiveContains("height") {
                name = "Height"
            } else if trimmed.localizedCaseInsensitiveContains("weight") {
                name = "Weight"
            } else {
                name = "Imported Measurement"
            }
            result.append(Measurement(
                name: name.isEmpty ? "Imported Measurement" : name,
                value: trimmed,
                unit: nil,
                notes: "Imported from Physical Description"
            ))
        }
        return result
    }
}

private struct ParsedSectionType {
    let id: String
    let title: String
}

private struct ParsedLabel {
    let id: String
    let title: String
    let color: String?
}

private struct ParsedStatus {
    let id: String
    let title: String
}

private struct ParsedCustomField {
    let id: String
    let title: String
    let type: String
}

private struct ParsedScrivenerProject {
    let identifier: String
    let attributes: [String: String]
    let items: [BinderItemRecord]
    let sectionTypes: [ParsedSectionType]
    let labels: [ParsedLabel]
    let defaultLabelID: String?
    let statuses: [ParsedStatus]
    let defaultStatusID: String?
    let customFields: [ParsedCustomField]
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

    private var sectionTypes: [ParsedSectionType] = []
    private var labels: [ParsedLabel] = []
    private var defaultLabelID: String?
    private var statuses: [ParsedStatus] = []
    private var defaultStatusID: String?
    private var customFields: [ParsedCustomField] = []
    private var pendingAttributes: [String: String] = [:]
    private var currentMetaDataFieldID: String?
    private var currentMetaDataFieldType: String?

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
            items: reader.items,
            sectionTypes: reader.sectionTypes,
            labels: reader.labels,
            defaultLabelID: reader.defaultLabelID,
            statuses: reader.statuses,
            defaultStatusID: reader.defaultStatusID,
            customFields: reader.customFields
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
        } else if elementName == "Type", elementPath.count >= 2, elementPath[elementPath.count - 2] == "TypeDefinitions" {
            pendingAttributes = attributeDict
        } else if elementName == "Label", elementPath.count >= 2, elementPath[elementPath.count - 2] == "Labels" {
            pendingAttributes = attributeDict
        } else if elementName == "Status", elementPath.count >= 2, elementPath[elementPath.count - 2] == "StatusItems" {
            pendingAttributes = attributeDict
        } else if elementName == "MetaDataField", elementPath.count >= 2, elementPath[elementPath.count - 2] == "CustomMetaDataSettings" {
            currentMetaDataFieldID = attributeDict["ID"]
            currentMetaDataFieldType = attributeDict["Type"] ?? "Text"
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        handleProjectSettingsEnd(elementName: elementName, trimmed: trimmed)
        guard !stack.isEmpty else { return }
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

    /// Captures the project-level `SectionTypes`, `LabelSettings`, `StatusSettings`, and
    /// `CustomMetaDataSettings` blocks, which sit as siblings of `Binder` under the project root
    /// and define the vocabularies used elsewhere via `MetaData/SectionType`, `MetaData/LabelID`,
    /// `MetaData/StatusID`, and `MetaData/CustomMetaData`.
    private func handleProjectSettingsEnd(elementName: String, trimmed: String) {
        if elementName == "Type", elementPath.count >= 2, elementPath[elementPath.count - 2] == "TypeDefinitions" {
            if let id = pendingAttributes["ID"] {
                sectionTypes.append(ParsedSectionType(id: id, title: trimmed))
            }
            pendingAttributes = [:]
        } else if elementName == "Label", elementPath.count >= 2, elementPath[elementPath.count - 2] == "Labels" {
            if let id = pendingAttributes["ID"] {
                labels.append(ParsedLabel(id: id, title: trimmed, color: pendingAttributes["Color"]))
            }
            pendingAttributes = [:]
        } else if elementName == "DefaultLabelID", elementPath.count >= 1, elementPath[elementPath.count - 1] == "DefaultLabelID" {
            defaultLabelID = trimmed
        } else if elementName == "Status", elementPath.count >= 2, elementPath[elementPath.count - 2] == "StatusItems" {
            if let id = pendingAttributes["ID"] {
                statuses.append(ParsedStatus(id: id, title: trimmed))
            }
            pendingAttributes = [:]
        } else if elementName == "DefaultStatusID", elementPath.count >= 1, elementPath[elementPath.count - 1] == "DefaultStatusID" {
            defaultStatusID = trimmed
        } else if elementName == "Title", elementPath.count >= 2, elementPath[elementPath.count - 2] == "MetaDataField",
                  let id = currentMetaDataFieldID {
            customFields.append(ParsedCustomField(id: id, title: trimmed, type: currentMetaDataFieldType ?? "Text"))
            currentMetaDataFieldID = nil
            currentMetaDataFieldType = nil
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
