import CoreData
import XCTest
@testable import AuthorData

@MainActor
final class ExportTemplateTests: XCTestCase {
    func testBuiltInsLoadWithStableIDsAndFormats() throws {
        let templates = try ExportTemplateLoader.builtIns()
        XCTAssertEqual(templates.map(\.id), [
            "com.unit37.scribe.template.manuscript.standard",
            "com.rhearobuk.scribe.template.ebook.novel",
            "com.rhearobuk.scribe.template.proof.reading"
        ])
        XCTAssertEqual(templates.map(\.version), [1, 1, 1])
        XCTAssertEqual(templates[0].supportedFormats, [.docx, .pdf])
        XCTAssertEqual(templates[1].supportedFormats, [.epub])
    }

    func testValidatorRejectsUnknownTagsDuplicateVersionsAndLateBoundBodyTags() throws {
        let template = try ExportTemplateLoader.builtIns()[0]
        let unknown = replacing(template, frontMatter: [
            ExportTemplateComponent(id: "title.unknown", style: "bookTitle", tag: "book.unknown", formatter: nil, condition: nil)
        ])
        let lateBound = replacing(template, frontMatter: [
            ExportTemplateComponent(id: "title.page", style: "bookTitle", tag: "page.number", formatter: nil, condition: nil)
        ])
        let issues = ExportTemplateValidator.validate([template, template, unknown, lateBound])
        XCTAssertTrue(issues.contains(.duplicateIdentifierVersion(id: template.id, version: template.version)))
        XCTAssertTrue(issues.contains(.unknownTag(componentID: "title.unknown", tag: "book.unknown")))
        XCTAssertTrue(issues.contains(.invalidTagContext(componentID: "title.page", tag: "page.number")))
        XCTAssertTrue(issues.contains(.illegalLateBoundTag(componentID: "title.page", tag: "page.number")))
    }

    func testResolutionUsesBookMetadataTypedAssetsAndPublicationISBN() throws {
        let publication = publication(
            subtitle: "A Novel", language: "en", isbn: "978-0-123", cover: true
        )
        let ebook = try ExportTemplateLoader.builtIns()[1]
        let resolved = ExportTemplateResolver.resolve(
            publication: publication,
            template: ebook,
            parameters: ExportTemplateParameters(outputFormat: .epub, exportDate: Date(timeIntervalSince1970: 0))
        )
        guard case .ready(let warnings) = resolved.readiness else {
            return XCTFail("Complete required ebook metadata should be export-ready.")
        }
        XCTAssertEqual(warnings.count, 4)
        XCTAssertTrue(resolved.frontMatter.contains { if case .asset = $0.value { return true }; return false })
        XCTAssertTrue(resolved.frontMatter.contains {
            $0.id == "copyright.isbns" && $0.value == .text("ISBN 978-0-123 (E-Book)")
        })
        XCTAssertEqual(ExportTemplateResolver.value(for: "book.series.volume", publication: publication, document: nil, parameters: .init(outputFormat: .epub)), .integer(2))
    }

    func testOptionalConditionsAndRequirementsAreDistinguished() throws {
        let noOptionalData = publication(subtitle: nil, language: nil, isbn: nil, cover: false)
        let ebook = try ExportTemplateLoader.builtIns()[1]
        let resolved = ExportTemplateResolver.resolve(
            publication: noOptionalData, template: ebook, parameters: .init(outputFormat: .epub)
        )
        XCTAssertEqual(resolved.readiness, .blocked(missingRequiredTags: ["book.language"]))
        XCTAssertFalse(resolved.frontMatter.contains { $0.id == "title.subtitle" || $0.id == "copyright.isbns" || $0.id == "cover.front" })

        let manuscript = try ExportTemplateLoader.builtIns()[0]
        let recommendedOnly = ExportTemplateResolver.resolve(
            publication: noOptionalData, template: manuscript, parameters: .init(outputFormat: .pdf)
        )
        XCTAssertEqual(recommendedOnly.readiness, .ready(warnings: [
            "Recommended publication data is missing: book.subtitle.",
            "Recommended publication data is missing: book.language."
        ]))
    }

