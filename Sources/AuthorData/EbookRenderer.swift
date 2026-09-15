import Foundation

public enum EbookRendererError: LocalizedError, Equatable {
    case invalidPublication(String)
    case invalidPackage(String)
    case fileWrite(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidPublication(let message), .invalidPackage(let message):
            return message
        case .fileWrite(let url):
            return "The ebook could not be written to \(url.lastPathComponent)."
        }
    }
}

public struct EbookDocument: Sendable {
    public let data: Data
    public let suggestedFilename: String
    public let diagnostics: [String]
}

/// Produces a reflowable EPUB 3.3 package from an already-resolved publication.
public enum EbookRenderer {
    private static let epubNamespace = "http://www.idpf.org/2007/ops"

    public static func render(_ publication: ResolvedPublication, modifiedAt: Date = Date()) throws -> EbookDocument {
        guard publication.outputFormat == .epub else {
            throw EbookRendererError.invalidPublication("Ebook rendering requires EPUB output.")
        }
        guard case .ready = publication.readiness else {
            throw EbookRendererError.invalidPublication("The publication is not ready to export.")
        }

        let title = componentText("title.book", in: publication.frontMatter) ?? "Untitled"
        let author = componentText("title.author", in: publication.frontMatter) ?? "Unknown"
        let language = metadataText("book.language", in: publication) ?? "und"
        let isbn = metadataText("publication.isbn", in: publication)
        let identifier = isbn.map { "urn:isbn:\($0)" } ?? "urn:uuid:\(stableUUID(for: publication))"
        let resources = try resources(for: publication, title: title, author: author, language: language)
        let package = packageDocument(
            publication: publication, resources: resources, title: title, author: author, language: language,
            identifier: identifier, isbn: isbn, modifiedAt: modifiedAt
        )
        var entries: [(String, Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("EPUB/package.opf", Data(package.utf8)),
            ("EPUB/nav.xhtml", Data(resources.navigation.utf8)),
            ("EPUB/styles/book.css", Data(css.utf8))
        ]
        entries.append(contentsOf: resources.documents.map { ("EPUB/\($0.path)", Data($0.xhtml.utf8)) })
        if let cover = resources.cover {
            entries.append(("EPUB/\(cover.path)", cover.data))
        }
        let data = try EPUBStoredZIP.encode(entries)
        try validate(data)
        return EbookDocument(
            data: data,
            suggestedFilename: suggestedFilename(for: publication),
            diagnostics: publication.diagnostics + resources.diagnostics
        )
    }

    public static func write(_ document: EbookDocument, to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw EbookRendererError.fileWrite(url)
        }
        do {
            try document.data.write(to: url, options: .atomic)
        } catch {
            throw EbookRendererError.fileWrite(url)
        }
    }

    public static func suggestedFilename(for publication: ResolvedPublication) -> String {
        let title = componentText("title.book", in: publication.frontMatter) ?? "Untitled"
        let root = publication.narrative.first
        let qualifier: String
        if let root, root.narrativeType != .book {
            qualifier = " - \(root.narrativeType.rawValue.capitalized) \(root.number)"
        } else {
            qualifier = ""
        }
        return "\(safeFilename(title))\(qualifier) - Ebook.epub"
    }

