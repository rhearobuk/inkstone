import CoreGraphics
import CoreText
import Foundation
import ImageIO
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct PDFExportOptions: Sendable, Hashable {
    public let subject: String
    public let creationDate: Date

    public init(subject: String = "Inkstone publication export", creationDate: Date = Date()) {
        self.subject = subject
        self.creationDate = creationDate
    }
}

public struct PDFRenderResult: Sendable {
    public let data: Data
    public let pageCount: Int
    public let suggestedFilename: String
    public let diagnostics: [String]
}

public enum PDFRendererError: LocalizedError, Equatable {
    case unsupportedPublication
    case exportNotReady
    case invalidPageLayout
    case contextCreationFailed
    case invalidPDF
    case destinationExists(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPublication: "The selected template cannot produce a PDF."
        case .exportNotReady: "The publication is not ready to export."
        case .invalidPageLayout: "The template page layout leaves no room for content."
        case .contextCreationFailed: "Inkstone could not create the PDF drawing context."
        case .invalidPDF: "Inkstone generated invalid PDF data."
        case .destinationExists(let url): "A file already exists at \(url.path)."
        }
    }
}

/// A native PDF renderer. Core Text lays out the resolved semantic text into page frames;
/// Core Graphics writes those frames and the resolved running furniture to the PDF.
public enum PDFRenderer {
    public static func render(
        publication: ResolvedPublication,
        options: PDFExportOptions = .init()
    ) throws -> PDFRenderResult {
        guard publication.outputFormat == .pdf else { throw PDFRendererError.unsupportedPublication }
        guard case .ready = publication.readiness else { throw PDFRendererError.exportNotReady }

        let layout = try PDFPageLayout(publication: publication)
        var diagnostics = publication.diagnostics + layout.diagnostics
        let pages = try PDFPaginator(publication: publication, layout: layout).paginate()
        guard !pages.isEmpty else { throw PDFRendererError.invalidPDF }

        let data = NSMutableData()
        var mediaBox = layout.mediaBox
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                [
                    kCGPDFContextTitle as String: layout.title,
                    kCGPDFContextAuthor as String: layout.author,
                    kCGPDFContextSubject as String: options.subject,
                    kCGPDFContextCreator as String: "Inkstone",
                    "CreationDate": options.creationDate
                ] as CFDictionary
              ) else {
            throw PDFRendererError.contextCreationFailed
        }

        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil as CFDictionary?)
            draw(page: page, pageNumber: index + 1, totalPages: pages.count, publication: publication, layout: layout, in: context)
            context.endPDFPage()
        }
        context.closePDF()

        let result = Data(referencing: data)
        guard let provider = CGDataProvider(data: result as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages == pages.count else {
            throw PDFRendererError.invalidPDF
        }
        diagnostics.append("Validated \(pages.count)-page PDF with Core Graphics.")
        return PDFRenderResult(
            data: result,
            pageCount: pages.count,
            suggestedFilename: suggestedFilename(for: publication, title: layout.title),
            diagnostics: diagnostics
        )
    }

    public static func write(
        publication: ResolvedPublication,
        to url: URL,
        options: PDFExportOptions = .init()
    ) throws -> PDFRenderResult {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw PDFRendererError.destinationExists(url)
        }
        let result = try render(publication: publication, options: options)
        try result.data.write(to: url, options: .withoutOverwriting)
        return result
    }

    public static func suggestedFilename(for publication: ResolvedPublication, title: String? = nil) -> String {
        let rawTitle = title ?? publication.frontMatter.compactMap { component -> String? in
            if component.id == "title.book", case .text(let value) = component.value { return value }
            return nil
        }.first ?? "Untitled"
        let scope = publication.narrative.first?.title
        let scopeSuffix = publication.narrative.count == 1 && publication.narrative.first?.narrativeType != .book
            ? " - \(sanitizeFilename(scope ?? "Selection"))" : ""
        let format = publication.templateID.contains("manuscript") ? "Manuscript" : "Reading Proof"
        return "\(sanitizeFilename(rawTitle))\(scopeSuffix) - \(format).pdf"
    }

    private static func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private static func draw(
        page: PDFPage,
        pageNumber: Int,
        totalPages: Int,
        publication: ResolvedPublication,
        layout: PDFPageLayout,
        in context: CGContext
    ) {
        if let cover = page.cover, let data = cover.data,
           let image = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) {
            let scale = min(layout.size.width / CGFloat(image.width), layout.size.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let rect = CGRect(
                x: (layout.size.width - size.width) / 2,
                y: (layout.size.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            context.draw(image, in: rect)
        }
        for segment in page.segments {
            let path = CGPath(rect: segment.rect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(segment.text),
                segment.range,
                path,
                nil
            )
            CTFrameDraw(frame, context)
        }
        if !page.isTitlePage {
            drawFurniture(publication.header, at: layout.headerRect, pageNumber: pageNumber, totalPages: totalPages, layout: layout, in: context)
            drawFurniture(publication.footer, at: layout.footerRect, pageNumber: pageNumber, totalPages: totalPages, layout: layout, in: context)
        }
    }

    private static func drawFurniture(
        _ components: [ResolvedTemplateComponent],
        at rect: CGRect,
        pageNumber: Int,
        totalPages: Int,
        layout: PDFPageLayout,
        in context: CGContext
    ) {
        guard !components.isEmpty else { return }
        let pieces = components.map { component in
            componentText(component, pageNumber: pageNumber, totalPages: totalPages)
        }
        let style = layout.style(named: components[0].style)
        let text = NSAttributedString(string: pieces.joined(separator: "  "), attributes: layout.attributes(for: style))
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    private static func componentText(_ component: ResolvedTemplateComponent, pageNumber: Int, totalPages: Int) -> String {
        switch component.value {
        case .text(let value): return transformed(value, style: component.style)
        case .integer(let value):
            return component.formatter == .approximateWordCount || component.formatter == .roundedHundredWordCount
                ? "\(value.formatted()) words" : value.formatted()
        case .date(let value):
            let formatter = DateFormatter()
            formatter.dateStyle = component.formatter == .longDate ? .long : .short
            formatter.timeStyle = .none
            return formatter.string(from: value)
        case .asset: return ""
        case .lateBound(let tag): return tag == "page.total" ? totalPages.formatted() : pageNumber.formatted()
        }
    }

    private static func transformed(_ text: String, style: String) -> String {
        text
    }
}

private struct PDFPageLayout {
    let size: CGSize
    let mediaBox: CGRect
    let contentRect: CGRect
    let headerRect: CGRect
    let footerRect: CGRect
    let title: String
    let author: String
    let styles: [String: ExportSemanticStyle]
    var diagnostics: [String] = []

    init(publication: ResolvedPublication) throws {
        let pageSize: CGSize = publication.pageSize == .a4
            ? CGSize(width: 595.28, height: 841.89)
            : CGSize(width: 612, height: 792)
        let margins = publication.pageLayout ?? ExportPageLayout(
            marginTop: 0.8,
            marginBottom: 0.8,
            marginLeading: 0.85,
            marginTrailing: 0.85
        )
        let top = margins.marginTop * 72
        let bottom = margins.marginBottom * 72
        let leading = margins.marginLeading * 72
        let trailing = margins.marginTrailing * 72
        let content = CGRect(x: leading, y: top + 22, width: pageSize.width - leading - trailing, height: pageSize.height - top - bottom - 44)
        guard content.width > 0, content.height > 0 else { throw PDFRendererError.invalidPageLayout }
        self.size = pageSize
        self.mediaBox = CGRect(origin: .zero, size: pageSize)
        self.contentRect = content
        self.headerRect = CGRect(x: leading, y: max(6, top - 18), width: content.width, height: 14)
        self.footerRect = CGRect(x: leading, y: pageSize.height - bottom + 4, width: content.width, height: 14)
        self.title = publication.frontMatter.compactMap {
            if $0.id == "title.book", case .text(let text) = $0.value { return text }; return nil
        }.first ?? "Untitled"
        self.author = publication.frontMatter.compactMap {
            if $0.id == "title.author", case .text(let text) = $0.value { return text }; return nil
        }.first ?? ""
        self.styles = publication.styles
        for family in Set(publication.styles.values.compactMap(\.fontFamily)) {
            let font = CTFontCreateWithName(family as CFString, 12, nil)
            if CTFontCopyFamilyName(font) as String != family {
                diagnostics.append("Font '\(family)' was unavailable; a system serif fallback was used.")
            }
        }
    }

    func style(named name: String) -> ExportSemanticStyle {
        styles[name] ?? ExportSemanticStyle(fontFamily: nil, fontSize: 12, weight: nil, alignment: .leading, firstLineIndent: nil, lineSpacing: nil, spacingBefore: nil, spacingAfter: nil, textTransform: nil)
    }

    func attributes(for style: ExportSemanticStyle, bold: Bool = false, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        let size = CGFloat(style.fontSize ?? 12)
        let preferred = style.fontFamily ?? "Times New Roman"
        var traits: CTFontSymbolicTraits = []
        if bold || style.weight == "semibold" { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = CTFontCreateWithName(preferred as CFString, size, nil)
        let font = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits)
            ?? CTFontCreateWithName("Times-Roman" as CFString, size, nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment(style.alignment)
        paragraph.firstLineHeadIndent = CGFloat(style.firstLineIndent ?? 0) * 72
        paragraph.lineSpacing = max(0, CGFloat((style.lineSpacing ?? 1) - 1) * size)
        paragraph.paragraphSpacingBefore = CGFloat(style.spacingBefore ?? 0) * size
        paragraph.paragraphSpacing = CGFloat(style.spacingAfter ?? 0) * size
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: CGColor(gray: 0, alpha: 1)]
    }

    private func alignment(_ value: ExportAlignment?) -> NSTextAlignment {
        switch value {
        case .center: .center
        case .trailing: .right
        case .justified: .justified
        default: .left
        }
    }
}

private struct PDFPage {
    let isTitlePage: Bool
    let cover: ExportCoverAsset?
    var segments: [PDFSegment]
}

private struct PDFSegment {
    let text: NSAttributedString
    let range: CFRange
    let rect: CGRect
}

private enum PDFBlock {
    case cover(ExportCoverAsset)
    case frontMatterPage(title: [NSAttributedString], contact: [NSAttributedString], wordCount: NSAttributedString?)
    case pageBreak
    case text(NSAttributedString, heading: Bool)
}

private struct PDFPaginator {
    let publication: ResolvedPublication
    let layout: PDFPageLayout

    func paginate() throws -> [PDFPage] {
        var pages: [PDFPage] = []
        var current = PDFPage(isTitlePage: false, cover: nil, segments: [])
        var y = layout.contentRect.minY
        func finishCurrent() {
            if !current.segments.isEmpty { pages.append(current) }
            current = PDFPage(isTitlePage: false, cover: nil, segments: [])
            y = layout.contentRect.minY
        }

        for block in blocks() {
            switch block {
            case .cover(let cover):
                finishCurrent()
                pages.append(PDFPage(isTitlePage: true, cover: cover, segments: []))
            case .frontMatterPage(let title, let contact, let wordCount):
                finishCurrent()
                pages.append(frontMatterPage(title: title, contact: contact, wordCount: wordCount))
            case .pageBreak:
                finishCurrent()
            case .text(let text, let isHeading):
                var location = 0
                let length = text.length
                while location < length {
                    let available = layout.contentRect.maxY - y
                    if available < 18 { finishCurrent(); continue }
                    let rect = CGRect(x: layout.contentRect.minX, y: y, width: layout.contentRect.width, height: available)
                    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: location, length: 0), CGPath(rect: rect, transform: nil), nil)
                    let visible = CTFrameGetVisibleStringRange(frame)
                    if visible.length == 0 { finishCurrent(); continue }
                    if isHeading && location == 0 && visible.length < length && !current.segments.isEmpty {
                        finishCurrent()
                        continue
                    }
                    let used = CGFloat(CTFramesetterSuggestFrameSizeWithConstraints(
                        CTFramesetterCreateWithAttributedString(text),
                        CFRange(location: location, length: visible.length),
                        nil,
                        CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                        nil
                    ).height)
                    current.segments.append(PDFSegment(text: text, range: CFRange(location: location, length: visible.length), rect: CGRect(x: rect.minX, y: y, width: rect.width, height: min(available, max(used, 1)))))
                    y += min(available, max(used, 1))
                    location += visible.length
                    if location < length { finishCurrent() }
                }
            }
        }
        finishCurrent()
        return pages
    }

    private func blocks() -> [PDFBlock] {
        var result: [PDFBlock] = []
        let cover = publication.frontMatter.first { component in
            guard component.id == "cover.front" else { return false }
            if case .asset = component.value { return true }
            return false
        }
        if let cover, case .asset(let asset) = cover.value, asset.data != nil {
            result.append(.cover(asset))
        }
        let titleComponents = publication.frontMatter.filter { $0.id.hasPrefix("title.") }
        let contactComponents = publication.frontMatter.filter { $0.id.hasPrefix("contact.") }
        let wordCount = titleComponents.first { $0.id == "title.wordCount" }
        let titleLines = titleComponents
            .filter { $0.id != "title.wordCount" }
            .map { componentText($0, style: layout.style(named: $0.style)) }
        if !titleLines.isEmpty || !contactComponents.isEmpty || wordCount != nil {
            result.append(.frontMatterPage(
                title: titleLines,
                contact: contactComponents.map { componentText($0, style: layout.style(named: $0.style)) },
                wordCount: wordCount.map { componentText($0, style: layout.style(named: $0.style)) }
            ))
        }
        let copyrightComponents = publication.frontMatter.filter { $0.id.hasPrefix("copyright.") }
        if !copyrightComponents.isEmpty {
            result.append(.frontMatterPage(
                title: copyrightComponents.map { componentText($0, style: layout.style(named: $0.style)) },
                contact: [],
                wordCount: nil
            ))
        }
        for item in publication.narrative {
            if item.rule.breakBefore == .page { result.append(.pageBreak) }
            if item.rule.insertsSceneBreakBefore {
                result.append(.text(string(item.rule.sceneBreakMarker ?? "* * *", style: layout.style(named: "sceneBreak"), trailing: 18), heading: false))
            }
            if item.rule.displaysTitle {
                let style = layout.style(named: item.rule.headingStyle ?? "chapterHeading")
                result.append(.text(string(item.title, style: style, trailing: 18), heading: true))
                if item.rule.displaysSubtitle, let subtitle = item.subtitle, !subtitle.isEmpty {
                    result.append(.text(string(subtitle, style: style, trailing: 18), heading: true))
                }
            }
            for prose in item.prose where !prose.plainText.isEmpty {
                result.append(.text(proseText(prose, style: layout.style(named: "body")), heading: false))
            }
        }
        return result
    }

    private func frontMatterPage(
        title: [NSAttributedString],
        contact: [NSAttributedString],
        wordCount: NSAttributedString?
    ) -> PDFPage {
        var segments: [PDFSegment] = []
        var titleY = layout.size.height * 0.69
        for line in title {
            let height = max(20, CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(line), CFRange(), nil, CGSize(width: layout.contentRect.width, height: .greatestFiniteMagnitude), nil).height)
            titleY -= height
            segments.append(PDFSegment(text: line, range: CFRange(), rect: CGRect(x: layout.contentRect.minX, y: titleY, width: layout.contentRect.width, height: height)))
            titleY -= 18
        }
        var contactY = layout.size.height * 0.91
        for line in contact {
            let height = max(16, CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(line), CFRange(), nil, CGSize(width: layout.contentRect.width * 0.45, height: .greatestFiniteMagnitude), nil).height)
            contactY -= height
            segments.append(PDFSegment(text: line, range: CFRange(), rect: CGRect(x: layout.contentRect.minX, y: contactY, width: layout.contentRect.width * 0.45, height: height)))
            contactY -= 2
        }
        if let wordCount {
            let width = layout.contentRect.width * 0.3
            let height = max(16, CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(wordCount), CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil).height)
            let y = layout.size.height * 0.91 - height
            segments.append(PDFSegment(text: wordCount, range: CFRange(), rect: CGRect(x: layout.contentRect.maxX - width, y: y, width: width, height: height)))
        }
        return PDFPage(isTitlePage: true, cover: nil, segments: segments)
    }

    private func componentText(_ component: ResolvedTemplateComponent, style: ExportSemanticStyle) -> NSAttributedString {
        let text: String
        switch component.value {
        case .text(let value): text = style.textTransform == .uppercase ? value.uppercased() : value
        case .integer(let value): text = component.formatter == .approximateWordCount || component.formatter == .roundedHundredWordCount ? "\(value.formatted()) words" : value.formatted()
        case .date(let value): text = value.formatted(date: .long, time: .omitted)
        case .asset, .lateBound: text = ""
        }
        return string(text, style: style, trailing: 0)
    }

    private func string(_ value: String, style: ExportSemanticStyle, trailing: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: value + "\n", attributes: layout.attributes(for: style))
        if trailing > 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = trailing
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private func proseText(_ prose: ExportProseBlock, style: ExportSemanticStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in prose.spans {
            result.append(NSAttributedString(string: span.text, attributes: layout.attributes(for: style, bold: span.isBold, italic: span.isItalic)))
        }
        result.append(NSAttributedString(string: "\n", attributes: layout.attributes(for: style)))
        return result
    }
}
