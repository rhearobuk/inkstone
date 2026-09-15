import Foundation

/// Renderer-neutral output families supported by export templates.
public enum ExportOutputFormat: String, Codable, CaseIterable, Sendable, Hashable {
    case docx
    case epub
    case pdf
}

public enum ExportTemplatePurpose: String, Codable, Sendable, Hashable {
    case manuscriptSubmission
    case ebook
    case readingProof
    case printInterior
}

public enum ExportPageSize: String, Codable, Sendable, Hashable {
    case usLetter
    case a4
}

public enum ExportBreak: String, Codable, Sendable, Hashable {
    case none
    case page
    case section
}

public enum ExportNumberingStyle: String, Codable, Sendable, Hashable {
    case none
    case arabic
    case roman
    case spelledOut
}

public enum ExportAlignment: String, Codable, Sendable, Hashable {
    case leading
    case center
    case trailing
    case justified
}

public enum ExportTextTransform: String, Codable, Sendable, Hashable {
    case none
    case uppercase
}

public struct ExportSemanticStyle: Codable, Sendable, Hashable {
    public let fontFamily: String?
    public let fontSize: Double?
    public let weight: String?
    public let alignment: ExportAlignment?
    public let firstLineIndent: Double?
    public let lineSpacing: Double?
    public let spacingBefore: Double?
    public let spacingAfter: Double?
    public let textTransform: ExportTextTransform?
}

/// Physical-page guidance for paginated future renderers, expressed without renderer instructions.
public struct ExportPageLayout: Codable, Sendable, Hashable {
    public let marginTop: Double
    public let marginBottom: Double
    public let marginLeading: Double
    public let marginTrailing: Double
}

public struct ExportNarrativeRule: Codable, Sendable, Hashable {
    public let displaysTitle: Bool
    public let displaysSubtitle: Bool
    public let headingStyle: String?
    public let breakBefore: ExportBreak
    public let appearsInNavigation: Bool
    public let numbering: ExportNumberingStyle
    public let insertsSceneBreakBefore: Bool
    public let sceneBreakMarker: String?
}

public enum TemplateFormatter: String, Codable, Sendable, Hashable {
    case number
    case approximateWordCount
    case roundedHundredWordCount
    case year
    case shortDate
    case longDate
}

public struct TemplateCondition: Codable, Sendable, Hashable {
    public let requiresTag: String
}

public struct ExportTemplateComponent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let style: String
    public let tag: String
    public let formatter: TemplateFormatter?
    public let condition: TemplateCondition?
}

public struct ExportHeaderFooter: Codable, Sendable, Hashable {
    public let header: [ExportTemplateComponent]
    public let footer: [ExportTemplateComponent]
}

public struct ExportMetadataRequirements: Codable, Sendable, Hashable {
    public let requiredTags: [String]
    public let recommendedTags: [String]
}

/// Immutable, versioned publishing convention. It has no project-specific settings or renderer markup.
public struct ExportTemplate: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let version: Int
    public let displayName: String
    public let description: String
    public let purpose: ExportTemplatePurpose
    public let supportedFormats: [ExportOutputFormat]
    public let supportedPageSizes: [ExportPageSize]
    public let pageLayout: ExportPageLayout?
    public let metadataRequirements: ExportMetadataRequirements
    public let frontMatter: [ExportTemplateComponent]
    public let backMatter: [ExportTemplateComponent]
    public let headerFooter: ExportHeaderFooter
    public let styles: [String: ExportSemanticStyle]
    public let narrativeRules: [String: ExportNarrativeRule]
}

public enum TemplateValueKind: String, Codable, Sendable, Hashable {
    case text
    case integer
    case date
    case asset
    case lateBound
}

public enum TemplateResolutionPhase: String, Codable, Sendable, Hashable {
    case template
    case renderer
}

public enum TemplateContext: String, Codable, Sendable, Hashable {
    case book
    case section
    case chapter
    case scene
    case headerFooter
}

public struct TemplateTagDefinition: Sendable, Hashable {
    public let name: String
    public let valueKind: TemplateValueKind
    public let contexts: Set<TemplateContext>
    public let phase: TemplateResolutionPhase
}

