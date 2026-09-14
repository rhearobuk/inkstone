# AuthorData

`AuthorData` is a Core Data foundation for a Universal Apple writing application. It contains no UI. The Swift package supports macOS 13, iOS/tvOS 16, watchOS 9, and visionOS 1 or newer.

## What is included

- A normalized, versioned Core Data schema with application-level UUID primary keys.
- Typed `NSManagedObject` classes and a typed CRUD repository for every entity.
- SQLite and in-memory persistent-store setup with automatic lightweight migration.
- A deterministic, idempotent Scrivener 3 importer for the supplied project XML and `Files` tree.
- Explicit import runs, validation, errors, warnings, source hashes, and provenance.
- Structured semantic entities, aliases, mentions, annotations, document links, revisions, and typed metadata values for agent-safe querying.

The editable model is `Sources/AuthorData/Resources/AuthorData.xcdatamodeld`. Swift Package Manager does not invoke `momc` for this resource arrangement, so the target also ships `AuthorData.momd`, compiled from the same model. After editing the model, regenerate it:

```sh
rm -rf Sources/AuthorData/Resources/AuthorData.momd
mkdir Sources/AuthorData/Resources/AuthorData.momd
xcrun momc \
  Sources/AuthorData/Resources/AuthorData.xcdatamodeld \
  Sources/AuthorData/Resources/AuthorData.momd
```

## Use

```swift
import AuthorData

let store = try AuthorDataStore(storeURL: applicationSupportURL)
let importer = ScrivenerImporter(store: store)
let result = try importer.importProject(
    xmlURL: projectXMLURL,
    filesURL: projectFilesURL
)

let documents = try store.documents.fetchAll(
    predicate: NSPredicate(format: "project.id == %@", result.projectID as CVarArg),
    sortedBy: [NSSortDescriptor(key: "orderIndex", ascending: true)]
)
```

Use `AuthorDataStore(inMemory: true)` for previews and tests. All mutations occur on the main actor because `NSManagedObjectContext` and managed objects are queue-confined.

## Import guarantees

- Scrivener project and binder UUIDs are retained as `WritingProject.id` and `Document.id`.
- Derived IDs use a namespaced SHA-256 UUID algorithm based on stable source paths and identifiers.
- Repeating an import updates matching projects, documents, resources, styles, metadata, links, revisions, and provenance rather than duplicating them. Each attempt receives a separate `ImportRun`.
- Binder XML order is stored as `orderIndex`; use `Document.orderedChildren`.
- Every regular file under `Files` is represented by `ContentResource`, including RTF, notes, synopsis, style references, images, PDFs, checksums, indexes, writing history, version metadata, and binder archives.
- Original source bytes, relative paths, byte counts, media types, and SHA-256 hashes are preserved. Searchable source text and extracted RTF plain text are separate fields.
- Broken references and orphan resources are reported as structured warnings. Duplicate/invalid identities, malformed XML, unsafe paths, and validation failures throw explicit errors.

Run the focused suite with `swift test`.
