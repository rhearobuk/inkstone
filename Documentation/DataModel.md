# Data model

## Ownership and document hierarchy

`WritingProject` is the aggregate root. `Document` models every ordered Scrivener binder item, not only prose: draft folders, folders, text, images, PDFs, and unknown future kinds remain distinguishable through `kind`. The self-referential parent/children relationship stores hierarchy; `orderIndex` stores sibling order independently of unordered Core Data relationship storage.

`ContentResource` stores a typed source asset and its provenance attributes. Large binary values permit Core Data external storage. Keeping `data`, `textContent`, and `Document.plainText` separate preserves exact source bytes while providing queryable text.

`DocumentLink` normalizes bookmarks and inline `scrivlnk://` references. A missing target remains explicit in `unresolvedTargetIdentifier`.

## Semantics for people and agents

`SemanticEntity.kind` uses the practical ontology `character`, `location`, `organization`, `object`, `event`, `concept`, `theme`, `relationship`, `timeline`, or `other`. `EntityAlias` supports name resolution, and `DocumentEntityMention` records a queryable range, surface text, context, source, and confidence.

`Annotation` has a controlled kind (`note`, `comment`, `highlight`, `todo`, `question`, `warning`, or `modelSuggestion`), lifecycle status, author/source, and optional document range. `Revision` records immutable text snapshots with sequence and content hash.

Generated interpretations should be stored as typed semantic entities, mentions, annotations, metadata values, or revisions with `source = "model"` and a `ProvenanceEvent`. They must not be embedded in opaque binary payloads. `ProvenanceEvent` records agent, version, timestamp, source URI/identifier, content hash, and concise human-readable details.

## Extensible metadata

`MetadataField` defines a project-scoped key, display name, scalar value type, and semantic purpose. `MetadataValue` has separate string, integer, double, boolean, and date columns so values remain filterable. Unknown Scrivener metadata is retained under stable `scrivener.*` keys with its source XML path; custom fields become keys such as `scrivener.MetaData.Custom.sexualcontent`.

## Identity and migration

Every entity has a UUID `id` uniqueness constraint. Source-owned UUIDs remain unchanged. Derived IDs are deterministic within the project namespace, making imports repeatable. Source identifier/path compound constraints provide additional conflict protection.

The persistent container enables automatic model migration and inferred mappings. Future schema changes should add a new version under `AuthorData.xcdatamodeld`, select it in `.xccurrentversion`, regenerate `AuthorData.momd`, and add a migration test opening a store created from the previous model. Use explicit mapping models when a change cannot be inferred without data loss.

Core Data requires inverse destinations of uniqueness-constrained entities to be optional in the model. The Swift API and importer treat aggregate relationships as required and validate them before saving imported data.
