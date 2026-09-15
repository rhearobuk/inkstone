import XCTest
@testable import AuthorData

final class EbookRendererTests: XCTestCase {
    func testRendersValidatedEPUBWithMetadataCoverAndSemanticContent() throws {
        let document = try EbookRenderer.render(publication(), modifiedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(document.suggestedFilename, "The -Novel - Chapter 1 - Ebook.epub")
        try EbookRenderer.validate(document.data)

        let entries = try EPUBStoredZIP.decode(document.data)
        XCTAssertEqual(entries.first?.name, "mimetype")
        XCTAssertEqual(entries.first?.compression, 0)
        let files = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.data) })
        let opf = String(decoding: files["EPUB/package.opf"]!, as: UTF8.self)
        let chapter = String(decoding: files["EPUB/text/chapter-1.xhtml"]!, as: UTF8.self)
        let nav = String(decoding: files["EPUB/nav.xhtml"]!, as: UTF8.self)
        XCTAssertTrue(opf.contains("urn:isbn:978-0-123"))
        XCTAssertTrue(opf.contains("<dc:publisher>Publisher</dc:publisher>"))
        XCTAssertTrue(opf.contains("properties=\"cover-image\""))
        XCTAssertTrue(files.keys.contains("EPUB/images/cover.jpg"))
        XCTAssertTrue(chapter.contains("<strong>bold</strong>"))
        XCTAssertTrue(chapter.contains("<em> italic</em>"))
        XCTAssertTrue(chapter.contains("“Smart quotes — Unicode”"))
        XCTAssertTrue(chapter.contains("aria-label=\"Scene break\""))
        XCTAssertTrue(nav.contains(">Chapter One</a>"))
        XCTAssertFalse(nav.contains(">Scene One</a>"))
        XCTAssertFalse(chapter.contains("A4"))
        XCTAssertFalse(chapter.contains("page-number"))
    }

    func testUsesStableNonISBNIdentifierAndSupportsMissingCover() throws {
        let first = try EbookRenderer.render(publication(isbn: nil, cover: false), modifiedAt: .distantPast)
        let second = try EbookRenderer.render(publication(isbn: nil, cover: false), modifiedAt: .distantPast)
        let firstOPF = String(decoding: Dictionary(uniqueKeysWithValues: try EPUBStoredZIP.decode(first.data).map { ($0.name, $0.data) })["EPUB/package.opf"]!, as: UTF8.self)
        let secondOPF = String(decoding: Dictionary(uniqueKeysWithValues: try EPUBStoredZIP.decode(second.data).map { ($0.name, $0.data) })["EPUB/package.opf"]!, as: UTF8.self)
        XCTAssertTrue(firstOPF.contains("urn:uuid:"))
        XCTAssertEqual(firstOPF, secondOPF)
        XCTAssertFalse(firstOPF.contains("cover-image"))
    }

    private func publication(isbn: String? = "978-0-123", cover: Bool = true) -> ResolvedPublication {
        let styles = ["body": ExportSemanticStyle(fontFamily: nil, fontSize: nil, weight: nil, alignment: nil, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil)]
        let chapterRule = ExportNarrativeRule(displaysTitle: true, displaysSubtitle: false, headingStyle: "chapterHeading", breakBefore: .section, appearsInNavigation: true, numbering: .arabic, insertsSceneBreakBefore: false, sceneBreakMarker: nil)
        let sceneRule = ExportNarrativeRule(displaysTitle: false, displaysSubtitle: false, headingStyle: nil, breakBefore: .none, appearsInNavigation: false, numbering: .none, insertsSceneBreakBefore: true, sceneBreakMarker: "* * *")
        let coverValue: [ResolvedTemplateComponent] = cover ? [ResolvedTemplateComponent(id: "cover.front", style: "cover", value: .asset(ExportCoverAsset(id: UUID(), kind: .front, sourcePath: "cover.jpg", mediaType: "image/jpeg", byteCount: 3, sha256: "test", data: Data([1, 2, 3]))), formatter: nil)] : []
        var metadata: [String: TemplateValue] = [
            "book.language": .text("en"),
            "book.publisher": .text("Publisher"),
            "book.publicationDate": .date(Date(timeIntervalSince1970: 0)),
            "book.copyright": .text("Copyright 2026 Author"),
            "book.series.name": .text("Series"),
            "book.series.volume": .integer(2),
            "book.edition": .text("First edition")
        ]
        if let isbn { metadata["publication.isbn"] = .text(isbn) }
        return ResolvedPublication(
            templateID: "ebook", templateVersion: 1, outputFormat: .epub, pageSize: nil, readiness: .ready(warnings: []), styles: styles,
            frontMatter: coverValue + [
                ResolvedTemplateComponent(id: "title.book", style: "bookTitle", value: .text("The /Novel"), formatter: nil),
                ResolvedTemplateComponent(id: "title.subtitle", style: "bookSubtitle", value: .text("A Subtitle"), formatter: nil),
                ResolvedTemplateComponent(id: "title.author", style: "author", value: .text("A. Writer"), formatter: nil),
                ResolvedTemplateComponent(id: "copyright.isbn", style: "frontMatterBody", value: .text(isbn ?? ""), formatter: nil)
            ],
            backMatter: [], header: [], footer: [],
            narrative: [
                ResolvedNarrativeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, narrativeType: .chapter, title: "Chapter One", subtitle: nil, wordCount: 3, rule: chapterRule, number: 1, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "“Smart quotes — Unicode” "), ExportTextSpan(text: "bold", isBold: true), ExportTextSpan(text: " italic", isItalic: true)])]),
                ResolvedNarrativeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, narrativeType: .scene, title: "Scene One", subtitle: nil, wordCount: 1, rule: sceneRule, number: 1, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "One.")])]),
                ResolvedNarrativeItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, narrativeType: .scene, title: "Scene Two", subtitle: nil, wordCount: 1, rule: sceneRule, number: 2, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "Two.")])])
            ],
            metadata: metadata, diagnostics: []
        )
    }
}
