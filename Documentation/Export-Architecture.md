# Export architecture

`ExportCompiler` belongs to `AuthorData`. It reads a selected narrative root from the existing
ordered binder hierarchy, applies publishing exclusions, and projects Core Data into an immutable,
`Sendable` `ExportPublication`. The publication contains typed project, book, and structural
metadata; ordered book/section/chapter/scene documents; source UUIDs; word counts; diagnostics;
and conservative prose blocks with bold/italic text spans.

The compiler is the only export layer that reads Core Data or RTF. It uses the same preferred
`content` RTF resource as the editor, turns supported RTF into portable spans, and records a
diagnostic when it must safely fall back to `Document.plainText`. A malformed resource without a
plain-text fallback is a typed compiler error. Renderers must consume the snapshot and must never
query managed objects.

Export scope is the selected book, section, chapter, or scene plus its narrative descendants in
`orderedChildren` binder order. Documents marked Do Not Publish, including descendants of an
excluded ancestor, are omitted by default. A proof/debug request can explicitly include them.
Metadata is projected from `WritingProject` and the existing `NarrativeMetadataSchema` /
`MetadataField` / `MetadataValue` records; no export metadata is persisted separately.

`ExportTemplateResolver` consumes this snapshot and a versioned bundled `ExportTemplate` to
produce an immutable `ResolvedPublication`. Future manuscript/DOCX, EPUB, and PDF renderers will
consume that representation. Format-specific pagination, EPUB markup, DOCX packaging, and PDF
generation do not belong in either compiler or template.

`ExportStudioView` receives a Navigator-selected narrative object through `WorkspaceController`.
It limits its chooser to roots of that same type (Book, Section, Chapter, or Scene), then passes
the chosen ID and the "Include content marked Do Not Publish" setting to `ExportCompiler`.
`PublicationPreviewView` consumes the resulting `ResolvedPublication`, preserving the single
pipeline: `ExportCompiler` -> export snapshot -> `ExportTemplateResolver` ->
`ResolvedPublication` -> publication preview -> `ExportStudioView`. Future manuscript, ebook,
and PDF renderers will consume that same resolved publication.
