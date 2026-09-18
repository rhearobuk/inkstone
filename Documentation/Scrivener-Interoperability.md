# Scrivener Project Import Compatibility

Inkstone provides one-way import compatibility for user-selected Scrivener
projects. It reads the project’s `.scrivx` XML, content files, and metadata and
creates or updates records in Inkstone’s own data store.

## Import implementation and source structure

The importer is independently implemented for interoperability. It reads project
files selected by the user and maps their contents into Inkstone's own data model.
It does not incorporate Scrivener application code, modify Scrivener, or require
Scrivener to be installed.

Supported projects have a user-visible structure:

```text
.scriv package -> .scrivx project XML -> Files/ content and resources
```

Inkstone reads the binder and project metadata from the XML, then maps referenced
RTF, images, and other resources beneath `Files`. For provenance and reliable
re-imports, it can retain original source bytes and metadata for files imported
from the user's selected project.

Imported text entries classified under Places, Locations, or Settings become
structured Story Bible Place cards in the workspace. Folder organization is
retained. The initial Description field copies the imported body text verbatim;
the source document, synopsis, and resources remain preserved separately.
The native document metadata key `system.storyBible.importedPlaceEntityID`
records the card's semantic entity identity. This mapping makes conversion
idempotent without merging similarly named places or requiring a schema change.
Re-imports update the source document without overwriting the editable card.
Place cards support the same category-then-entry relationship composer as other
Story Bible entries and participate in Relationship Explorer.

## Compatibility boundary

- Inkstone does not modify the selected Scrivener project or its source files.
- Inkstone does not export to Scrivener, synchronize with Scrivener, or provide
  round-trip editing.
- Imported data can be incomplete when a source feature is unsupported,
  malformed, or cannot be represented safely in Inkstone.
- Inkstone does not claim that the Scrivener project structure is an open format
  or that every Scrivener project or feature is compatible.

The importer is based on user-accessible project data and publicly available
format information. It does not include Scrivener source code, decompiled code,
proprietary implementation material, or copied documentation.

Scrivener is a trademark of Literature & Latte Ltd. Inkstone is an independent
project and is not affiliated with, endorsed by, or sponsored by Literature &
Latte Ltd.

## Test data and contributions

Do not contribute Scrivener projects, templates, sample prose, artwork, or
other material unless you created it or have clear permission to redistribute
it under the MIT License. Prefer small, original, synthetic fixtures for tests.
If an import fixture is added, store it at
`Tests/Fixtures/MinimalScrivenerProject.scriv` and ensure every file inside the
package, including resources and archived material, is original to this project.

This document describes the project’s technical scope and is not legal advice.
Consult qualified counsel for advice on interoperability or distribution in a
specific jurisdiction.