/// The single authority for legal tags, their values, contexts, and resolution phase.
public enum ExportTemplateTagRegistry {
    public static let definitions: [String: TemplateTagDefinition] = {
        func text(_ name: String, _ contexts: Set<TemplateContext> = [.book, .headerFooter]) -> TemplateTagDefinition {
            TemplateTagDefinition(name: name, valueKind: .text, contexts: contexts, phase: .template)
        }
        func integer(_ name: String, _ contexts: Set<TemplateContext>) -> TemplateTagDefinition {
            TemplateTagDefinition(name: name, valueKind: .integer, contexts: contexts, phase: .template)
        }
        func asset(_ name: String) -> TemplateTagDefinition {
            TemplateTagDefinition(name: name, valueKind: .asset, contexts: [.book], phase: .template)
        }
        var result = Dictionary(uniqueKeysWithValues: [
            text("book.title"), text("book.subtitle"), text("book.author"), text("book.publisher"),
            text("book.language"), text("book.edition"), text("book.copyright"), text("book.series.name"),
            text("book.author.address"), text("book.author.phone"), text("book.author.email"),
            text("book.agent.name"), text("book.agent.agency"), text("book.agent.address"), text("book.agent.phone"), text("book.agent.email"),
            text("publication.fictionDisclaimer"), text("publication.copyrightStatement"),
            text("publication.allRightsReserved"),
            TemplateTagDefinition(name: "book.publicationDate", valueKind: .date, contexts: [.book], phase: .template),
            integer("book.series.volume", [.book]), text("publication.isbn"), text("publication.isbns"), asset("publication.cover"),
            integer("manuscript.wordCount", [.book]), integer("manuscript.wordCount.approximate", [.book]),
            integer("manuscript.wordCount.roundedHundred", [.book]),
            TemplateTagDefinition(name: "export.date", valueKind: .date, contexts: [.book, .headerFooter], phase: .template),
            TemplateTagDefinition(name: "export.year", valueKind: .date, contexts: [.book, .headerFooter], phase: .template),
            text("section.title", [.section]), text("section.subtitle", [.section]),
            integer("section.wordCount", [.section]), integer("section.number", [.section]),
            text("chapter.title", [.chapter, .headerFooter]), text("chapter.subtitle", [.chapter]),
            integer("chapter.wordCount", [.chapter]), integer("chapter.number", [.chapter]),
            text("scene.title", [.scene]), integer("scene.wordCount", [.scene]),
            TemplateTagDefinition(name: "page.number", valueKind: .lateBound, contexts: [.headerFooter], phase: .renderer),
            TemplateTagDefinition(name: "page.total", valueKind: .lateBound, contexts: [.headerFooter], phase: .renderer)
        ].map { ($0.name, $0) })
        for format in BookFormat.allCases {
            result["book.isbn.\(format.rawValue)"] = text("book.isbn.\(format.rawValue)")
        }
        for kind in BookCoverKind.allCases {
            result["book.cover.\(kind.rawValue)"] = asset("book.cover.\(kind.rawValue)")
        }
        return result
    }()

    public static func definition(for tag: String) -> TemplateTagDefinition? {
        definitions[tag]
    }
}

public enum ExportTemplateValidationIssue: Error, Hashable, Sendable {
    case invalidVersion(templateID: String)
    case noSupportedFormats(templateID: String)
    case duplicateIdentifierVersion(id: String, version: Int)
    case unknownTag(componentID: String, tag: String)
    case invalidTagContext(componentID: String, tag: String)
    case illegalLateBoundTag(componentID: String, tag: String)
    case missingStyle(componentID: String, style: String)
    case missingNarrativeRule(String)
    case invalidNarrativeRule(String)
    case missingRequiredComponent(String)
}

