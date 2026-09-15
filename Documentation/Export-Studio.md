# Export Studio

Export Studio opens from the Navigator when a Book, Section, Chapter, or Scene is selected. The
scope chooser only lists objects of that selected type, and an export always includes the selected
root and its narrative descendants in binder order.

Formats are **Manuscript**, **Ebook**, and **PDF**. Export Studio automatically limits templates
to combinations that support the chosen format. Paper size is available only for paginated
Manuscript and PDF templates.

The publication summary and readiness state come from the compiled and resolved publication.
Items marked **Do Not Publish** are excluded by default from counts and preview; the optional
toggle includes them. Preview uses the same `ResolvedPublication` that future file renderers will
receive. Paginated preview communicates semantic page layout rather than exact Word pagination,
and ebook preview is reflowable because final EPUB appearance varies by reader and device.