    func testManuscriptUsesApplicationContactInformation() throws {
        let contactInformation = ExportContactInformation(
            author: "A. Writer",
            authorAddress: "10 Author Lane\nLondon",
            authorPhone: "555-0100",
            authorEmail: "author@example.com",
            agentName: "Alex Agent",
            agency: "The Agency",
            agentAddress: "20 Agency Street\nNew York",
            agentPhone: "555-0200",
            agentEmail: "agent@example.com"
        )
        let manuscript = try ExportTemplateLoader.builtIns()[0]
        let resolved = ExportTemplateResolver.resolve(
            publication: publication(
                subtitle: nil,
                language: "en",
                isbn: nil,
                cover: false,
                contactInformation: contactInformation
            ),
            template: manuscript,
            parameters: .init(outputFormat: .docx, pageSize: .usLetter)
        )

        XCTAssertEqual(resolved.frontMatter.first { $0.id == "title.author" }?.value, .text("A. Writer"))
        XCTAssertEqual(resolved.frontMatter.first { $0.id == "contact.author.address" }?.value, .text("10 Author Lane\nLondon"))
        XCTAssertEqual(resolved.frontMatter.first { $0.id == "contact.agent.name" }?.value, .text("Alex Agent"))
        XCTAssertEqual(resolved.frontMatter.first { $0.id == "contact.agent.agency" }?.value, .text("The Agency"))
        XCTAssertEqual(resolved.frontMatter.first { $0.id == "contact.agent.email" }?.value, .text("agent@example.com"))
    }

    func testStatisticsScopeNarrativeRulesAndDeterminism() throws {
        let publication = publication(subtitle: nil, language: "en", isbn: nil, cover: false)
        let manuscript = try ExportTemplateLoader.builtIns()[0]
        let parameters = ExportTemplateParameters(outputFormat: .pdf, pageSize: .a4, exportDate: Date(timeIntervalSince1970: 1))
        let first = ExportTemplateResolver.resolve(publication: publication, template: manuscript, parameters: parameters)
        let second = ExportTemplateResolver.resolve(publication: publication, template: manuscript, parameters: parameters)
        XCTAssertEqual(first, second)
        XCTAssertEqual(ExportTemplateResolver.value(for: "manuscript.wordCount", publication: publication, document: nil, parameters: parameters), .integer(1_501))
        XCTAssertEqual(ExportTemplateResolver.approximateWordCount(1_501), 2_000)
        XCTAssertEqual(first.narrative.first { $0.narrativeType == .chapter }?.rule.breakBefore, .page)
        XCTAssertEqual(first.narrative.first { $0.narrativeType == .chapter }?.number, 1)
        XCTAssertEqual(first.narrative.first { $0.narrativeType == .scene }?.rule.insertsSceneBreakBefore, true)
    }

