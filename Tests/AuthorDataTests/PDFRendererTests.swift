import CoreGraphics
import PDFKit
import XCTest
@testable import AuthorData

final class PDFRendererTests: XCTestCase {
    func testRendersInspectableManuscriptLetterPDF() throws {
        let result = try PDFRenderer.render(publication: publication(templateID: "manuscript", pageSize: .usLetter))
        let document = try XCTUnwrap(PDFDocument(data: result.data))

        XCTAssertGreaterThan(result.pageCount, 1)
        XCTAssertEqual(document.pageCount, result.pageCount)
        let attributes = try XCTUnwrap(document.documentAttributes)
        XCTAssertEqual(attributes[AnyHashable("Title")] as? String, "The /Novel")
        XCTAssertEqual(attributes[AnyHashable("Creator")] as? String, "Scribe")
        XCTAssertTrue(document.string?.contains("“Smart quotes — Unicode”") == true)
        XCTAssertTrue(document.string?.contains("bold italic") == true)
        XCTAssertTrue(document.string?.contains("#") == true)
        XCTAssertEqual(result.suggestedFilename, "The -Novel - Manuscript.pdf")
    }

    func testRendersDistinctReadingProofA4WithLateBoundFooter() throws {
        let result = try PDFRenderer.render(publication: publication(templateID: "proof", pageSize: .a4))
        let document = try XCTUnwrap(PDFDocument(data: result.data))

        XCTAssertGreaterThan(result.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.string?.contains("1"), false, "Title pages suppress running furniture.")
        XCTAssertTrue(document.string?.contains("* * *") == true)
        XCTAssertEqual(result.suggestedFilename, "The -Novel - Reading Proof.pdf")

        let provider = try XCTUnwrap(CGDataProvider(data: result.data as CFData))
        XCTAssertEqual(CGPDFDocument(provider)?.numberOfPages, result.pageCount)
    }

    func testSeparatesReadingProofTitleAndCopyrightPages() throws {
        let base = publication(templateID: "proof", pageSize: .a4)
        let publication = ResolvedPublication(
            templateID: base.templateID,
            templateVersion: base.templateVersion,
            outputFormat: base.outputFormat,
            pageSize: base.pageSize,
            pageLayout: base.pageLayout,
            readiness: base.readiness,
            styles: base.styles,
            frontMatter: base.frontMatter + [
                ResolvedTemplateComponent(
                    id: "contact.author.address",
                    style: "frontMatterBody",
                    value: .text("10 Author Lane"),
                    formatter: nil
                ),
                ResolvedTemplateComponent(
                    id: "contact.agent.name",
                    style: "frontMatterBody",
                    value: .text("Alex Agent"),
                    formatter: nil
                ),
                ResolvedTemplateComponent(
                    id: "copyright.statement",
                    style: "frontMatterBody",
                    value: .text("Copyright © 2026 A. Writer"),
                    formatter: nil
                ),
                ResolvedTemplateComponent(
                    id: "copyright.rights",
                    style: "frontMatterBody",
                    value: .text("All rights reserved."),
                    formatter: nil
                )
            ],
            backMatter: base.backMatter,
            header: base.header,
            footer: base.footer,
            narrative: base.narrative,
            diagnostics: base.diagnostics
        )

        let result = try PDFRenderer.render(publication: publication)
        let document = try XCTUnwrap(PDFDocument(data: result.data))

        XCTAssertTrue(document.page(at: 0)?.string?.contains("The /Novel") == true)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("10 Author Lane") == true)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Alex Agent") == true)
        XCTAssertFalse(document.page(at: 0)?.string?.contains("Copyright © 2026 A. Writer") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Copyright © 2026 A. Writer") == true)
        XCTAssertFalse(document.page(at: 1)?.string?.contains("The /Novel") == true)
    }

