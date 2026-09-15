import CoreData
import Foundation

/// The kind of value a `NarrativeFieldDescriptor` holds, controlling both storage
/// (`MetadataValue`'s typed columns) and how the field is presented in the UI.
public enum NarrativeFieldValueKind: String, Sendable {
    case text
    case longText
    case number
    case date
}

/// Describes one piece of type-specific metadata (e.g. "ISBN" on a Book). Values are persisted
/// through the existing generic `MetadataField`/`MetadataValue` system, keyed by `key`, so no new
/// Core Data attributes are required per field.
public struct NarrativeFieldDescriptor: Sendable {
    public let key: String
    public let displayName: String
    public let valueKind: NarrativeFieldValueKind
    public let placeholder: String?

    public init(key: String, displayName: String, valueKind: NarrativeFieldValueKind, placeholder: String? = nil) {
        self.key = key
        self.displayName = displayName
        self.valueKind = valueKind
        self.placeholder = placeholder
    }
}

/// Standard publishing product formats. Each published format requires its own ISBN; edition is
/// recorded separately because it identifies a version of a format rather than a format itself.
public enum BookFormat: String, CaseIterable, Identifiable, Sendable {
    case unspecified
    case hardback
    case paperback
    case ebook
    case audiobook
    case largePrint
    case boardBook
    case libraryBinding

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .unspecified: "Unspecified (Legacy)"
        case .hardback: "Hardback"
        case .paperback: "Paperback"
        case .ebook: "E-Book"
        case .audiobook: "Audiobook"
        case .largePrint: "Large Print"
        case .boardBook: "Board Book"
        case .libraryBinding: "Library Binding"
        }
    }

    public var isbnMetadataKey: String {
        if self == .unspecified {
            return "system.book.isbn"
        }
        return "system.book.isbn.\(rawValue)"
    }

    public var isUserSelectable: Bool {
        self != .unspecified
    }

    public var isbnFieldDescriptor: NarrativeFieldDescriptor {
        NarrativeFieldDescriptor(
            key: isbnMetadataKey,
            displayName: "\(displayName) ISBN",
            valueKind: .text,
            placeholder: "978-0-000-00000-0"
        )
    }
}

public struct BookISBN: Identifiable, Sendable {
    public let format: BookFormat
    public let number: String

    public var id: BookFormat { format }

    public init(format: BookFormat, number: String) {
        self.format = format
        self.number = number
    }
}

public enum BookCoverKind: String, CaseIterable, Identifiable, Sendable {
    case front
    case back
    case full

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .front: "Front Cover"
        case .back: "Back Cover"
        case .full: "Full Cover"
        }
    }

    public var detail: String {
        switch self {
        case .front: "Front artwork"
        case .back: "Back artwork"
        case .full: "Front, spine, back, and overleaves"
        }
    }

    public var resourceRole: String {
        "bookCover.\(rawValue)"
    }
}

/// The fixed set of system-defined metadata fields shown for each `NarrativeType`, plus the
/// shared "Target Word Count" field every level gets.
public enum NarrativeMetadataSchema {
    public static let targetWordCountKey = "system.targetWordCount"

