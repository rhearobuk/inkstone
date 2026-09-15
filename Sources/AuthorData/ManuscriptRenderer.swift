import Foundation

public enum ManuscriptRendererError: LocalizedError, Equatable {
    case invalidPublication(String)
    case unsupportedComponent(String)
    case xmlGeneration(String)
    case packageGeneration(String)
    case invalidPackage(String)
    case fileWrite(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidPublication(let message), .unsupportedComponent(let message),
             .xmlGeneration(let message), .packageGeneration(let message), .invalidPackage(let message):
            return message
        case .fileWrite(let url):
            return "The manuscript could not be written to \(url.lastPathComponent)."
        }
    }
}

public struct ManuscriptDocument: Sendable {
    public let data: Data
    public let suggestedFilename: String
    public let diagnostics: [String]
}

/// Converts an already-resolved manuscript publication into a self-contained OOXML package.
public enum ManuscriptRenderer {
    public static func render(_ publication: ResolvedPublication) throws -> ManuscriptDocument {
        guard publication.outputFormat == .docx else {
            throw ManuscriptRendererError.invalidPublication("Manuscript rendering requires DOCX output.")
        }
        guard case .ready = publication.readiness else {
            throw ManuscriptRendererError.invalidPublication("The publication is not ready to export.")
        }
        guard let pageSize = publication.pageSize else {
            throw ManuscriptRendererError.invalidPublication("The manuscript template did not resolve a paper size.")
        }

        let documentXML = try documentXML(publication, pageSize: pageSize)
        let headerXML = try headerXML(publication.header, styles: publication.styles)
        let footerXML = try footerXML(publication.footer, styles: publication.styles)
        let parts = try packageParts(
            publication: publication,
            documentXML: documentXML,
            headerXML: headerXML,
            footerXML: footerXML
        )
        let data = try StoredZIP.encode(parts)
        try validate(data)
        return ManuscriptDocument(
            data: data,
            suggestedFilename: suggestedFilename(for: publication),
            diagnostics: publication.diagnostics
        )
    }

