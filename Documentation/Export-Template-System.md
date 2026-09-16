# Export template system

The export pipeline is:

`Core Data -> ExportCompiler -> immutable ExportPublication -> ExportTemplateResolver -> ResolvedPublication -> future renderer`

`ExportCompiler` is the only export subsystem that accesses Core Data, RTF, or book-cover
resources. Its immutable snapshot now includes the containing Book for every export scope and
portable front/back/full cover-asset records. `ExportTemplate` and `ResolvedPublication` contain
no managed objects or renderer markup.

## Built-in templates

| ID | Version | Purpose | Future formats |
| --- | --- | --- | --- |
| `com.unit37.scribe.template.manuscript.standard` | 1 | Manuscript submission | DOCX, PDF |
| `com.rhearobuk.scribe.template.ebook.novel` | 1 | Reflowable novel ebook | EPUB |
| `com.rhearobuk.scribe.template.proof.reading` | 1 | Human reading proof | PDF |

Built-ins are bundled JSON resources, loaded as immutable values and validated before use. An ID
and version are a permanent meaning: a later convention must use a new version rather than
silently changing an existing version. Templates define bounded semantic styles, front/back
matter components, header/footer concepts, and rules for Book, Section, Chapter, and Scene.
They never specify HTML, CSS, XML, PDF commands, or packaging.

The `scribe` namespace in existing template IDs is retained after the Inkstone rebrand because
template IDs are persistent compatibility identifiers.

Manuscript Submission uses 1-inch margins, double-spaced 12-point Times New Roman manuscript body text, title/
byline/approximate-word-count front matter, chapter page breaks, a `#` scene break, and a running
author/title/page header. It requires title and byline; subtitle, language, and word count are
recommended. It has no cover, ISBN, copyright, or generated back matter.

Novel Ebook targets a future reflowable EPUB 3.3 renderer with title/author/language required.
ISBN, front cover, copyright, publisher, publication date, series, volume, and edition are
recommended. Its semantic front matter conditionally includes cover, title/subtitle/byline, series,
and publication information; titled sections and chapters are navigation entries; scenes use
`* * *`; and it specifies neither pages nor running headers.

Reading Proof accepts `usLetter` or `a4`, uses comfortable 0.8/0.85-inch reading margins and
proportional typography, generated title/subtitle/byline front matter, optional copyright, chapter
page openers, `* * *` scene breaks, a restrained book-title header, and a late-bound page-number
footer. It requires only title and recommends byline, subtitle, language, and copyright.

Page size changes layout policy only; it never changes authored prose or language conventions.
Future export presets may store a template/version, format, and such parameters separately from
templates.

## Validation and readiness

`ExportTemplateValidator` rejects invalid versions, duplicate ID/version pairs, empty format
support, unknown tags, tags in invalid contexts, missing styles/rules, invalid narrative rules,
and missing front matter. `ExportTemplateResolver` then distinguishes an invalid template, a
blocked export missing required metadata, and a ready export with recommended-data warnings.

The resolver produces typed component values and renderer late-bound tokens. Future renderers
consume `ResolvedPublication`, apply semantic styles and structural rules repeatedly to the
narrative, then perform pagination or format serialization. They do not parse JSON or query
Core Data.

Manuscript approximate word count rounds to the nearest 1,000 words for totals of 1,000 or more;
smaller totals remain exact. Counts are summed from the compiled snapshot, so standard exports
already exclude Do Not Publish material.