public enum ExportTemplateValidator {
    public static func validate(_ templates: [ExportTemplate]) -> [ExportTemplateValidationIssue] {
        var issues: [ExportTemplateValidationIssue] = []
        var identifiers = Set<String>()
        for template in templates {
            if template.version < 1 { issues.append(.invalidVersion(templateID: template.id)) }
            if template.supportedFormats.isEmpty { issues.append(.noSupportedFormats(templateID: template.id)) }
            if !identifiers.insert("\(template.id)#\(template.version)").inserted {
                issues.append(.duplicateIdentifierVersion(id: template.id, version: template.version))
            }
            for type in ["book", "section", "chapter", "scene"] {
                guard let rule = template.narrativeRules[type] else {
                    issues.append(.missingNarrativeRule(type))
                    continue
                }
                if rule.headingStyle != nil && template.styles[rule.headingStyle!] == nil {
                    issues.append(.invalidNarrativeRule(type))
                }
            }
            let components = template.frontMatter + template.backMatter + template.headerFooter.header + template.headerFooter.footer
            if template.frontMatter.isEmpty { issues.append(.missingRequiredComponent("frontMatter")) }
            for component in components {
                if template.styles[component.style] == nil {
                    issues.append(.missingStyle(componentID: component.id, style: component.style))
                }
                validate(tag: component.tag, component: component, context: context(for: component), issues: &issues)
                if let condition = component.condition {
                    validate(tag: condition.requiresTag, component: component, context: context(for: component), issues: &issues)
                }
            }
            for tag in template.metadataRequirements.requiredTags + template.metadataRequirements.recommendedTags {
                guard ExportTemplateTagRegistry.definition(for: tag) != nil else {
                    issues.append(.unknownTag(componentID: "metadataRequirements", tag: tag))
                    continue
                }
            }
        }
        return issues
    }

    private static func validate(tag: String, component: ExportTemplateComponent, context: TemplateContext, issues: inout [ExportTemplateValidationIssue]) {
        guard let definition = ExportTemplateTagRegistry.definition(for: tag) else {
            issues.append(.unknownTag(componentID: component.id, tag: tag))
            return
        }
        if definition.phase == .renderer && context != .headerFooter {
            issues.append(.illegalLateBoundTag(componentID: component.id, tag: tag))
        }
        guard definition.contexts.contains(context) else {
            issues.append(.invalidTagContext(componentID: component.id, tag: tag))
            return
        }
    }

    private static func context(for component: ExportTemplateComponent) -> TemplateContext {
        if component.id.hasPrefix("header.") || component.id.hasPrefix("footer.") { return .headerFooter }
        if component.tag.hasPrefix("section.") { return .section }
        if component.tag.hasPrefix("chapter.") { return .chapter }
        if component.tag.hasPrefix("scene.") { return .scene }
        return .book
    }
}

public enum ExportTemplateLoaderError: Error, Equatable {
    case invalidTemplateResources
    case validationFailed([ExportTemplateValidationIssue])
}

public enum ExportTemplateLoader {
    public static func builtIns() throws -> [ExportTemplate] {
        let names = ["StandardManuscriptSubmissionV1", "StandardNovelEbookV1", "ReadingProofV1"]
        let templates = try names.map { name -> ExportTemplate in
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                throw ExportTemplateLoaderError.invalidTemplateResources
            }
            return try JSONDecoder().decode(ExportTemplate.self, from: data)
        }
        let issues = ExportTemplateValidator.validate(templates)
        guard issues.isEmpty else { throw ExportTemplateLoaderError.validationFailed(issues) }
        return templates
    }
}

public enum TemplateValue: Sendable, Hashable {
    case text(String)
    case integer(Int64)
    case date(Date)
    case asset(ExportCoverAsset)
    case lateBound(String)

    public var isPresent: Bool {
        switch self {
        case .text(let value): !value.isEmpty
        default: true
        }
    }
}

public struct ExportTemplateParameters: Sendable, Hashable {
    public let outputFormat: ExportOutputFormat
    public let pageSize: ExportPageSize?
    /// The user-selected ISBN format for a proof PDF. Ebook output always selects `.ebook`.
    public let publicationISBNFormat: BookFormat?
    public let exportDate: Date

    public init(
        outputFormat: ExportOutputFormat,
        pageSize: ExportPageSize? = nil,
        publicationISBNFormat: BookFormat? = nil,
        exportDate: Date = Date()
    ) {
        self.outputFormat = outputFormat
        self.pageSize = pageSize
        self.publicationISBNFormat = publicationISBNFormat
        self.exportDate = exportDate
    }
}

public enum ExportReadiness: Sendable, Hashable {
    case templateInvalid([ExportTemplateValidationIssue])
    case blocked(missingRequiredTags: [String])
    case ready(warnings: [String])
}

public struct ResolvedTemplateComponent: Sendable, Hashable, Identifiable {
    public let id: String
    public let style: String
    public let value: TemplateValue
    public let formatter: TemplateFormatter?
}

