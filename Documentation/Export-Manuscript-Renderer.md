# Manuscript renderer

`ManuscriptRenderer` consumes only `ResolvedPublication`, producing an interoperable DOCX package without accessing Core Data, document hierarchy, or template resources. The compiler and template resolver remain the sole sources of content, exclusions, metadata, and publishing intent.

The renderer writes a focused Office Open XML package using a deterministic stored-ZIP implementation rather than adding a dependency. It includes content types, package and document relationships, document properties, document XML, reusable paragraph styles, and header/footer parts. Its built-in validator checks ZIP entries, required parts, XML well-formedness, relationships, and referenced paragraph styles.

Template semantic styles become named Word paragraph styles. The Standard Manuscript template supplies Times New Roman, alignment, indentation, double spacing, margins, A4/US Letter selection, headings, scene-break marker, title page, and header/footer values. Bold and italic prose spans become Word run formatting; unsupported late-bound fields and invalid styles fail with typed renderer errors.

Suggested names use the title plus ` - Manuscript.docx`, add a selected chapter/section/scene qualifier for a partial scope, and replace invalid filename characters. Existing destinations are rejected rather than overwritten.

Known limitations: the first version supports the resolved text, bold, italic, page-number/total-page fields, and standard header/footer components. It intentionally does not emit cover artwork, ISBNs, arbitrary rich-text features, comments, images, print-production marks, EPUB, or PDF.

## Manual validation

1. Export a full novel.
2. Open it in Microsoft Word.
3. Open it in Apple Pages.
4. Verify the title page.
5. Verify headers and page numbers.
6. Verify chapter page breaks.
7. Verify italics and bold.
8. Verify A4 and US Letter variants.
9. Save and reopen from Word to confirm interoperability.
