# Scrivener Project Import Compatibility

Scribe provides one-way import compatibility for user-selected Scrivener
projects. It reads the project’s `.scrivx` XML, content files, and metadata and
creates or updates records in Scribe’s own data store.

## Compatibility boundary

- Scribe does not modify the selected Scrivener project or its source files.
- Scribe does not export to Scrivener, synchronize with Scrivener, or provide
  round-trip editing.
- Imported data can be incomplete when a source feature is unsupported,
  malformed, or cannot be represented safely in Scribe.
- Scribe does not claim that the Scrivener project structure is an open format
  or that every Scrivener project or feature is compatible.

The importer is independently implemented to read user-accessible project data
and publicly available format information. It does not include Scrivener source
code, decompiled code, proprietary implementation material, or copied
documentation.

Scrivener is a trademark of Literature & Latte Ltd. Scribe is not affiliated
with, endorsed by, certified by, or sponsored by Literature & Latte Ltd.

## Test data and contributions

Do not contribute Scrivener projects, templates, sample prose, artwork, or
other material unless you created it or have clear permission to redistribute
it under the MIT License. Prefer small, original, synthetic fixtures for tests.

This document describes the project’s technical scope and is not legal advice.
Consult qualified counsel for advice on interoperability or distribution in a
specific jurisdiction.