    public static func write(_ document: ManuscriptDocument, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ManuscriptRendererError.fileWrite(url)
        }
        do {
            try document.data.write(to: url, options: .atomic)
        } catch {
            throw ManuscriptRendererError.fileWrite(url)
        }
    }

    public static func suggestedFilename(for publication: ResolvedPublication) -> String {
        let title = publication.frontMatter.first(where: { $0.id == "title.book" }).flatMap(textValue) ?? "Untitled"
        let scope = publication.narrative.first(where: { $0.narrativeType == publicationScope(publication) })
        let qualifier: String
        if let scope, scope.narrativeType != .book {
            qualifier = " - \(scope.narrativeType.rawValue.capitalized) \(scope.number)"
        } else {
            qualifier = ""
        }
        return "\(safeFilename(title))\(qualifier) - Manuscript.docx"
    }

    /// A lightweight structural validation suitable for automated tests and pre-write validation.
    public static func validate(_ data: Data) throws {
        let parts = try StoredZIP.decode(data)
        let required = ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels"]
        guard required.allSatisfy({ parts[$0] != nil }) else {
            throw ManuscriptRendererError.invalidPackage("The DOCX package is missing a required part.")
        }
        for name in required {
            guard let value = parts[name], XMLParser(data: value).parse() else {
                throw ManuscriptRendererError.invalidPackage("The DOCX package contains malformed XML in \(name).")
            }
        }
        let document = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        let relationships = String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self)
        let styles = String(decoding: parts["word/styles.xml"]!, as: UTF8.self)
        for id in ids(in: document, attribute: "w:val", element: "w:pStyle") {
            guard styles.contains("w:styleId=\"\(id)\"") else {
                throw ManuscriptRendererError.invalidPackage("The document references unknown style \(id).")
            }
        }
        for relation in ["rIdHeader", "rIdFooter"] where document.contains("r:id=\"\(relation)\"") {
            guard relationships.contains("Id=\"\(relation)\"") else {
                throw ManuscriptRendererError.invalidPackage("The document contains an unresolved relationship.")
            }
        }
    }

    private static func documentXML(_ publication: ResolvedPublication, pageSize: ExportPageSize) throws -> String {
        var body: [String] = []
        for component in publication.frontMatter {
            body.append(try componentParagraph(component, styles: publication.styles, pageBreakBefore: false))
        }
        if !publication.frontMatter.isEmpty {
            body.append(paragraph(style: nil, text: "", pageBreakBefore: true))
        }

        var lastWasScene = false
        var previousWasPageHeading = false
        for item in publication.narrative {
            let isHeading = item.rule.displaysTitle && item.rule.headingStyle != nil
            if item.narrativeType == .scene && item.rule.insertsSceneBreakBefore && lastWasScene {
                body.append(paragraph(style: styleID(item.rule.headingStyle ?? "sceneBreak"), text: item.rule.sceneBreakMarker ?? "#"))
            }
            if isHeading {
                let breakBefore = item.rule.breakBefore == .page && !previousWasPageHeading
                body.append(paragraph(
                    style: styleID(item.rule.headingStyle!),
                    text: headingText(item),
                    pageBreakBefore: breakBefore
                ))
                if item.rule.displaysSubtitle, let subtitle = item.subtitle, !subtitle.isEmpty {
                    body.append(paragraph(style: styleID(item.rule.headingStyle!), text: subtitle))
                }
                previousWasPageHeading = breakBefore
            } else {
                previousWasPageHeading = false
            }
            for prose in item.prose {
                body.append(proseParagraph(prose))
                previousWasPageHeading = false
            }
            lastWasScene = item.narrativeType == .scene
        }
        for component in publication.backMatter {
            body.append(try componentParagraph(component, styles: publication.styles, pageBreakBefore: false))
        }
        let page = pageSize == .usLetter ? ("12240", "15840") : ("11906", "16838")
        let layout = publication.pageLayout
        let margins = "w:top=\"\(twips(layout?.marginTop ?? 1))\" w:right=\"\(twips(layout?.marginTrailing ?? 1))\" w:bottom=\"\(twips(layout?.marginBottom ?? 1))\" w:left=\"\(twips(layout?.marginLeading ?? 1))\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>
        \(body.joined())
        <w:sectPr><w:titlePg/><w:headerReference w:type="default" r:id="rIdHeader"/><w:footerReference w:type="default" r:id="rIdFooter"/><w:pgSz w:w="\(page.0)" w:h="\(page.1)"/><w:pgMar \(margins)/></w:sectPr>
        </w:body></w:document>
        """
    }

    private static func headerXML(_ components: [ResolvedTemplateComponent], styles: [String: ExportSemanticStyle]) throws -> String {
        let content = try components.map { try componentParagraph($0, styles: styles, pageBreakBefore: false, lateBoundField: true) }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(content)</w:hdr>"
    }

    private static func footerXML(_ components: [ResolvedTemplateComponent], styles: [String: ExportSemanticStyle]) throws -> String {
        let content = try components.map { try componentParagraph($0, styles: styles, pageBreakBefore: false, lateBoundField: true) }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(content)</w:ftr>"
    }

    private static func componentParagraph(_ component: ResolvedTemplateComponent, styles: [String: ExportSemanticStyle], pageBreakBefore: Bool, lateBoundField: Bool = false) throws -> String {
        guard styles[component.style] != nil else {
            throw ManuscriptRendererError.unsupportedComponent("The resolved component \(component.id) references an unknown style.")
        }
        if lateBoundField, case .lateBound(let field) = component.value {
            guard field == "page.number" || field == "page.total" else {
                throw ManuscriptRendererError.unsupportedComponent("The renderer does not support late-bound value \(field).")
            }
            let instruction = field == "page.number" ? "PAGE" : "NUMPAGES"
            return paragraph(style: styleID(component.style), field: instruction, pageBreakBefore: pageBreakBefore)
        }
        return paragraph(style: styleID(component.style), text: formatted(component))
    }

    private static func proseParagraph(_ block: ExportProseBlock) -> String {
        let runs = block.spans.map { span in
            let properties = (span.isBold ? "<w:b/>" : "") + (span.isItalic ? "<w:i/>" : "")
            return "<w:r><w:rPr>\(properties)</w:rPr><w:t xml:space=\"preserve\">\(xml(span.text))</w:t></w:r>"
        }.joined()
        return "<w:p><w:pPr><w:pStyle w:val=\"ManuscriptBody\"/></w:pPr>\(runs)</w:p>"
    }

    private static func paragraph(style: String?, text: String, pageBreakBefore: Bool = false) -> String {
        let properties = (style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? "") + (pageBreakBefore ? "<w:pageBreakBefore/>" : "")
        let content = xml(text).replacingOccurrences(
            of: "\n",
            with: "</w:t><w:br/><w:t xml:space=\"preserve\">"
        )
        return "<w:p><w:pPr>\(properties)</w:pPr><w:r><w:t xml:space=\"preserve\">\(content)</w:t></w:r></w:p>"
    }

    private static func paragraph(style: String?, field: String, pageBreakBefore: Bool) -> String {
        let properties = (style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? "") + (pageBreakBefore ? "<w:pageBreakBefore/>" : "")
        return "<w:p><w:pPr>\(properties)</w:pPr><w:fldSimple w:instr=\" \(field) \\* MERGEFORMAT \"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p>"
    }

    private static func packageParts(publication: ResolvedPublication, documentXML: String, headerXML: String, footerXML: String) throws -> [String: Data] {
        let title = publication.frontMatter.first(where: { $0.id == "title.book" }).flatMap(textValue) ?? ""
        let author = publication.frontMatter.first(where: { $0.id == "title.author" }).flatMap(textValue) ?? ""
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """
        let rootRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>"
        let relationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/><Relationship Id=\"rIdFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/></Relationships>"
        let core = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(xml(title))</dc:title><dc:creator>\(xml(author))</dc:creator><dc:subject>Manuscript</dc:subject></cp:coreProperties>"
        return [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(rootRelationships.utf8),
            "docProps/core.xml": Data(core.utf8),
            "word/document.xml": Data(documentXML.utf8),
            "word/styles.xml": Data(stylesXML(publication.styles).utf8),
            "word/header1.xml": Data(headerXML.utf8),
            "word/footer1.xml": Data(footerXML.utf8),
            "word/_rels/document.xml.rels": Data(relationships.utf8)
        ]
    }

    private static func stylesXML(_ styles: [String: ExportSemanticStyle]) -> String {
        let predefined = ["body": "ManuscriptBody", "bookTitle": "BookTitle", "bookSubtitle": "BookSubtitle", "author": "Author", "titlePageMetadata": "TitlePageMetadata", "sectionHeading": "SectionHeading", "chapterHeading": "ChapterHeading", "epigraph": "Epigraph", "sceneBreak": "SceneBreak", "header": "Header", "footer": "Footer"]
        let rendered = predefined.compactMap { key, id -> String? in
            guard let style = styles[key] else { return nil }
            let font = xml(style.fontFamily ?? "Times New Roman")
            let size = Int((style.fontSize ?? 12) * 2)
            let alignment: String
            switch style.alignment ?? .leading { case .center: alignment = "center"; case .trailing: alignment = "right"; case .justified: alignment = "both"; default: alignment = "left" }
            let indent = style.firstLineIndent.map { "<w:ind w:firstLine=\"\(Int($0 * 1440))\"/>" } ?? ""
            let spacingAttributes = [
                style.lineSpacing.map { "w:line=\"\(Int($0 * 240))\" w:lineRule=\"auto\"" },
                style.spacingBefore.map { "w:before=\"\(Int($0 * 240))\"" },
                style.spacingAfter.map { "w:after=\"\(Int($0 * 240))\"" }
            ].compactMap { $0 }.joined(separator: " ")
            let spacing = spacingAttributes.isEmpty ? "" : "<w:spacing \(spacingAttributes)/>"
            let caps = style.textTransform == .uppercase ? "<w:caps/>" : ""
            return "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(key)\"/><w:pPr><w:jc w:val=\"\(alignment)\"/>\(indent)\(spacing)</w:pPr><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\"/><w:sz w:val=\"\(size)\"/>\(caps)</w:rPr></w:style>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(rendered)</w:styles>"
    }

    private static func formatted(_ component: ResolvedTemplateComponent) -> String {
        switch component.value {
        case .text(let text): return text
        case .integer(let value):
            return component.formatter == .approximateWordCount || component.formatter == .roundedHundredWordCount
                ? "Approx. \(value.formatted()) words" : value.formatted()
        case .date(let date): return date.formatted(date: .long, time: .omitted)
        case .asset: return ""
        case .lateBound: return ""
        }
    }

    private static func headingText(_ item: ResolvedNarrativeItem) -> String {
        switch item.rule.numbering {
        case .arabic: return "CHAPTER \(item.number)\n\(item.title)"
        case .roman: return "\(roman(item.number))\n\(item.title)"
        default: return item.title
        }
    }

    private static func publicationScope(_ publication: ResolvedPublication) -> NarrativeType {
        publication.narrative.first?.narrativeType ?? .book
    }

    private static func textValue(_ component: ResolvedTemplateComponent) -> String? {
        if case .text(let value) = component.value { return value }
        return nil
    }

    private static func styleID(_ key: String) -> String {
        ["body": "ManuscriptBody", "bookTitle": "BookTitle", "bookSubtitle": "BookSubtitle", "author": "Author", "titlePageMetadata": "TitlePageMetadata", "sectionHeading": "SectionHeading", "chapterHeading": "ChapterHeading", "epigraph": "Epigraph", "sceneBreak": "SceneBreak", "header": "Header", "footer": "Footer"][key] ?? key
    }

    private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    private static func roman(_ number: Int) -> String {
        let table = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = number
        return table.map { value, symbol in
            let repetitions = remaining / value
            remaining %= value
            return String(repeating: symbol, count: repetitions)
        }.joined()
    }

    private static func twips(_ inches: Double) -> Int { Int((inches * 1440).rounded()) }

    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func ids(in xml: String, attribute: String, element: String) -> [String] {
        let pattern = "<\(element) \(attribute)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
            Range($0.range(at: 1), in: xml).map { String(xml[$0]) }
        }
    }
}

