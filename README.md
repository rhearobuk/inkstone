# Inkstone

[![Swift tests](https://github.com/rhearobuk/inkstone/actions/workflows/swift-tests.yml/badge.svg)](https://github.com/rhearobuk/inkstone/actions/workflows/swift-tests.yml)

Inkstone is an open-source Apple authoring application for macOS, iPadOS, and
visionOS. It is licensed under the [MIT License](LICENSE) and is planned for a
future free release on the Apple App Store.

## Scrivener interoperability

Inkstone supports **one-way Scrivener project import compatibility**: it reads a
user-selected `.scriv` project and creates or updates data in Inkstone. It does
not modify the original Scrivener project, export to Scrivener, synchronize
with Scrivener, offer round-trip editing, or guarantee compatibility with every
Scrivener feature or project. Inkstone does not claim that the Scrivener project
structure is an open format.

Scrivener is a trademark of Literature & Latte Ltd. Inkstone is an independent
project and is not affiliated with, endorsed by, or sponsored by Literature &
Latte Ltd. See
[Scrivener Project Import Compatibility](Documentation/Scrivener-Interoperability.md)
for the complete interoperability boundary.

Inkstone is a universal Apple authoring application backed by the `AuthorData`
Core Data foundation. The package also includes `AuthorUI`, a reusable SwiftUI
authoring workspace for macOS 14, iPadOS 16, and visionOS 1 or newer, plus a
runnable macOS prototype.

## What is included

- A normalized, versioned Core Data schema with application-level UUID primary keys.
- Typed `NSManagedObject` classes and a typed CRUD repository for every entity.
- SQLite and in-memory persistent-store setup with automatic lightweight migration.
- A deterministic, idempotent Scrivener 3 importer for supported project data.
- Explicit import runs, validation, errors, warnings, source hashes, and provenance.
- Structured semantic entities, aliases, mentions, annotations, document links, revisions, and typed metadata values for agent-safe querying.
- A three-column SwiftUI workspace for project selection, a draggable binder, story-bible navigation, text editing, and project-wide body-text find and replace with match previews and escaped special characters.
- Per-format Book ISBN metadata. Authors add only the formats they publish—Hardback, Paperback, E-Book, Audiobook, Large Print, Board Book, or Library Binding—and record one ISBN for each. The edition remains separate metadata because it is not a product format.
- Three named book-cover assets for future publishing output: Front Cover, Back Cover, and Full Cover (front, spine, back, and overleaves).

## Run the UI prototype

Open `AuthorApp.xcodeproj` in Xcode, select the `Inkstone` scheme and a Mac,
iPad, or Apple Vision Pro destination, then press Run.

To import a project, click **Import Scrivener Project** in the Projects toolbar
and select a supported `.scriv` package, `.scrivx` project file, or legacy
exported XML-plus-`Files` folder. The importer preserves the available binder
hierarchy and selects the imported project when complete. Do not commit personal writing, third-party sample projects, or other private
project data to the repository. Any import fixture must be original, synthetic
content created for this repository.

The command-line equivalent for the macOS prototype is:

```sh
swift run InkstonePrototype
```

The first launch creates a native sample project with three stable workspace areas:

- **Project Definition** edits project identity and author properties on `WritingProject`.
- **Story Bible** groups `SemanticEntity` values into people, places, artifacts, events/conflicts/timelines, and worldbuilding without introducing a second persistence model.
- **Narrative** is a `Document` hierarchy containing scripts, folders, chapters, scenes, and imported Scrivener binder items. Binder drag and drop updates `parent` and `orderIndex`.

On iPadOS and visionOS, the binder uses a scrollable outline with chevrons to
expand folders and an ellipsis menu for each item's available actions. Drag onto
the upper or lower part of a row to place an item before or after it, or onto the
middle of a folder to move it inside. The Mac binder retains its native list and
context menus.

Story Bible entries and documents can be reordered together within a category
using drag and drop or **Move Up / Move Down** in the item menu. Clear binder
search and label/status filters before moving items. Explicit ordering is saved
with the project; dragging an entity does not change its semantic type.

Document editors, character dossiers, and Story Bible cards provide **Label**
and **Status** controls, including **None** and access to project definitions.
Assignments appear in binder badges and participate in binder filtering.
Deleting a definition clears its assignments without deleting any content.

All semantic Story Bible entries offer confirmed permanent deletion, including
organizations, places, artifacts, and worldbuilding entries. Related narrative
text and project gallery images are retained. Research and other document-backed
entries continue to use **Move to Trash** and **Restore**; character deletion
also removes its imported source entry, as described in its confirmation.

Folder and scene metadata text fields, including ISBNs, preserve spaces as you
type; multiline metadata also preserves line breaks. Number and date fields
continue to use typed values.

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

- The app accepts a `.scriv` package, its `.scrivx` project file, or the legacy exported XML-plus-`Files` folder layout. Imports can create a native app project or target an existing one.
- Records imported into an existing project are namespaced by the Scrivener project UUID. Re-importing the same source updates its records, while separate Scrivener projects cannot overwrite one another.
- When an imported Story Bible identity has the same name as an existing identity, the imported copy is retained and renamed with its Scrivener project name rather than silently merged.
- A standalone legacy import retains Scrivener project and binder UUIDs directly. Imports into native target projects preserve those UUIDs as source identifiers and derive collision-safe app UUIDs.
- Derived IDs use a namespaced SHA-256 UUID algorithm based on stable source paths and identifiers.
- Repeating an import updates matching projects, documents, resources, styles, metadata, links, revisions, and provenance rather than duplicating them. Each attempt receives a separate `ImportRun`.
- Binder XML order is stored as `orderIndex`; use `Document.orderedChildren`.
- Every regular file under `Files` is represented by `ContentResource`, including RTF, notes, synopsis, style references, images, PDFs, checksums, indexes, writing history, version metadata, and binder archives.
- Standalone images, card images, and images embedded in imported RTF are exposed as project-owned `GalleryItem` records. Gallery items retain their source document link; extracted embedded images are stored as deterministic derived resources.
- Photos can also be added natively to a project, document, character, place, or other Story Bible entry. These records use app-owned UUIDs and resources, require no Scrivener identifiers, and can be deleted independently.
- Original source bytes, relative paths, byte counts, media types, and SHA-256 hashes are preserved. Searchable source text and extracted RTF plain text are separate fields.
- Broken references and orphan resources are reported as structured warnings. Duplicate/invalid identities, malformed XML, unsafe paths, and validation failures throw explicit errors.

Run the data and UI behavior suites with `swift test`.

CloudKit manuscript sharing is intentionally not exposed. The current connected
Core Data model fails the confidentiality preflight required by issue #10; see
[Core Data sharing feasibility](Documentation/Core-Data-Sharing-Feasibility.md)
for the executable evidence and no-go decision.

## Community and support

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance,
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community standards, and
[SECURITY.md](SECURITY.md) for private vulnerability reporting. Use GitHub
Issues for bugs and feature requests, and GitHub Discussions for questions and
support.

See [Privacy Policy](Documentation/Privacy-Policy.md) for how Inkstone handles
project data, iCloud synchronization, and optional AI-assisted features.


## AI Editor

Open **AI Editor** in the workspace toolbar. Choose a persona, review scope and explicit manuscript target. On Mac, the editor stays beside the manuscript. The reply appears as a message, with review controls at the bottom; Change opens review options, and the clock button opens history. Narrow mobile layouts use a sheet. Scene/document review examines one document; chapter and novel reviews traverse the chosen root and descendants in binder order. Compile-excluded text can be included explicitly. An optional short Story Bible summary supplies reference context.

Apple Intelligence is the default provider when no other provider preference exists. On-device inference requires a supported Apple Intelligence device and macOS/iOS/visionOS 26 or later, with the model enabled and ready. Older platforms retain the rest of the app and show availability guidance. OpenAI is an explicit alternative using a user-supplied Keychain credential; its Responses/structured-output models can be selected in the panel. Other provider settings remain available, but their editorial adapters are not implemented. No automatic cloud fallback occurs.

Results are critique and recommendations, with evidence and user-controlled addressed/dismissed status and notes. They do not rewrite or apply changes to the manuscript. History stores snapshots and warns when the current text differs. Model feedback can be mistaken. Mature fiction is submitted as literary material; providers may still refuse it, in which case refusals and incomplete coverage remain visible.

Automatic scene-to-Story-Bible recognition is currently disabled behind
`WorkspaceController`'s default-off `sceneEntityRecognitionEnabled` switch while
the logic is refined. Autosave, pending-change flushes, and explicit scene-link
refreshes do not run recognition or remove existing links. There is no regex
fallback. Relationship Explorer remains independent: it displays existing Story Bible
entities and saved relationships, and supports manual relationship editing.
Existing scene links remain visible, but are not refreshed.

Relationship Explorer uses **Start with → Focus on → Show connections to**: choose
a Story Bible category, a specific entry, and one or more destination categories.
The focused entry is a compact node connected to surrounding nodes, arranged by
category. Each relationship is drawn as a line with its label on the line and an
arrowhead at the saved target. Only direct saved relationships are shown,
including incoming connections. Click a line label to inspect, edit, or delete
the relationship, or click a surrounding node to refocus. Drag to pan and use
the small zoom/Fit controls to navigate; empty categories do not occupy diagram
space. Use
**Add Relationship** and its **Story Bible category** picker to link the focus to any
category, including Places, independently of the display filters. A newly linked
category is revealed on the board automatically. Choosing a new focus initially
shows its connected categories. Category buttons show unfiltered connection
counts; the diagram shows visible versus total connections with a **Show all**
action when filters hide links. Category and focus selections are saved per board.
Story Bible cards also provide a category-based relationship composer; character
dossiers distinguish character-only relationships from general Story Bible links.
The shared composer requires a category first, then an entry from that category.
Changing the category clears the previous entry; no mixed list is presented.
Existing explicit owner, related-character, and organization-member selections
on older cards are backfilled into shared relationship records on opening the
workspace. Editing or deleting these records updates the corresponding card
selections, so removed links are not recreated on the next launch.
Old boards retain their saved focus where possible; their old book, depth,
visibility, and layout settings do not restrict the focused explorer.
The feature was previously named Murder Board; its storage identifiers remain
compatible, so existing saved views continue to open.

Imported text entries under Places, Locations, or Settings are presented as
structured Place cards. Their original body text is copied verbatim into the
editable Description field. The card provides relationships to other Story Bible
entries and appears as a target in the shared relationship composer. Original
source documents and resources remain intact; subsequent imports do not
overwrite edits to the card's name or description.

When explicitly enabled in code, recognition uses only on-device Apple
Intelligence, independently of AI Editor's model selection.
Recognition runs sequentially by entity category, with
up to 24 candidates per request; each request includes the full scene text.
If Apple blocks a request, the banner distinguishes a safety-guardrail block from
a model refusal, identifies the scene and category pass, and includes Apple's
diagnostic when supplied. Apple may not identify the specific trigger.
The scene's existing links remain unchanged. Scene edits are saved
before automatic linking runs. No alternative model or cloud fallback is used.
This recognition does not infer new relationships between Story Bible entities.

The V5 Core Data model migrates existing stores. Review snapshots remain local and consume storage until the review/project is deleted. OpenAI requests use `store: false`; this is not a promise of zero provider retention. Reported token usage is shown when available, and API calls may incur charges.

For a safe manual preview, run a debug build with `--editor-preview`. This opens a synthetic in-memory project instead of the saved project database. Standard validation: `swift test`. Optional runtime tests: `AUTHOR_APPLE_SMOKE=1 swift test --filter EditorialReviewTests/testAppleRuntimeSmokeWhenExplicitlyEnabled`; optional mature-theme checks use `AUTHOR_APPLE_MATURE_SMOKE=1`. These use synthetic material only and require an available local model. The UI rendering check uses `AUTHOR_RENDER_EDITOR=1 swift test --filter EditorPanelRenderTests`.