public struct ResolvedNarrativeItem: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let narrativeType: NarrativeType
    public let title: String
    public let subtitle: String?
    public let epigraph: String?
    public let wordCount: Int64
    public let rule: ExportNarrativeRule
    public let number: Int
    public let prose: [ExportProseBlock]

    public init(
        id: UUID,
        narrativeType: NarrativeType,
        title: String,
        subtitle: String?,
        epigraph: String? = nil,
        wordCount: Int64,
        rule: ExportNarrativeRule,
        number: Int,
        prose: [ExportProseBlock]
    ) {
        self.id = id
        self.narrativeType = narrativeType
        self.title = title
        self.subtitle = subtitle
        self.epigraph = epigraph
        self.wordCount = wordCount
        self.rule = rule
        self.number = number
        self.prose = prose
    }
}

/// Immutable bridge from an export snapshot and a template to future format renderers.
public struct ResolvedPublication: Sendable, Hashable {
    public let templateID: String
    public let templateVersion: Int
    public let outputFormat: ExportOutputFormat
    public let pageSize: ExportPageSize?
    public let pageLayout: ExportPageLayout?
    public let readiness: ExportReadiness
    public let styles: [String: ExportSemanticStyle]
    public let frontMatter: [ResolvedTemplateComponent]
    public let backMatter: [ResolvedTemplateComponent]
    public let header: [ResolvedTemplateComponent]
    public let footer: [ResolvedTemplateComponent]
    public let narrative: [ResolvedNarrativeItem]
    /// Resolved publication tags needed by format renderers but not necessarily displayed in template components.
    public let metadata: [String: TemplateValue]
    public let diagnostics: [String]

    public init(
        templateID: String,
        templateVersion: Int,
        outputFormat: ExportOutputFormat,
        pageSize: ExportPageSize?,
        pageLayout: ExportPageLayout? = nil,
        readiness: ExportReadiness,
        styles: [String: ExportSemanticStyle],
        frontMatter: [ResolvedTemplateComponent],
        backMatter: [ResolvedTemplateComponent],
        header: [ResolvedTemplateComponent],
        footer: [ResolvedTemplateComponent],
        narrative: [ResolvedNarrativeItem],
        metadata: [String: TemplateValue] = [:],
        diagnostics: [String]
    ) {
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.outputFormat = outputFormat
        self.pageSize = pageSize
        self.pageLayout = pageLayout
        self.readiness = readiness
        self.styles = styles
        self.frontMatter = frontMatter
        self.backMatter = backMatter
        self.header = header
        self.footer = footer
        self.narrative = narrative
        self.metadata = metadata
        self.diagnostics = diagnostics
    }
}

public enum ExportTemplateResolver {
    public static func resolve(
        publication: ExportPublication,
        template: ExportTemplate,
        parameters: ExportTemplateParameters
    ) -> ResolvedPublication {
        let templateIssues = ExportTemplateValidator.validate([template])
        let readiness = readiness(
            for: publication,
            template: template,
            parameters: parameters,
            templateIssues: templateIssues
        )
        let all = publication.documents
        var counters: [NarrativeType: Int] = [:]
        let narrative = all.compactMap { document -> ResolvedNarrativeItem? in
            guard let rule = template.narrativeRules[document.narrativeType.rawValue] else { return nil }
            counters[document.narrativeType, default: 0] += 1
            return ResolvedNarrativeItem(
                id: document.id, narrativeType: document.narrativeType, title: document.title,
                subtitle: document.metadata.subtitle, epigraph: document.metadata.epigraph,
                wordCount: document.wordCount, rule: rule,
                number: counters[document.narrativeType]!, prose: document.prose
            )
        }
        return ResolvedPublication(
            templateID: template.id, templateVersion: template.version, outputFormat: parameters.outputFormat,
            pageSize: parameters.pageSize, pageLayout: template.pageLayout, readiness: readiness, styles: template.styles,
            frontMatter: components(template.frontMatter, publication: publication, parameters: parameters),
            backMatter: components(template.backMatter, publication: publication, parameters: parameters),
            header: components(template.headerFooter.header, publication: publication, parameters: parameters),
            footer: components(template.headerFooter.footer, publication: publication, parameters: parameters),
            narrative: narrative,
            metadata: resolvedMetadata(publication: publication, parameters: parameters),
            diagnostics: publication.diagnostics.map(\.message)
        )
    }

