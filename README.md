# AuthorData

`AuthorData` is a Core Data foundation for a Universal Apple writing application. The package also includes `AuthorUI`, a reusable SwiftUI authoring workspace for macOS 13, iPadOS 16, and visionOS 1 or newer, plus a runnable macOS prototype.

## What is included

- A normalized, versioned Core Data schema with application-level UUID primary keys.
- Typed `NSManagedObject` classes and a typed CRUD repository for every entity.
- SQLite and in-memory persistent-store setup with automatic lightweight migration.
- A deterministic, idempotent Scrivener 3 importer for the supplied project XML and `Files` tree.
- Explicit import runs, validation, errors, warnings, source hashes, and provenance.
- Structured semantic entities, aliases, mentions, annotations, document links, revisions, and typed metadata values for agent-safe querying.
- A three-column SwiftUI workspace for project selection, a draggable binder, story-bible navigation, and text editing.

## Run the UI prototype

Open `AuthorApp.xcodeproj` in Xcode, select the `AuthorApp` scheme and a Mac,
iPad, or Apple Vision Pro destination, then press Run.

To load the supplied test project, click **Import Scrivener Project** in the
Projects toolbar and select the repository folder (`Author Tool`). The importer
finds the single project XML and its sibling `Files` folder, preserves the full
binder hierarchy, and selects the imported project when complete.

The command-line equivalent for the macOS prototype is:

```sh
swift run AuthorAppPrototype
```

The first launch creates a native sample project with three stable workspace areas:

- **Project Definition** edits project identity and author properties on `WritingProject`.
- **Story Bible** groups `SemanticEntity` values into people, places, artifacts, events/conflicts/timelines, and worldbuilding without introducing a second persistence model.
- **Narrative** is a `Document` hierarchy containing scripts, folders, chapters, scenes, and imported Scrivener binder items. Binder drag and drop updates `parent` and `orderIndex`.

Imported Scrivener character cards are normalized into native character dossiers.
The importer maps names, aliases, age/location, physical description, biography,
measurements, notes, relationships, and conflicts when it can do so safely.
Relationships and conflict participants point to actual character records;
unstructured material and the original rich-text card remain available without
creating unresolved references.

`AuthorUI` is platform-neutral SwiftUI. To ship on iPadOS and visionOS, add `AuthorUI` and `AuthorData` as package product dependencies to the corresponding app targets in an Xcode multiplatform app and use the same root view:

```swift
let store = try AuthorDataStore(storeURL: applicationSupportURL)
let workspace = WorkspaceController(store: store)

AuthorWorkspaceView(controller: workspace)
```

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
- Standalone images, card images, and images embedded in imported RTF are exposed as project-owned `GalleryItem` records. Gallery items retain their source document link; extracted embedded images are stored as deterministic derived resources.
- Photos can also be added natively to a project, document, character, place, or other Story Bible entry. These records use app-owned UUIDs and resources, require no Scrivener identifiers, and can be deleted independently.
- Original source bytes, relative paths, byte counts, media types, and SHA-256 hashes are preserved. Searchable source text and extracted RTF plain text are separate fields.
- Broken references and orphan resources are reported as structured warnings. Duplicate/invalid identities, malformed XML, unsafe paths, and validation failures throw explicit errors.

Run the data and UI behavior suites with `swift test`.
