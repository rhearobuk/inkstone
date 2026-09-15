# Export template tags

Tags are validated by `ExportTemplateTagRegistry`; templates use structured components and
presence-only `condition.requiresTag`, never string replacement or scripting. A missing optional
tag omits the conditional component. An unknown tag is a template error.

| Category | Tags | Typed value |
| --- | --- | --- |
| Book | `book.title`, `book.subtitle`, `book.author`, `book.publisher`, `book.language`, `book.edition`, `book.copyright`, `book.publicationDate`, `book.series.name`, `book.series.volume` | Text, date, or integer |
| ISBN | `book.isbn.unspecified`, `book.isbn.hardback`, `book.isbn.paperback`, `book.isbn.ebook`, `book.isbn.audiobook`, `book.isbn.largePrint`, `book.isbn.boardBook`, `book.isbn.libraryBinding`, `publication.isbn` | Text |
| Artwork | `book.cover.front`, `book.cover.back`, `book.cover.full`, `publication.cover` | `ExportCoverAsset` |
| Statistics | `manuscript.wordCount`, `manuscript.wordCount.approximate`, `section.wordCount`, `chapter.wordCount`, `scene.wordCount`, `section.number`, `chapter.number` | Integer |
| Context | `section.title`, `section.subtitle`, `chapter.title`, `chapter.subtitle`, `scene.title` | Text |
| Export | `export.date`, `export.year` | Date |
| Renderer | `page.number`, `page.total` | Late-bound token |

`publication.isbn` maps EPUB output to the E-Book ISBN and DOCX/PDF publication output to the
Paperback ISBN. `publication.cover` maps ebook output to the front cover. Asset values keep their
resource identity, media type, checksum, and data; they are not encoded into template text.

`page.number` and `page.total` are legal only in header/footer components. They remain unresolved
until a future paginating renderer provides them. Contextual section/chapter/scene tags are
reserved for components applied while rendering their matching narrative item.

Formatters are a fixed enum: `number`, `approximateWordCount`, `year`, `shortDate`, and
`longDate`. Case presentation is a semantic style property, not a mutation of metadata.
