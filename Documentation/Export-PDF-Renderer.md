# PDF Renderer

`PDFRenderer` consumes only a `ResolvedPublication` plus `PDFExportOptions`; it never reads Core Data or a live document tree. `ExportTemplateResolver` remains the authority for content inclusion, template structure, metadata, semantic styles, page rules, and late-bound header/footer tags.

## Architecture

The renderer uses Core Text to turn semantic heading, scene-break, and prose blocks into deterministic page frames, then Core Graphics to write those frames to a native PDF. It uses the page layout retained on `ResolvedPublication`, supports A4 and US Letter, and resolves page-number tags after final pagination. Title pages suppress running furniture. Chapter and section page breaks come from the resolved narrative rules; headings move to a fresh page rather than orphan at the foot of an existing page where possible.

The Export Studio builds the same resolved publication that its textual preview displays and sends it to the renderer through the standard macOS save panel. The preview does not yet use the Core Text pagination model, so it represents the same semantic content and structural rules but is not page-for-page with generated output.

## Templates and text

Standard Manuscript Submission uses its resolved Times-family, double-spaced, first-line-indented manuscript semantics and suppresses cover imagery. Reading Proof uses its proportional reading style, distinct title treatment, justified body text, and restrained footer numbering. Preferred fonts use the native font resolver; unavailable fonts fall back to the platform serif font and add a non-blocking diagnostic.

Bold and italic spans are mapped to Core Text traits. Unicode is passed directly through attributed strings. The V1 renderer does not render assets because neither built-in PDF template includes an image component; it reports no failure for unused assets. It does not provide trim, bleed, crop marks, PDF/X, commercial-print preparation, or full widow/orphan control.

## Metadata and files

Core Graphics writes title, author, subject, creator (`Scribe`), and creation date metadata. Suggested names are deterministic, safely sanitized, and use `Title - Manuscript.pdf` or `Title - Reading Proof.pdf`; a one-item non-book scope includes its item title.

## Manual validation

1. Export both templates in A4 and US Letter, then open each in Preview.app and Acrobat if available.
2. Compare manuscript double-spacing and running header with the distinct Reading Proof title/body/footer treatment.
3. Verify chapter starts, scene separators, page numbers, title-page suppression, bold/italic text, Unicode, and long-paragraph page continuation.