    /// Validates the structural EPUB requirements that do not require an external EPUBCheck install.
    public static func validate(_ data: Data) throws {
        let entries = try EPUBStoredZIP.decode(data)
        guard entries.first?.name == "mimetype", entries.first?.compression == 0,
              String(data: entries.first!.data, encoding: .utf8) == "application/epub+zip" else {
            throw EbookRendererError.invalidPackage("The EPUB mimetype must be the first uncompressed ZIP entry.")
        }
        let files = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.data) })
        let required = ["META-INF/container.xml", "EPUB/package.opf", "EPUB/nav.xhtml", "EPUB/styles/book.css"]
        guard required.allSatisfy({ files[$0] != nil }) else {
            throw EbookRendererError.invalidPackage("The EPUB package is missing a required resource.")
        }
        for path in ["META-INF/container.xml", "EPUB/package.opf", "EPUB/nav.xhtml"] {
            guard let value = files[path], XMLParser(data: value).parse() else {
                throw EbookRendererError.invalidPackage("The EPUB contains malformed XML in \(path).")
            }
        }
        let opf = String(decoding: files["EPUB/package.opf"]!, as: UTF8.self)
        let manifest = attributeValues("href", in: opf, element: "item")
        for href in manifest {
            guard files["EPUB/\(href)"] != nil else {
                throw EbookRendererError.invalidPackage("The EPUB manifest references a missing resource: \(href).")
            }
        }
        let ids = Set(attributeValues("id", in: opf, element: "item"))
        for id in attributeValues("idref", in: opf, element: "itemref") where !ids.contains(id) {
            throw EbookRendererError.invalidPackage("The EPUB spine references an unknown manifest item: \(id).")
        }
        let nav = String(decoding: files["EPUB/nav.xhtml"]!, as: UTF8.self)
        for href in attributeValues("href", in: nav, element: "a") {
            let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
            guard files["EPUB/\(path)"] != nil else {
                throw EbookRendererError.invalidPackage("The navigation references a missing resource: \(href).")
            }
        }
    }

    private struct ContentDocument {
        let id: String
        let path: String
        let xhtml: String
        let navigationLabel: String?
        let navigationID: String?
    }

    private struct Cover {
        let path: String
        let mediaType: String
        let data: Data
    }

    private struct Resources {
        let documents: [ContentDocument]
        let cover: Cover?
        let navigation: String
        let diagnostics: [String]
    }

    private static func resources(for publication: ResolvedPublication, title: String, author: String, language: String) throws -> Resources {
        var documents: [ContentDocument] = []
        var diagnostics: [String] = []
        let coverAsset = publication.frontMatter.first(where: { $0.id == "cover.front" }).flatMap(assetValue)
        let cover: Cover?
        if let coverAsset, let data = coverAsset.data, !data.isEmpty {
            let ext = imageExtension(mediaType: coverAsset.mediaType, sourcePath: coverAsset.sourcePath)
            cover = Cover(path: "images/cover.\(ext)", mediaType: coverAsset.mediaType, data: data)
            documents.append(ContentDocument(id: "cover-page", path: "text/cover.xhtml", xhtml: coverXHTML(title: title, language: language, imagePath: "../\(cover!.path)"), navigationLabel: nil, navigationID: nil))
        } else {
            cover = nil
            if coverAsset != nil { diagnostics.append("The configured front cover had no image data and was omitted.") }
        }

        let titleComponents = publication.frontMatter.filter { !$0.id.hasPrefix("cover.") && !$0.id.hasPrefix("copyright.") }
        if !titleComponents.isEmpty {
            documents.append(ContentDocument(id: "title-page", path: "text/title.xhtml", xhtml: frontMatterXHTML(title: title, language: language, components: titleComponents), navigationLabel: "Title Page", navigationID: "title-page"))
        }
        let copyright = publication.frontMatter.filter { $0.id.hasPrefix("copyright.") }
        if !copyright.isEmpty {
            documents.append(ContentDocument(id: "copyright-page", path: "text/copyright.xhtml", xhtml: frontMatterXHTML(title: "Publication Information", language: language, components: copyright), navigationLabel: "Publication Information", navigationID: "copyright-page"))
        }

        var current: (item: ResolvedNarrativeItem, index: Int, body: [String], titleID: String, navigation: Bool)?
        func finishCurrent() {
            guard let current else { return }
            let path = "text/\(current.item.narrativeType.rawValue)-\(current.index).xhtml"
            let xhtml = documentXHTML(title: current.item.title, language: language, body: current.body)
            documents.append(ContentDocument(id: "content-\(current.item.narrativeType.rawValue)-\(current.index)", path: path, xhtml: xhtml, navigationLabel: current.navigation ? current.item.title : nil, navigationID: current.navigation ? current.titleID : nil))
        }
        var ordinal = 0
        var previousWasScene = false
        for item in publication.narrative {
            let startsResource = item.narrativeType == .section || item.narrativeType == .chapter || current == nil
            if startsResource {
                finishCurrent()
                ordinal += 1
                let titleID = "heading-\(ordinal)"
                current = (item, ordinal, narrativeHeading(item, id: titleID) + narrativeProse(item), titleID, item.rule.appearsInNavigation && !item.title.isEmpty)
            } else if item.narrativeType == .scene {
                if previousWasScene && item.rule.insertsSceneBreakBefore {
                    current!.body.append(sceneBreak(marker: item.rule.sceneBreakMarker ?? "* * *"))
                }
                current!.body.append(contentsOf: narrativeProse(item))
            } else {
                current!.body.append(contentsOf: narrativeProse(item))
            }
            previousWasScene = item.narrativeType == .scene
        }
        finishCurrent()
        let navigation = navigationXHTML(title: title, language: language, documents: documents)
        return Resources(documents: documents, cover: cover, navigation: navigation, diagnostics: diagnostics)
    }

    private static func packageDocument(publication: ResolvedPublication, resources: Resources, title: String, author: String, language: String, identifier: String, isbn: String?, modifiedAt: Date) -> String {
        let publisher = metadataText("book.publisher", in: publication)
        let date = metadataDate("book.publicationDate", in: publication)
        let rights = metadataText("book.copyright", in: publication)
        let series = metadataText("book.series.name", in: publication)
        let volume = metadataInteger("book.series.volume", in: publication)
        let edition = metadataText("book.edition", in: publication)
        let manifestDocuments = resources.documents.map { "<item id=\"\($0.id)\" href=\"\($0.path)\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let coverManifest = resources.cover.map { "<item id=\"cover-image\" href=\"\($0.path)\" media-type=\"\(xml($0.mediaType))\" properties=\"cover-image\"/>" } ?? ""
        let spine = resources.documents.map { "<itemref idref=\"\($0.id)\"/>" }.joined()
        var optional = ""
        if let publisher { optional += "<dc:publisher>\(xml(publisher))</dc:publisher>" }
        if let date { optional += "<dc:date>\(isoDate(date))</dc:date>" }
        if let rights { optional += "<dc:rights>\(xml(rights))</dc:rights>" }
        if let series { optional += "<meta property=\"belongs-to-collection\" id=\"series\">\(xml(series))</meta><meta refines=\"#series\" property=\"collection-type\">series</meta>" }
        if let volume { optional += "<meta property=\"group-position\">\(volume)</meta>" }
        if let edition { optional += "<meta property=\"edition\">\(xml(edition))</meta>" }
        if isbn != nil { optional += "<meta property=\"identifier-type\" refines=\"#pub-id\">isbn</meta>" }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(xml(language))" prefix="dcterms: http://purl.org/dc/terms/">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="pub-id">\(xml(identifier))</dc:identifier><dc:title>\(xml(title))</dc:title><dc:creator>\(xml(author))</dc:creator><dc:language>\(xml(language))</dc:language><meta property="dcterms:modified">\(isoDateTime(modifiedAt))</meta>\(optional)
          </metadata>
          <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="styles/book.css" media-type="text/css"/>\(coverManifest)\(manifestDocuments)</manifest>
          <spine>\(spine)</spine>
        </package>
        """
    }

    private static let containerXML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\" version=\"1.0\"><rootfiles><rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"
    private static let css = "html { font-size: 100%; } body { margin: 5%; line-height: 1.4; } h1, .book-title, .subtitle, .author, .scene-break { text-align: center; } h1 { margin: 2em 0 1em; break-before: page; } .book-title { font-size: 2em; margin-top: 25%; } .subtitle { font-size: 1.3em; } .author { font-size: 1.2em; margin-top: 3em; } .front-matter { break-after: page; } .front-matter-body { margin: 1em 0; } .epigraph { text-align: center; font-style: italic; margin: 2em; } .scene-break { margin: 2em 0; } p { margin: 0 0 1em; } img.cover { display: block; max-width: 100%; max-height: 95vh; margin: auto; }"

    private static func coverXHTML(title: String, language: String, imagePath: String) -> String {
        documentXHTML(title: title, language: language, body: ["<section epub:type=\"cover\" aria-label=\"Cover\"><img class=\"cover\" src=\"\(xml(imagePath))\" alt=\"Cover of \(xml(title))\"/></section>"])
    }

    private static func frontMatterXHTML(title: String, language: String, components: [ResolvedTemplateComponent]) -> String {
        let body = components.map { component -> String in
            let value = formatted(component)
            let cssClass = component.style == "frontMatterBody" ? "front-matter-body" : component.style
            let content = xml(value).replacingOccurrences(of: "\n", with: "<br/>")
            if component.id == "title.book" { return "<h1 class=\"book-title\">\(content)</h1>" }
            return "<p class=\"\(xml(cssClass))\">\(content)</p>"
        }
        return documentXHTML(title: title, language: language, body: ["<section class=\"front-matter\" epub:type=\"frontmatter\">\(body.joined())</section>"])
    }

    private static func documentXHTML(title: String, language: String, body: [String]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE html><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"\(epubNamespace)\" xml:lang=\"\(xml(language))\" lang=\"\(xml(language))\"><head><title>\(xml(title))</title><link rel=\"stylesheet\" type=\"text/css\" href=\"../styles/book.css\"/></head><body>\(body.joined())</body></html>"
    }

    private static func navigationXHTML(title: String, language: String, documents: [ContentDocument]) -> String {
        let items = documents.compactMap { document -> String? in
            guard let label = document.navigationLabel, let id = document.navigationID else { return nil }
            return "<li><a href=\"\(xml(document.path))#\(xml(id))\">\(xml(label))</a></li>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE html><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"\(epubNamespace)\" xml:lang=\"\(xml(language))\" lang=\"\(xml(language))\"><head><title>\(xml(title)) — Contents</title></head><body><nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>\(items)</ol></nav></body></html>"
    }

    private static func narrativeHeading(_ item: ResolvedNarrativeItem, id: String) -> [String] {
        guard item.rule.displaysTitle, !item.title.isEmpty else { return [] }
        let heading = item.rule.numbering == .arabic ? "Chapter \(item.number): \(item.title)" : item.title
        var result = ["<h1 id=\"\(id)\">\(xml(heading))</h1>"]
        if item.rule.displaysSubtitle, let subtitle = item.subtitle, !subtitle.isEmpty { result.append("<p class=\"subtitle\">\(xml(subtitle))</p>") }
        return result
    }

    private static func narrativeProse(_ item: ResolvedNarrativeItem) -> [String] {
        var result: [String] = []
        if let epigraph = item.epigraph, !epigraph.isEmpty {
            result.append("<blockquote class=\"epigraph\"><p>\(xml(epigraph))</p></blockquote>")
        }
        result.append(contentsOf: item.prose.map { block in
            let content = block.spans.map { span -> String in
                let content = xml(span.text)
                if span.isBold && span.isItalic { return "<strong><em>\(content)</em></strong>" }
                if span.isBold { return "<strong>\(content)</strong>" }
                if span.isItalic { return "<em>\(content)</em>" }
                return content
            }.joined()
            return "<p>\(content)</p>"
        })
        return result
    }

    private static func sceneBreak(marker: String) -> String {
        "<hr class=\"scene-break\" role=\"separator\" aria-label=\"Scene break\"/><p class=\"scene-break\" aria-hidden=\"true\">\(xml(marker))</p>"
    }

    private static func componentText(_ id: String, in components: [ResolvedTemplateComponent]) -> String? {
        components.first(where: { $0.id == id }).flatMap(textValue)
    }
    private static func metadataText(_ key: String, in publication: ResolvedPublication) -> String? {
        guard case .text(let value) = publication.metadata[key] else { return nil }
        return value
    }
    private static func metadataInteger(_ key: String, in publication: ResolvedPublication) -> Int64? {
        guard case .integer(let value) = publication.metadata[key] else { return nil }
        return value
    }
    private static func metadataDate(_ key: String, in publication: ResolvedPublication) -> Date? {
        guard case .date(let value) = publication.metadata[key] else { return nil }
        return value
    }
    private static func textValue(_ component: ResolvedTemplateComponent) -> String? {
        guard case .text(let value) = component.value else { return nil }
        return value
    }
    private static func assetValue(_ component: ResolvedTemplateComponent) -> ExportCoverAsset? {
        guard case .asset(let value) = component.value else { return nil }
        return value
    }
    private static func formatted(_ component: ResolvedTemplateComponent) -> String {
        switch component.value {
        case .text(let value), .lateBound(let value): return value
        case .integer(let value): return value.formatted()
        case .date(let value): return value.formatted(date: .long, time: .omitted)
        case .asset: return ""
        }
    }
    private static func stableUUID(for publication: ResolvedPublication) -> UUID {
        let seed = "\(publication.templateID)#\(publication.templateVersion)#\(publication.narrative.map(\.id.uuidString).joined(separator: ","))"
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in seed.utf8.enumerated() { bytes[index % 16] = bytes[index % 16] &+ byte &+ UInt8(truncatingIfNeeded: index) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func imageExtension(mediaType: String, sourcePath: String) -> String {
        switch mediaType { case "image/jpeg": return "jpg"; case "image/png": return "png"; case "image/gif": return "gif"; case "image/svg+xml": return "svg"; default:
            let ext = URL(fileURLWithPath: sourcePath).pathExtension.lowercased()
            return ext.isEmpty ? "img" : ext
        }
    }
    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let result = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Untitled" : result
    }
    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func isoDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date).prefix(10).description }
    private static func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: date)
    }
    private static func attributeValues(_ attribute: String, in xml: String, element: String) -> [String] {
        let pattern = "<\(element)\\b[^>]*\\b\(attribute)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
    }
}

enum EPUBStoredZIP {
    struct Entry { let name: String; let compression: UInt16; let data: Data }
    static func encode(_ entries: [(String, Data)]) throws -> Data {
        guard entries.first?.0 == "mimetype", Set(entries.map(\.0)).count == entries.count else {
            throw EbookRendererError.invalidPackage("The EPUB ZIP entries are invalid.")
        }
        var output = Data(); var directory = Data()
        for (name, value) in entries {
            let filename = Data(name.utf8), offset = UInt32(output.count), crc = checksum(value)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(crc); output.appendLE(UInt32(value.count)); output.appendLE(UInt32(value.count)); output.appendLE(UInt16(filename.count)); output.appendLE(UInt16(0)); output.append(filename); output.append(value)
            directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(crc); directory.appendLE(UInt32(value.count)); directory.appendLE(UInt32(value.count)); directory.appendLE(UInt16(filename.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0)); directory.appendLE(offset); directory.append(filename)
        }
        let offset = UInt32(output.count); output.append(directory); output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count)); output.appendLE(UInt32(directory.count)); output.appendLE(offset); output.appendLE(UInt16(0))
        return output
    }
    static func decode(_ data: Data) throws -> [Entry] {
        var result: [Entry] = []; var index = 0
        while index + 4 <= data.count, data.u32(index) == 0x04034b50 {
            guard index + 30 <= data.count else { throw EbookRendererError.invalidPackage("A ZIP entry is truncated.") }
            let compression = data.u16(index + 8), size = Int(data.u32(index + 18)), nameLength = Int(data.u16(index + 26)), extraLength = Int(data.u16(index + 28)), valueStart = index + 30 + nameLength + extraLength, end = valueStart + size
            guard compression == 0 else { throw EbookRendererError.invalidPackage("The EPUB ZIP uses unsupported compression.") }
            guard nameLength > 0, valueStart <= data.count, end <= data.count else { throw EbookRendererError.invalidPackage("An EPUB ZIP entry is truncated.") }
            guard let name = String(data: data[(index + 30)..<(index + 30 + nameLength)], encoding: .utf8) else { throw EbookRendererError.invalidPackage("An EPUB ZIP entry has an invalid name.") }
            result.append(Entry(name: name, compression: compression, data: Data(data[valueStart..<end]))); index = end
        }
        return result
    }
    private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data { for _ in 0..<8 { crc = ((crc ^ UInt32(byte)) & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 } }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; append(Data(bytes: &little, count: MemoryLayout<T>.size)) }
    func u16(_ offset: Int) -> UInt16 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian } }
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian } }
}