    private static func resolvedMetadata(publication: ExportPublication, parameters: ExportTemplateParameters) -> [String: TemplateValue] {
        Dictionary(uniqueKeysWithValues: ExportTemplateTagRegistry.definitions.keys.compactMap { tag in
            guard tag.hasPrefix("book.") || tag.hasPrefix("publication.") else { return nil }
            return value(for: tag, publication: publication, document: nil, parameters: parameters).map { (tag, $0) }
        })
    }

    private static func readiness(for publication: ExportPublication, template: ExportTemplate, parameters: ExportTemplateParameters, templateIssues: [ExportTemplateValidationIssue]) -> ExportReadiness {
        guard templateIssues.isEmpty else { return .templateInvalid(templateIssues) }
        let missingRequired = template.metadataRequirements.requiredTags.filter {
            value(for: $0, publication: publication, document: nil, parameters: parameters) == nil
        }
        guard missingRequired.isEmpty else { return .blocked(missingRequiredTags: missingRequired) }
        let warnings = template.metadataRequirements.recommendedTags.compactMap { tag in
            value(for: tag, publication: publication, document: nil, parameters: parameters) == nil
                ? "Recommended publication data is missing: \(tag)." : nil
        }
        return .ready(warnings: warnings)
    }

    private static func components(_ definitions: [ExportTemplateComponent], publication: ExportPublication, parameters: ExportTemplateParameters) -> [ResolvedTemplateComponent] {
        definitions.compactMap { component in
            if let condition = component.condition,
               value(for: condition.requiresTag, publication: publication, document: nil, parameters: parameters) == nil {
                return nil
            }
            guard let value = value(for: component.tag, publication: publication, document: nil, parameters: parameters) else {
                return nil
            }
            return ResolvedTemplateComponent(id: component.id, style: component.style, value: value, formatter: component.formatter)
        }
    }

