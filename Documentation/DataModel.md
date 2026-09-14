# Data model

## Ownership and document hierarchy

`WritingProject` is the aggregate root. `Document` models every ordered Scrivener binder item, not only prose: draft folders, folders, text, images, PDFs, and unknown future kinds remain distinguishable through `kind`. The self-referential parent/children relationship stores hierarchy; `orderIndex` stores sibling order independently of unordered Core Data relationship storage.

`ContentResource` stores a typed source asset and its provenance attributes. Large binary values permit Core Data external storage. Keeping `data`, `textContent`, and `Document.plainText` separate preserves exact source bytes while providing queryable text.

Scrivener is an import adapter, not the application domain model. Imported source
identities and hierarchy are retained for provenance and repeatable migration,
while the application projects documents into its own Project, Story Bible, and
Narrative workspace. The source RTF remains in `ContentResource.data`; decoded
search text belongs in `ContentResource.textContent` and `Document.plainText`.
Rich editors must decode the resource data rather than display RTF source.

`DocumentLink` normalizes bookmarks and inline `scrivlnk://` references. A missing target remains explicit in `unresolvedTargetIdentifier`.

## Semantics for people and agents

`SemanticEntity.kind` uses the practical ontology `character`, `location`, `organization`, `object`, `event`, `concept`, `theme`, `relationship`, `timeline`, or `other`. `EntityAlias` supports name resolution, and `DocumentEntityMention` records a queryable range, surface text, context, source, and confidence.

`CharacterProfile` is the native character dossier, independently of any
Scrivener layout. A project cascade-owns its profiles. Every profile has a
Swift-required project and character `SemanticEntity`; its aliases remain the
semantic entity's multiple `EntityAlias` records. An optional `sourceDocument`
preserves where imported dossier material came from without making the source
document the owner.

Profiles cascade-own user-defined `CharacterMeasurement` values, multiple
`CharacterNote` records, and their `CharacterConflict` records. A conflict may
reference zero or more other profiles through `relatedCharacters`; those
participant references are nullified when a participant is deleted, while
deleting the owning profile deletes the conflict. Character relationships are
objects whose source and target are both profiles. Both profile inverses use
cascade deletion so deleting either endpoint deletes the relationship object
instead of leaving a relationship with an invalid endpoint.

`Annotation` has a controlled kind (`note`, `comment`, `highlight`, `todo`, `question`, `warning`, or `modelSuggestion`), lifecycle status, author/source, and optional document range. `Revision` records immutable text snapshots with sequence and content hash.

Generated interpretations should be stored as typed semantic entities, mentions, annotations, metadata values, or revisions with `source = "model"` and a `ProvenanceEvent`. They must not be embedded in opaque binary payloads. `ProvenanceEvent` records agent, version, timestamp, source URI/identifier, content hash, and concise human-readable details.

## Extensible metadata

`MetadataField` defines a project-scoped key, display name, scalar value type, and semantic purpose. `MetadataValue` has separate string, integer, double, boolean, and date columns so values remain filterable. Unknown Scrivener metadata is retained under stable `scrivener.*` keys with its source XML path; custom fields become keys such as `scrivener.MetaData.Custom.sexualcontent`.

## Identity and migration

Every entity has a UUID `id` uniqueness constraint. Source-owned UUIDs remain unchanged. Derived IDs are deterministic within the project namespace, making imports repeatable. Source identifier/path compound constraints provide additional conflict protection.

The persistent container enables automatic model migration and inferred mappings. `AuthorDataV1` preserves the original schema, and additive `AuthorDataV2` is current; the compiled `AuthorData.momd` contains both versions so existing SQLite stores migrate through an inferred lightweight mapping. Future schema changes should add a new version under `AuthorData.xcdatamodeld`, select it in `.xccurrentversion`, regenerate `AuthorData.momd`, and add a migration test opening a store created from the previous model. Use explicit mapping models when a change cannot be inferred without data loss.

Core Data requires inverse destinations of uniqueness-constrained entities to be optional in the model. The Swift API and importer treat aggregate relationships as required and validate them before saving imported data.
