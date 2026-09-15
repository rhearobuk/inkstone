import CoreData
import XCTest
@testable import AuthorData

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class ExportCompilerTests: XCTestCase {
    func testCompilesBookInBinderOrderAndProjectsMetadata() throws {
        let fixture = try makeFixture()
        setMetadata("system.book.subtitle", string: "A Novel", on: fixture.book, store: fixture.store)
        setMetadata("system.book.author", string: "Byline", on: fixture.book, store: fixture.store)
        setMetadata("system.book.isbn.paperback", string: "978-1", on: fixture.book, store: fixture.store)
        setMetadata("system.chapter.epigraph", string: "Begin.", on: fixture.chapter, store: fixture.store)
        setMetadata("system.scene.location", string: "Harbor", on: fixture.scene, store: fixture.store)
        setMetadata("system.scene.storyDate", string: "Day 1", on: fixture.scene, store: fixture.store)

        let publication = try ExportCompiler(store: fixture.store).compile(request(for: fixture.book, scope: .book))

        XCTAssertEqual(publication.documents.map(\.title), ["Book", "Part I", "Chapter 1", "Scene 1", "Scene 2"])
        XCTAssertEqual(publication.documents.map(\.depth), [0, 1, 2, 3, 1])
        XCTAssertEqual(publication.project.title, "Project")
        XCTAssertEqual(publication.documents[0].metadata.book?.subtitle, "A Novel")
        XCTAssertEqual(publication.documents[0].metadata.book?.author, "Byline")
        XCTAssertEqual(publication.documents[0].metadata.book?.isbns.first?.number, "978-1")
        XCTAssertEqual(publication.documents[2].metadata.epigraph, "Begin.")
        XCTAssertEqual(publication.documents[3].metadata.location, "Harbor")
        XCTAssertEqual(publication.documents[3].wordCount, 2)
    }

    func testCompilesEachScopeAndNestedDescendants() throws {
        let fixture = try makeFixture()
        let compiler = ExportCompiler(store: fixture.store)

        XCTAssertEqual(try compiler.compile(request(for: fixture.section, scope: .section)).documents.map(\.title), ["Part I", "Chapter 1", "Scene 1"])
        XCTAssertEqual(try compiler.compile(request(for: fixture.chapter, scope: .chapter)).documents.map(\.title), ["Chapter 1", "Scene 1"])
        XCTAssertEqual(try compiler.compile(request(for: fixture.scene, scope: .scene)).documents.map(\.title), ["Scene 1"])
    }

    func testExclusionsAreInheritedUnlessExplicitlyIncluded() throws {
        let fixture = try makeFixture()
        fixture.section.includeInCompile = false
        let compiler = ExportCompiler(store: fixture.store)

        XCTAssertEqual(try compiler.compile(request(for: fixture.book, scope: .book)).documents.map(\.title), ["Book", "Scene 2"])
        XCTAssertEqual(
            try compiler.compile(request(for: fixture.book, scope: .book, includesExcluded: true)).documents.map(\.title),
            ["Book", "Part I", "Chapter 1", "Scene 1", "Scene 2"]
        )
    }

    func testLocallyExcludedAndEmptyDocumentsRemainPredictable() throws {
        let fixture = try makeFixture()
        fixture.scene.includeInCompile = false
        let emptyChapter = fixture.store.documents.create {
            $0.sourceIdentifier = "empty"; $0.title = "Empty"; $0.kind = DocumentKind.text.rawValue
            $0.narrativeType = NarrativeType.chapter.rawValue; $0.orderIndex = 2
            $0.project = fixture.book.project; $0.parent = fixture.book; $0.plainText = ""
        }
        let compiler = ExportCompiler(store: fixture.store)

        XCTAssertEqual(
            try compiler.compile(request(for: fixture.book, scope: .book)).documents.map(\.title),
            ["Book", "Part I", "Chapter 1", "Scene 2", "Empty"]
        )
        XCTAssertEqual(
            try compiler.compile(request(for: emptyChapter, scope: .chapter)).documents[0].prose,
            []
        )
    }

    func testPlainTextDocumentsBecomeParagraphBlocks() throws {
        let fixture = try makeFixture()
        fixture.scene.plainText = "First paragraph\nSecond paragraph"

        let prose = try ExportCompiler(store: fixture.store)
            .compile(request(for: fixture.scene, scope: .scene)).documents[0].prose

        XCTAssertEqual(prose.map(\.plainText), ["First paragraph", "Second paragraph"])
        XCTAssertTrue(prose.flatMap(\.spans).allSatisfy { !$0.isBold && !$0.isItalic })
    }

    func testRichTextPreservesEmphasisAndPlainTextIsAvailable() throws {
        let fixture = try makeFixture()
        let attributed = NSMutableAttributedString(string: "Bold and italic")
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 4))
        attributed.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask), range: NSRange(location: 9, length: 6))
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        addRTF(data, on: fixture.scene, store: fixture.store)

        let prose = try ExportCompiler(store: fixture.store).compile(request(for: fixture.scene, scope: .scene)).documents[0].prose

        XCTAssertEqual(prose[0].plainText, "Bold and italic")
        XCTAssertEqual(prose[0].spans.map(\.isBold), [true, false, false])
        XCTAssertEqual(prose[0].spans.map(\.isItalic), [false, false, true])
    }

    func testMalformedRTFFallsBackOrThrowsAndCompilationIsDeterministic() throws {
        let fixture = try makeFixture()
        addRTF(Data("not rtf".utf8), on: fixture.scene, store: fixture.store)
        let compiler = ExportCompiler(store: fixture.store)
        let first = try compiler.compile(request(for: fixture.book, scope: .book))
        let second = try compiler.compile(request(for: fixture.book, scope: .book))

        XCTAssertEqual(first.documents.map(\.id), second.documents.map(\.id))
        XCTAssertEqual(first.diagnostics.map(\.kind), [.richTextFallback])
        fixture.scene.plainText = nil
        XCTAssertThrowsError(try compiler.compile(request(for: fixture.scene, scope: .scene))) {
            XCTAssertEqual($0 as? ExportCompilerError, .malformedRichText(documentID: fixture.scene.id, resourceID: fixture.scene.resources.first!.id))
        }
    }

    func testRejectsInvalidScopeAndForeignRoot() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try ExportCompiler(store: fixture.store).compile(request(for: fixture.book, scope: .chapter)))
        let other = fixture.store.projects.create {
            $0.title = "Other"; $0.sourceIdentifier = "other"; $0.sourceFormat = "native"; $0.createdAt = Date(); $0.modifiedAt = Date()
        }
        XCTAssertThrowsError(try ExportCompiler(store: fixture.store).compile(ExportRequest(projectID: other.id, rootDocumentID: fixture.book.id, scope: .book)))
    }

    private func request(for document: Document, scope: ExportScope, includesExcluded: Bool = false) -> ExportRequest {
        ExportRequest(projectID: document.project.id, rootDocumentID: document.id, scope: scope, includesExcludedDocuments: includesExcluded)
    }

    private func makeFixture() throws -> (store: AuthorDataStore, book: Document, section: Document, chapter: Document, scene: Document) {
        let store = try AuthorDataStore(inMemory: true)
        let project = store.projects.create {
            $0.title = "Project"; $0.sourceIdentifier = "project"; $0.sourceFormat = "native"; $0.createdAt = Date(timeIntervalSince1970: 1); $0.modifiedAt = Date(timeIntervalSince1970: 2)
        }
        func document(_ title: String, _ type: NarrativeType, parent: Document? = nil, order: Int64) -> Document {
            store.documents.create {
                $0.sourceIdentifier = title; $0.title = title; $0.kind = DocumentKind.text.rawValue; $0.narrativeType = type.rawValue
                $0.orderIndex = order; $0.project = project; $0.parent = parent; $0.plainText = title == "Scene 1" ? "one two" : ""
                $0.ownWordCount = WordCountService.count(in: $0.plainText); $0.actualWordCount = $0.ownWordCount
            }
        }
        let book = document("Book", .book, order: 0)
        let section = document("Part I", .section, parent: book, order: 0)
        let chapter = document("Chapter 1", .chapter, parent: section, order: 0)
        let scene = document("Scene 1", .scene, parent: chapter, order: 0)
        _ = document("Scene 2", .scene, parent: book, order: 1)
        return (store, book, section, chapter, scene)
    }

    private func setMetadata(_ key: String, string: String, on document: Document, store: AuthorDataStore) {
        let field = store.metadataFields.create {
            $0.key = key; $0.displayName = key; $0.valueType = "text"; $0.isSourceDefined = true; $0.orderIndex = 0; $0.project = document.project
        }
        _ = store.metadataValues.create { $0.stringValue = string; $0.field = field; $0.document = document }
    }

    private func addRTF(_ data: Data, on document: Document, store: AuthorDataStore) {
        _ = store.resources.create {
            $0.sourcePath = "content.rtf"; $0.role = "content"; $0.mediaType = "application/rtf"; $0.byteCount = Int64(data.count)
            $0.sha256 = "test"; $0.data = data; $0.isSourcePreserved = false; $0.project = document.project; $0.document = document
        }
    }
}