    public static func fields(for type: NarrativeType) -> [NarrativeFieldDescriptor] {
        let targetWordCount = NarrativeFieldDescriptor(
            key: targetWordCountKey,
            displayName: "Target Word Count",
            valueKind: .number,
            placeholder: "e.g. 80000"
        )
        switch type {
        case .book:
            return [
                NarrativeFieldDescriptor(key: "system.book.subtitle", displayName: "Subtitle", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.book.seriesName", displayName: "Series Name", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.book.volumeNumber", displayName: "Volume Number", valueKind: .number),
                NarrativeFieldDescriptor(key: "system.book.volumeCount", displayName: "Number of Volumes", valueKind: .number),
                NarrativeFieldDescriptor(key: "system.book.publisher", displayName: "Publisher", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.book.publicationDate", displayName: "Publication Date", valueKind: .date),
                NarrativeFieldDescriptor(key: "system.book.copyright", displayName: "Copyright Notice", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.book.language", displayName: "Language", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.book.edition", displayName: "Edition", valueKind: .text),
                targetWordCount
            ]
        case .section:
            return [
                NarrativeFieldDescriptor(key: "system.section.subtitle", displayName: "Subtitle", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.section.epigraph", displayName: "Epigraph", valueKind: .longText),
                targetWordCount
            ]
        case .chapter:
            return [
                NarrativeFieldDescriptor(key: "system.chapter.subtitle", displayName: "Subtitle", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.chapter.epigraph", displayName: "Epigraph", valueKind: .longText),
                NarrativeFieldDescriptor(key: "system.chapter.povCharacter", displayName: "POV Character", valueKind: .text),
                targetWordCount
            ]
        case .scene:
            return [
                NarrativeFieldDescriptor(key: "system.scene.povCharacter", displayName: "POV Character", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.scene.location", displayName: "Location", valueKind: .text),
                NarrativeFieldDescriptor(key: "system.scene.storyDate", displayName: "In-story Date/Time", valueKind: .text),
                targetWordCount
            ]
        }
    }
}

/// Reads and writes narrative metadata field values, lazily creating the backing
/// `MetadataField` definitions the first time a key is used in a project.
@MainActor
public enum NarrativeMetadataStore {
    @discardableResult
    public static func field(
        for key: String,
        displayName: String,
        valueType: NarrativeFieldValueKind,
        in project: WritingProject,
        store: AuthorDataStore
    ) -> MetadataField {
        if let existing = project.metadataFields.first(where: { $0.key == key }) {
            return existing
        }
        let maxOrder = project.metadataFields.map(\.orderIndex).max() ?? -1
        return store.metadataFields.create {
            $0.key = key
            $0.displayName = displayName
            $0.valueType = valueType.rawValue
            $0.isSourceDefined = true
            $0.sourceIdentifier = nil
            $0.orderIndex = maxOrder + 1
            $0.project = project
        }
    }

    public static func value(for descriptor: NarrativeFieldDescriptor, on document: Document) -> MetadataValue? {
        document.metadataValues.first { $0.field.key == descriptor.key }
    }

    public static func stringValue(for descriptor: NarrativeFieldDescriptor, on document: Document) -> String {
        guard let value = value(for: descriptor, on: document) else { return "" }
        switch descriptor.valueKind {
        case .number:
            return value.integerValue.map { "\($0)" } ?? ""
        case .date:
            return value.dateValue.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        case .text, .longText:
            return value.stringValue ?? ""
        }
    }

    public static func setValue(
        _ rawValue: String,
        for descriptor: NarrativeFieldDescriptor,
        on document: Document,
        store: AuthorDataStore
    ) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let field = self.field(
            for: descriptor.key,
            displayName: descriptor.displayName,
            valueType: descriptor.valueKind,
            in: document.project,
            store: store
        )
        let existing = value(for: descriptor, on: document)
        if trimmed.isEmpty {
            if let existing { store.context.delete(existing) }
            return
        }
        let metadataValue = existing ?? store.metadataValues.create {
            $0.field = field
            $0.document = document
        }
        switch descriptor.valueKind {
        case .number:
            metadataValue.integerValue = Int64(trimmed).map { NSNumber(value: $0) }
            metadataValue.stringValue = nil
        case .date:
            metadataValue.dateValue = ISO8601DateFormatter().date(from: trimmed)
            metadataValue.stringValue = nil
        case .text, .longText:
            metadataValue.stringValue = trimmed
        }
    }

    public static func bookISBNs(on document: Document) -> [BookISBN] {
        BookFormat.allCases.compactMap { format in
            guard let value = document.metadataValues.first(where: { $0.field.key == format.isbnMetadataKey }) else {
                return nil
            }
            return BookISBN(format: format, number: value.stringValue ?? "")
        }
    }

    public static func addBookISBN(
        for format: BookFormat,
        on document: Document,
        store: AuthorDataStore
    ) {
        guard format.isUserSelectable else { return }
        guard !document.metadataValues.contains(where: { $0.field.key == format.isbnMetadataKey }) else {
            return
        }
        let field = self.field(
            for: format.isbnMetadataKey,
            displayName: format.isbnFieldDescriptor.displayName,
            valueType: .text,
            in: document.project,
            store: store
        )
        _ = store.metadataValues.create {
            $0.field = field
            $0.document = document
            $0.stringValue = ""
        }
    }

    public static func setBookISBN(
        _ rawValue: String,
        for format: BookFormat,
        on document: Document,
        store: AuthorDataStore
    ) {
        addBookISBN(for: format, on: document, store: store)
        guard let value = document.metadataValues.first(where: { $0.field.key == format.isbnMetadataKey }) else {
            return
        }
        value.stringValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func removeBookISBN(for format: BookFormat, on document: Document, store: AuthorDataStore) {
        guard let value = document.metadataValues.first(where: { $0.field.key == format.isbnMetadataKey }) else {
            return
        }
        store.context.delete(value)
    }
}

/// Counts words in plain text and keeps `Document.actualWordCount` up to date incrementally as
/// text is edited or the tree is restructured, so no full-tree recalculation is ever needed.
public enum WordCountService {
    public static func count(in text: String?) -> Int64 {
        guard let text, !text.isEmpty else { return 0 }
        return Int64(text.split { $0.isWhitespace || $0.isNewline }.count)
    }

    /// Adds `delta` to `document.actualWordCount` and every one of its ancestors' rollups.
    public static func propagate(delta: Int64, from document: Document) {
        guard delta != 0 else { return }
        document.actualWordCount += delta
        for ancestor in document.ancestors {
            ancestor.actualWordCount += delta
        }
    }

    /// Call whenever a document's `plainText` is saved. Recomputes its own word count and
    /// propagates only the delta up the ancestor chain.
    public static func recomputeOwnWordCount(for document: Document) {
        let newCount = count(in: document.plainText)
        let delta = newCount - document.ownWordCount
        document.ownWordCount = newCount
        propagate(delta: delta, from: document)
    }

    /// Call before detaching `document` from `oldParent` (move, trash-permanent-delete) so the
    /// old ancestor chain's rollups no longer include this subtree's total.
    public static func removeSubtree(_ document: Document, from oldParent: Document?) {
        guard let oldParent else { return }
        let total = document.actualWordCount
        guard total != 0 else { return }
        oldParent.actualWordCount -= total
        for ancestor in oldParent.ancestors {
            ancestor.actualWordCount -= total
        }
    }

    /// Call after attaching `document` under `newParent` so the new ancestor chain's rollups
    /// include this subtree's total.
    public static func addSubtree(_ document: Document, to newParent: Document?) {
        guard let newParent else { return }
        let total = document.actualWordCount
        guard total != 0 else { return }
        newParent.actualWordCount += total
        for ancestor in newParent.ancestors {
            ancestor.actualWordCount += total
        }
    }
}
