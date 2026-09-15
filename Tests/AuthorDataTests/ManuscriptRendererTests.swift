import XCTest
@testable import AuthorData

final class ManuscriptRendererTests: XCTestCase {
    func testRendersInspectableLetterManuscriptPackage() throws {
        let document = try ManuscriptRenderer.render(publication())
        XCTAssertEqual(document.suggestedFilename, "The -Novel - Manuscript.docx")
        try ManuscriptRenderer.validate(document.data)

        let parts = try StoredZIP.decode(document.data)
        XCTAssertNotNil(parts["[Content_Types].xml"])
        XCTAssertNotNil(parts["word/_rels/document.xml.rels"])
        let body = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        let styles = String(decoding: parts["word/styles.xml"]!, as: UTF8.self)
        let header = String(decoding: parts["word/header1.xml"]!, as: UTF8.self)
        XCTAssertTrue(body.contains("w:w=\"12240\" w:h=\"15840\""))
        XCTAssertTrue(body.contains("Approx. 12,000 words"))
        XCTAssertTrue(body.contains("<w:b/>"))
        XCTAssertTrue(body.contains("<w:i/>"))
        XCTAssertTrue(body.contains("“Smart quotes — Unicode”"))
        XCTAssertEqual(body.components(separatedBy: ">#</w:t>").count - 1, 1)
        XCTAssertTrue(styles.contains("w:firstLine=\"720\""))
        XCTAssertTrue(styles.contains("w:line=\"480\""))
        XCTAssertTrue(header.contains("w:instr=\" PAGE \\* MERGEFORMAT \""))
    }

    func testRendersA4AndOptionalComponentsCleanly() throws {
        var resolved = publication(pageSize: .a4)
        resolved = ResolvedPublication(
            templateID: resolved.templateID, templateVersion: resolved.templateVersion, outputFormat: resolved.outputFormat,
            pageSize: resolved.pageSize, pageLayout: resolved.pageLayout, readiness: resolved.readiness, styles: resolved.styles,
            frontMatter: resolved.frontMatter.filter { $0.id != "title.subtitle" }, backMatter: [],
            header: resolved.header, footer: resolved.footer, narrative: resolved.narrative, diagnostics: []
        )
        let parts = try StoredZIP.decode(ManuscriptRenderer.render(resolved).data)
        let body = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(body.contains("w:w=\"11906\" w:h=\"16838\""))
        XCTAssertFalse(body.contains("A subtitle"))
    }

    func testRejectsUnreadyAndMissingPaperSizePublications() {
        var missingPaperSize = publication(pageSize: .usLetter)
        missingPaperSize = ResolvedPublication(
            templateID: missingPaperSize.templateID, templateVersion: missingPaperSize.templateVersion,
            outputFormat: .docx, pageSize: nil, pageLayout: missingPaperSize.pageLayout, readiness: missingPaperSize.readiness, styles: missingPaperSize.styles,
            frontMatter: missingPaperSize.frontMatter, backMatter: [], header: [], footer: [],
            narrative: [], diagnostics: []
        )
        XCTAssertThrowsError(try ManuscriptRenderer.render(missingPaperSize))
    }

    private func publication(pageSize: ExportPageSize = .usLetter) -> ResolvedPublication {
        let styles: [String: ExportSemanticStyle] = [
            "body": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .leading, firstLineIndent: 0.5, lineSpacing: 2, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "bookTitle": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: .uppercase),
            "bookSubtitle": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "author": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "titlePageMetadata": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .leading, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "chapterHeading": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "sectionHeading": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "sceneBreak": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "header": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .trailing, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil),
            "footer": ExportSemanticStyle(fontFamily: "Times New Roman", fontSize: 12, weight: nil, alignment: .center, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil)
        ]
        let chapterRule = ExportNarrativeRule(displaysTitle: true, displaysSubtitle: true, headingStyle: "chapterHeading", breakBefore: .page, appearsInNavigation: false, numbering: .arabic, insertsSceneBreakBefore: false, sceneBreakMarker: nil)
        let sceneRule = ExportNarrativeRule(displaysTitle: false, displaysSubtitle: false, headingStyle: nil, breakBefore: .none, appearsInNavigation: false, numbering: .none, insertsSceneBreakBefore: true, sceneBreakMarker: "#")
        return ResolvedPublication(
            templateID: "manuscript", templateVersion: 1, outputFormat: .docx, pageSize: pageSize,
            pageLayout: ExportPageLayout(marginTop: 1, marginBottom: 1, marginLeading: 1, marginTrailing: 1),
            readiness: .ready(warnings: []), styles: styles,
            frontMatter: [
                ResolvedTemplateComponent(id: "title.book", style: "bookTitle", value: .text("The /Novel"), formatter: nil),
                ResolvedTemplateComponent(id: "title.subtitle", style: "bookSubtitle", value: .text("A subtitle"), formatter: nil),
                ResolvedTemplateComponent(id: "title.author", style: "author", value: .text("A. Writer"), formatter: nil),
                ResolvedTemplateComponent(id: "title.wordCount", style: "titlePageMetadata", value: .integer(12_000), formatter: .approximateWordCount)
            ],
            backMatter: [], header: [
                ResolvedTemplateComponent(id: "header.page", style: "header", value: .lateBound("page.number"), formatter: nil)
            ], footer: [],
            narrative: [
                ResolvedNarrativeItem(id: UUID(), narrativeType: .chapter, title: "Beginning", subtitle: nil, wordCount: 4, rule: chapterRule, number: 1, prose: [
                    ExportProseBlock(spans: [ExportTextSpan(text: "“Smart quotes — Unicode” "), ExportTextSpan(text: "bold", isBold: true), ExportTextSpan(text: " italic", isItalic: true)])
                ]),
                ResolvedNarrativeItem(id: UUID(), narrativeType: .scene, title: "First", subtitle: nil, wordCount: 1, rule: sceneRule, number: 1, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "One.")])]),
                ResolvedNarrativeItem(id: UUID(), narrativeType: .scene, title: "Second", subtitle: nil, wordCount: 1, rule: sceneRule, number: 2, prose: [ExportProseBlock(spans: [ExportTextSpan(text: "Two.")])])
            ], diagnostics: []
        )
    }
}