    func testBundledTemplateContentUsesConcreteV1Conventions() throws {
        let templates = try ExportTemplateLoader.builtIns()
        let manuscript = templates[0]
        XCTAssertEqual(manuscript.supportedPageSizes, [.a4, .usLetter])
        XCTAssertEqual(manuscript.pageLayout?.marginTop, 1)
        XCTAssertEqual(manuscript.styles["body"]?.lineSpacing, 2)
        XCTAssertTrue(manuscript.frontMatter.contains { $0.tag == "manuscript.wordCount.roundedHundred" })
        XCTAssertFalse(manuscript.frontMatter.contains { $0.tag.hasPrefix("book.cover") })
        XCTAssertFalse(manuscript.metadataRequirements.requiredTags.contains { $0.contains("isbn") })
        XCTAssertEqual(manuscript.narrativeRules["chapter"]?.breakBefore, .page)
        XCTAssertEqual(manuscript.narrativeRules["scene"]?.sceneBreakMarker, "#")
        XCTAssertTrue(manuscript.headerFooter.header.contains(where: { $0.tag == "page.number" }))

        let ebook = templates[1]
        XCTAssertEqual(ebook.metadataRequirements.requiredTags, ["book.title", "book.author", "book.language"])
        XCTAssertTrue(ebook.metadataRequirements.recommendedTags.contains("book.isbn.ebook"))
        XCTAssertTrue(ebook.metadataRequirements.recommendedTags.contains("book.cover.front"))
        XCTAssertTrue(ebook.supportedPageSizes.isEmpty)
        XCTAssertTrue(ebook.headerFooter.header.isEmpty && ebook.headerFooter.footer.isEmpty)
        XCTAssertEqual(ebook.narrativeRules["chapter"]?.appearsInNavigation, true)
        XCTAssertEqual(ebook.narrativeRules["scene"]?.appearsInNavigation, false)
        XCTAssertEqual(ebook.narrativeRules["scene"]?.sceneBreakMarker, "* * *")
        XCTAssertEqual(
            ebook.frontMatter.map(\.id),
            [
                "cover.front",
                "title.book",
                "title.subtitle",
                "title.author",
                "title.series",
                "title.seriesVolume",
                "copyright.statement",
                "copyright.notice",
                "copyright.publisher",
                "copyright.date",
                "copyright.edition",
                "copyright.isbns",
                "copyright.fictionDisclaimer",
                "copyright.rights"
            ]
        )

        let proof = templates[2]
        XCTAssertEqual(proof.metadataRequirements.requiredTags, ["book.title"])
        XCTAssertEqual(proof.supportedPageSizes, [.usLetter, .a4])
        XCTAssertNotNil(proof.pageLayout)
        XCTAssertEqual(proof.narrativeRules["chapter"]?.breakBefore, .page)
        XCTAssertEqual(proof.narrativeRules["scene"]?.sceneBreakMarker, "* * *")
        XCTAssertTrue(proof.headerFooter.footer.contains(where: { $0.tag == "page.number" }))
        XCTAssertFalse(proof.metadataRequirements.requiredTags.contains { $0.contains("isbn") })
        XCTAssertEqual(
            proof.frontMatter.map(\.id),
            [
                "cover.front",
                "title.book",
                "title.subtitle",
                "title.author",
                "copyright.statement",
                "copyright.notice",
                "copyright.isbns",
                "copyright.fictionDisclaimer",
                "copyright.rights"
            ]
        )
    }

    private func replacing(_ template: ExportTemplate, frontMatter: [ExportTemplateComponent]) -> ExportTemplate {
        ExportTemplate(
            id: template.id, version: template.version, displayName: template.displayName,
            description: template.description, purpose: template.purpose, supportedFormats: template.supportedFormats,
            supportedPageSizes: template.supportedPageSizes, pageLayout: template.pageLayout, metadataRequirements: template.metadataRequirements,
            frontMatter: frontMatter, backMatter: template.backMatter, headerFooter: template.headerFooter,
            styles: template.styles, narrativeRules: template.narrativeRules
        )
    }

    private func publication(
        subtitle: String?,
        language: String?,
        isbn: String?,
        cover: Bool,
        contactInformation: ExportContactInformation = .init()
    ) -> ExportPublication {
        let bookID = UUID()
        let chapter = ExportDocument(
            id: UUID(), title: "One", narrativeType: .chapter, depth: 1, wordCount: 1_500,
            metadata: ExportDocumentMetadata(subtitle: nil, epigraph: nil, povCharacter: nil, location: nil, storyDate: nil, book: nil),
            prose: [ExportProseBlock(spans: [ExportTextSpan(text: "words")])]
        )
        let scene = ExportDocument(
            id: UUID(), title: "Scene", narrativeType: .scene, depth: 2, wordCount: 1,
            metadata: ExportDocumentMetadata(subtitle: nil, epigraph: nil, povCharacter: nil, location: nil, storyDate: nil, book: nil),
            prose: []
        )
        let asset = cover ? [ExportCoverAsset(id: UUID(), kind: .front, sourcePath: "cover.jpg", mediaType: "image/jpeg", byteCount: 3, sha256: "abc", data: Data([1, 2, 3]))] : []
        let metadata = ExportBookMetadata(
            subtitle: subtitle, author: "Author", isbns: isbn.map { [ExportISBN(format: .ebook, number: $0)] } ?? [],
            seriesName: "Series", volumeNumber: 2, volumeCount: 3, publisher: nil, publicationDate: nil,
            copyright: nil, language: language, edition: nil, covers: asset
        )
        return ExportPublication(
            scope: .book, rootDocumentID: bookID,
            project: ExportProjectMetadata(
                title: "Project",
                creator: nil,
                author: "Project Author",
                createdAt: .distantPast,
                modifiedAt: .distantPast,
                contactInformation: contactInformation
            ),
            book: ExportBook(id: bookID, title: "Book", metadata: metadata),
            documents: [chapter, scene], diagnostics: []
        )
    }
}