    func testUsesScopeAwareSanitizedFilenameAndRejectsUnreadyPublication() throws {
        var chapter = publication(templateID: "proof", pageSize: .a4)
        chapter = ResolvedPublication(
            templateID: chapter.templateID, templateVersion: chapter.templateVersion, outputFormat: chapter.outputFormat,
            pageSize: chapter.pageSize, pageLayout: chapter.pageLayout, readiness: chapter.readiness, styles: chapter.styles,
            frontMatter: chapter.frontMatter, backMatter: chapter.backMatter, header: chapter.header, footer: chapter.footer,
            narrative: [chapter.narrative[0]], diagnostics: chapter.diagnostics
        )
        XCTAssertEqual(PDFRenderer.suggestedFilename(for: chapter), "The -Novel - Chapter - One - Reading Proof.pdf")

        let unready = ResolvedPublication(
            templateID: chapter.templateID, templateVersion: chapter.templateVersion, outputFormat: .pdf,
            pageSize: chapter.pageSize, pageLayout: chapter.pageLayout, readiness: .blocked(missingRequiredTags: ["book.title"]),
            styles: chapter.styles, frontMatter: [], backMatter: [], header: [], footer: [], narrative: [], diagnostics: []
        )
        XCTAssertThrowsError(try PDFRenderer.render(publication: unready)) {
            XCTAssertEqual($0 as? PDFRendererError, .exportNotReady)
        }
    }

    private func publication(templateID: String, pageSize: ExportPageSize) -> ResolvedPublication {
        let isManuscript = templateID == "manuscript"
        let styles = [
            "body": ExportSemanticStyle(fontFamily: isManuscript ? "Times New Roman" : "Literata", fontSize: isManuscript ? 12 : 11, weight: nil, alignment: isManuscript ? .leading : .justified, firstLineIndent: isManuscript ? 0.5 : 0.25, lineSpacing: isManuscript ? 2 : 1.4, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "bookTitle": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: isManuscript ? 12 : 24, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: isManuscript ? .uppercase : nil),
            "author": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "chapterHeading": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 16, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "sceneBreak": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "header": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 9, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "footer": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 9, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil)
        ]
        let chapterRule = ExportNarrativeRule(displaysTitle: true, displaysSubtitle: false, headingStyle: "chapterHeading", breakBefore: .page, appearsInNavigation: false, numbering: .arabic, insertsSceneBreakBefore: false, sceneBreakMarker: nil)
        let sceneRule = ExportNarrativeRule(displaysTitle: false, displaysSubtitle: false, headingStyle: nil, breakBefore: .none, appearsInNavigation: false, numbering: .none, insertsSceneBreakBefore: true, sceneBreakMarker: isManuscript ? "#" : "* * *")
        let paragraph = ExportProseBlock(spans: [
            ExportTextSpan(text: "“Smart quotes — Unicode” "),
            ExportTextSpan(text: "bold", isBold: true),
            ExportTextSpan(text: " italic", isItalic: true),
            ExportTextSpan(text: " " + String(repeating: "A long paragraph must continue across pages. ", count: 80))
        ])
        return ResolvedPublication(
            templateID: templateID, templateVersion: 1, outputFormat: .pdf, pageSize: pageSize,
            pageLayout: ExportPageLayout(marginTop: isManuscript ? 1 : 0.8, marginBottom: isManuscript ? 1 : 0.8, marginLeading: isManuscript ? 1 : 0.85, marginTrailing: isManuscript ? 1 : 0.85),
            readiness: .ready(warnings: []), styles: styles,
            frontMatter: [
                ResolvedTemplateComponent(id: "title.book", style: "bookTitle", value: .text("The /Novel"), formatter: nil),
                ResolvedTemplateComponent(id: "title.author", style: "author", value: .text("A. Writer"), formatter: nil)
            ],
            backMatter: [],
            header: isManuscript ? [
                ResolvedTemplateComponent(id: "header.title", style: "header", value: .text("The /Novel"), formatter: nil),
                ResolvedTemplateComponent(id: "header.page", style: "header", value: .lateBound("page.number"), formatter: nil)
            ] : [ResolvedTemplateComponent(id: "header.title", style: "header", value: .text("The /Novel"), formatter: nil)],
            footer: isManuscript ? [] : [ResolvedTemplateComponent(id: "footer.page", style: "footer", value: .lateBound("page.number"), formatter: nil)],
            narrative: [
                ResolvedNarrativeItem(id: UUID(), narrativeType: .chapter, title: "Chapter / One", subtitle: nil, wordCount: 500, rule: chapterRule, number: 1, prose: [paragraph]),
                ResolvedNarrativeItem(id: UUID(), narrativeType: .scene, title: "Scene", subtitle: nil, wordCount: 1, rule: sceneRule, number: 1, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "Short scene.")])])
            ],
            diagnostics: []
        )
    }
}
