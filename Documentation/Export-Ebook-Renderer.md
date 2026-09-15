# Ebook renderer

Scribe's Ebook export produces a reflowable **EPUB 3.3** file from
`ResolvedPublication`. `EbookRenderer` never accesses Core Data, live documents, or template
resources: the compiler and template resolver remain the sole owners of metadata, publication
exclusions, rich-text conversion, and navigation rules.

## Package and metadata

The archive starts with an uncompressed `mimetype` entry containing `application/epub+zip`, then
contains `META-INF/container.xml`, `EPUB/package.opf`, a navigation document, XHTML resources,
and `EPUB/styles/book.css`. The package maps resolved title, author, language, EPUB ISBN,
publisher, publication date, copyright, edition, and series metadata to EPUB/DC metadata.

When an EPUB ISBN is available it is emitted as `urn:isbn:<value>`. Otherwise the renderer creates
a deterministic UUID-based `urn:uuid:` identifier from the template identity and ordered resolved
narrative IDs. It never creates a synthetic ISBN.

## Content, covers, and navigation

The resolved front cover is included as the EPUB cover image when image bytes are available; a
cover page presents it with descriptive alternative text. Missing covers do not block an export
when template readiness permits it. Title and publication-information pages are separate XHTML
resources. Sections and chapters are split into individual XHTML resources; scenes remain in
their parent reading resource and use the template scene-break marker.

The navigation document is generated only from resolved items whose navigation rule is enabled
and which have a title. This includes configured chapters and major sections, while excluding
scenes by default. Spine order is the resolved publication order.

## Semantics, accessibility, and styling

XHTML declares the resolved language and uses logical headings, navigation landmarks, semantic
`em`/`strong` spans, and an accessible scene-break separator. The restrained stylesheet provides
body, title, author, heading, front-matter, epigraph, and scene-break presentation without page
sizes, page numbers, fixed headers/footers, absolute positioning, or embedded fonts. Readers
remain in control of font choice and text size.

## Validation and limitations

`EbookRenderer.validate` checks ZIP ordering and mimetype storage, required files, XML
well-formedness, manifest resources, spine references, and navigation targets. Renderer tests
exercise package structure, metadata, cover handling, chapter splitting, navigation, semantic
formatting, Unicode, scene breaks, missing-cover behavior, filenames, and fallback identifiers.
EPUBCheck is intentionally not bundled with the application; run the current project/CI
EPUBCheck integration when it is installed.

Known limitations: V1 supports the resolved front cover and prose rich text (bold and italic);
it does not yet lay out arbitrary illustrated-book content, embed fonts, produce fixed-layout
EPUBs, provide DRM, or publish to storefronts.

## Manual validation checklist

1. Export a complete novel.
2. Validate using EPUBCheck.
3. Open in Apple Books.
4. Open in another EPUB reader if available.
5. Verify cover.
6. Verify navigation/TOC.
7. Verify chapter order.
8. Verify scene breaks.
9. Change reader font/text size and confirm reflow.
10. Verify italics/bold and Unicode punctuation.