enum StoredZIP {
    static func encode(_ entries: [String: Data]) throws -> Data {
        var output = Data()
        var directory = Data()
        for (name, value) in entries.sorted(by: { $0.key < $1.key }) {
            let filename = Data(name.utf8)
            let offset = UInt32(output.count)
            let crc = CRC32.checksum(value)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(crc); output.appendLE(UInt32(value.count)); output.appendLE(UInt32(value.count))
            output.appendLE(UInt16(filename.count)); output.appendLE(UInt16(0)); output.append(filename); output.append(value)
            directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(crc); directory.appendLE(UInt32(value.count)); directory.appendLE(UInt32(value.count))
            directory.appendLE(UInt16(filename.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0)); directory.appendLE(offset); directory.append(filename)
        }
        let offset = UInt32(output.count)
        output.append(directory)
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(directory.count)); output.appendLE(offset); output.appendLE(UInt16(0))
        return output
    }

    static func decode(_ data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var index = 0
        while index + 4 <= data.count, data.u32(index) == 0x04034b50 {
            guard index + 30 <= data.count else { throw ManuscriptRendererError.invalidPackage("A ZIP entry is truncated.") }
            let compression = data.u16(index + 8), compressedSize = Int(data.u32(index + 18)), nameLength = Int(data.u16(index + 26)), extraLength = Int(data.u16(index + 28))
            guard compression == 0 else { throw ManuscriptRendererError.invalidPackage("The validator only supports stored ZIP entries.") }
            let nameStart = index + 30, valueStart = nameStart + nameLength + extraLength, end = valueStart + compressedSize
            guard end <= data.count, let name = String(data: data[nameStart..<(nameStart + nameLength)], encoding: .utf8) else {
                throw ManuscriptRendererError.invalidPackage("A ZIP entry is invalid.")
            }
            result[name] = Data(data[valueStart..<end]); index = end
        }
        return result
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data { for _ in 0..<8 { crc = ((crc ^ UInt32(byte)) & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 } }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: MemoryLayout<T>.size))
    }
    func u16(_ offset: Int) -> UInt16 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian } }
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian } }
}
