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

## Project preferences (section types, labels, statuses, custom metadata)

`LabelDefinition`, `StatusDefinition`, and `SectionTypeDefinition` are project-scoped vocabularies parsed from the Scrivener project XML's `<LabelSettings>`, `<StatusSettings>`, and `<SectionTypes><TypeDefinitions>` blocks (siblings of `<Binder>`). Each stores the source ID (Scrivener's numeric label/status ID or section type GUID), a display `title`, `orderIndex` for stable ordering, and — for labels — an optional RGB color parsed from Scrivener's `"R G B"` color string. `LabelDefinition.isDefault`/`StatusDefinition.isDefault` reflect Scrivener's `DefaultLabelID`/`DefaultStatusID`. `Document.labelIdentifier`, `statusIdentifier`, and `sectionTypeIdentifier` reference these definitions' `sourceIdentifier` values.

`CustomMetaDataSettings/MetaDataField` entries populate `MetadataField` rows keyed as `scrivener.MetaData.Custom.<fieldID>` (matching the keys `upsertMetadata` derives per document), with `MetadataField.sourceIdentifier` set to the Scrivener field ID and `displayName`/`valueType` taken from the settings block rather than inferred from the key. Import order matters: per-document metadata is imported first (creating placeholder fields if needed), then `importProjectSettings` runs so the authoritative titles/types from the settings block win.

These four definitions back `ProjectPreferencesView` (`AuthorUI`), a project-level preferences pane (opened via the binder toolbar's gear icon) for viewing and editing Section Types, Labels, Statuses, and Custom Metadata fields, including adding/renaming/deleting entries and recoloring labels. User-created entries use a synthesized `native.<uuid>` (or `custom.<uuid>` key) source identifier since they have no Scrivener origin.

## Identity and migration

Every entity has a UUID `id` uniqueness constraint. Source-owned UUIDs remain unchanged. Derived IDs are deterministic within the project namespace, making imports repeatable. Source identifier/path compound constraints provide additional conflict protection.

The persistent container enables automatic model migration and inferred mappings. `AuthorDataV1` preserves the original schema, and additive `AuthorDataV5` is current; the compiled `AuthorData.momd` contains V1–V5 versions so existing SQLite stores migrate through an inferred lightweight mapping. Future schema changes should add a new version under `AuthorData.xcdatamodeld`, select it in `.xccurrentversion`, regenerate `AuthorData.momd`, and add a migration test opening a store created from the previous model. Use explicit mapping models when a change cannot be inferred without data loss.

Core Data requires inverse destinations of uniqueness-constrained entities to be optional in the model. The Swift API and importer treat aggregate relationships as required and validate them before saving imported data.


## AI Editor reviews (V5)

`EditorialReview` is project-owned and cascade-owns inputs, findings, and processing chunks. Inputs preserve exact submitted text, hashes, source UUID/title/path/order, and manuscript/context role. Findings contain typed category, severity, explanation, recommendation and independent human tracking fields. Multiple `EditorialFindingAnchor` records point into immutable input snapshots using verified UTF-16 ranges. Invalid or ambiguous quotations fall back to document-level references.

Deleting a target document or persona nullifies the live reference without erasing review snapshots. Deleting a project or review cascades through its review records. Persona presets are idempotently seeded; customized personas and each run's effective rubric are independent. History keeps selected provider/model, prompt/schema versions, timestamps, parameters, OS/app version, reported token usage when available, and rerun links. `ProvenanceEvent` records terminal review outcomes.

States distinguish completed, partial, failed, refused, cancelled and interrupted runs. Startup marks abandoned active runs interrupted without resending text. Chunk records preserve coverage and intermediate summaries; synthesis is hierarchical and no manuscript input is silently truncated. This is an editorial subsystem: review execution never writes manuscript prose or rich-text resources.