    public static func value(for tag: String, publication: ExportPublication, document: ExportDocument?, parameters: ExportTemplateParameters) -> TemplateValue? {
        let book = publication.book
        switch tag {
        case "book.title": return book.map { .text($0.title) }
        case "book.subtitle": return book?.metadata.subtitle.map(TemplateValue.text)
        case "book.author": return publication.project.contactInformation.author.map(TemplateValue.text) ?? book?.metadata.author.map(TemplateValue.text) ?? publication.project.author.map(TemplateValue.text)
        case "book.author.address": return publication.project.contactInformation.authorAddress.map(TemplateValue.text) ?? book?.metadata.authorAddress.map(TemplateValue.text)
        case "book.author.phone": return publication.project.contactInformation.authorPhone.map(TemplateValue.text) ?? book?.metadata.authorPhone.map(TemplateValue.text)
        case "book.author.email": return publication.project.contactInformation.authorEmail.map(TemplateValue.text) ?? book?.metadata.authorEmail.map(TemplateValue.text)
        case "book.agent.name": return publication.project.contactInformation.agentName.map(TemplateValue.text) ?? book?.metadata.agentName.map(TemplateValue.text)
        case "book.agent.agency": return publication.project.contactInformation.agency.map(TemplateValue.text)
        case "book.agent.address": return publication.project.contactInformation.agentAddress.map(TemplateValue.text) ?? book?.metadata.agentAddress.map(TemplateValue.text)
        case "book.agent.phone": return publication.project.contactInformation.agentPhone.map(TemplateValue.text) ?? book?.metadata.agentPhone.map(TemplateValue.text)
        case "book.agent.email": return publication.project.contactInformation.agentEmail.map(TemplateValue.text) ?? book?.metadata.agentEmail.map(TemplateValue.text)
        case "book.publisher": return book?.metadata.publisher.map(TemplateValue.text)
        case "book.language": return book?.metadata.language.map(TemplateValue.text)
        case "book.edition": return book?.metadata.edition.map(TemplateValue.text)
        case "book.copyright": return book?.metadata.copyright.map(TemplateValue.text)
        case "book.publicationDate": return book?.metadata.publicationDate.map(TemplateValue.date)
        case "book.series.name": return book?.metadata.seriesName.map(TemplateValue.text)
        case "book.series.volume": return book?.metadata.volumeNumber.map(TemplateValue.integer)
        case "publication.isbn":
            return isbn(
                for: parameters.outputFormat,
                selectedFormat: parameters.publicationISBNFormat,
                book: book
            ).map(TemplateValue.text)
        case "publication.isbns":
            let values = BookFormat.allCases.compactMap { format -> String? in
                guard let number = book?.metadata.isbns.first(where: { $0.format == format })?.number,
                      !number.isEmpty else {
                    return nil
                }
                return "ISBN \(number) (\(format.displayName))"
            }
            return values.isEmpty ? nil : .text(values.joined(separator: "\n"))
        case "publication.cover":
            return book?.metadata.covers.first(where: { $0.kind == .front }).map(TemplateValue.asset)
        case "publication.fictionDisclaimer":
            guard let book else { return nil }
            let name = book.metadata.seriesName.map { "\($0): \(book.title)" } ?? book.title
            return .text("\(name) is a work of fiction. Names, characters, places, and incidents are the products of the author's imagination or are used fictitiously. Any resemblance to actual events, locales, or persons, living or dead, is entirely coincidental.")
        case "publication.copyrightStatement":
            guard let book, let author = publication.project.contactInformation.author ?? book.metadata.author ?? publication.project.author else { return nil }
            let year = Calendar.current.component(.year, from: book.metadata.publicationDate ?? parameters.exportDate)
            return .text("Copyright © \(year) by \(author)")
        case "publication.allRightsReserved":
            return .text("All rights reserved.")
        case "manuscript.wordCount": return .integer(publication.documents.reduce(0) { $0 + $1.wordCount })
        case "manuscript.wordCount.approximate":
            return .integer(approximateWordCount(publication.documents.reduce(0) { $0 + $1.wordCount }))
        case "manuscript.wordCount.roundedHundred":
            return .integer(roundedHundredWordCount(publication.documents.reduce(0) { $0 + $1.wordCount }))
        case "export.date": return .date(parameters.exportDate)
        case "export.year": return .date(parameters.exportDate)
        case "page.number", "page.total": return .lateBound(tag)
        case "section.title": return document?.narrativeType == .section ? .text(document!.title) : nil
        case "section.subtitle": return document?.narrativeType == .section ? document!.metadata.subtitle.map(TemplateValue.text) : nil
        case "section.wordCount": return document?.narrativeType == .section ? .integer(document!.wordCount) : nil
        case "section.number": return document?.narrativeType == .section ? .integer(number(of: document!, in: publication)) : nil
        case "chapter.title": return document?.narrativeType == .chapter ? .text(document!.title) : nil
        case "chapter.subtitle": return document?.narrativeType == .chapter ? document!.metadata.subtitle.map(TemplateValue.text) : nil
        case "chapter.wordCount": return document?.narrativeType == .chapter ? .integer(document!.wordCount) : nil
        case "chapter.number": return document?.narrativeType == .chapter ? .integer(number(of: document!, in: publication)) : nil
        case "scene.title": return document?.narrativeType == .scene ? .text(document!.title) : nil
        case "scene.wordCount": return document?.narrativeType == .scene ? .integer(document!.wordCount) : nil
        default:
            if tag.hasPrefix("book.isbn."), let format = BookFormat(rawValue: String(tag.dropFirst("book.isbn.".count))) {
                return book?.metadata.isbns.first(where: { $0.format == format }).map { .text($0.number) }
            }
            if tag.hasPrefix("book.cover."), let kind = BookCoverKind(rawValue: String(tag.dropFirst("book.cover.".count))) {
                return book?.metadata.covers.first(where: { $0.kind == kind }).map(TemplateValue.asset)
            }
            return nil
        }
    }

    /// Manuscript convention: nearest 1,000 words, with anything below 1,000 reported exactly.
    public static func approximateWordCount(_ count: Int64) -> Int64 {
        guard count >= 1_000 else { return count }
        return ((count + 500) / 1_000) * 1_000
    }

    public static func roundedHundredWordCount(_ count: Int64) -> Int64 {
        ((count + 50) / 100) * 100
    }

    private static func isbn(
        for output: ExportOutputFormat,
        selectedFormat: BookFormat?,
        book: ExportBook?
    ) -> String? {
        let format: BookFormat
        if output == .epub {
            format = .ebook
        } else if let selectedFormat {
            format = selectedFormat
        } else {
            return nil
        }
        return book?.metadata.isbns.first(where: { $0.format == format })?.number
    }

    private static func number(of document: ExportDocument, in publication: ExportPublication) -> Int64 {
        Int64(
            publication.documents.prefix { $0.id != document.id }
                .filter { $0.narrativeType == document.narrativeType }
                .count + 1
        )
    }
}
