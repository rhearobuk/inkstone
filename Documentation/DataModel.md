# Data model

## Sharing ownership topology

Issue #11 introduces an explicit ownership contract before changing the
versioned Core Data schema. The contract prevents a future migration from
turning sharing into a private/shared manuscript synchronization system.

Every canonical record has exactly one authoritative route:

- The owner's canonical records remain in the private-database store whether
  their group currently has participants or not.
- Records accepted from another owner live in the participant shared-database
  store and identify exactly one SharingGroup.
- A SharingGroup is one disconnected authorization graph and one prospective
  CKShare boundary.
- Manuscript, feedback, and Story Bible context use different groups when their
  CloudKit permissions differ.
- References across groups are stable UUID values, never Core Data
  relationships.
- Users may belong to multiple groups. A record is not copied into multiple
  groups to provide broader access.

SharingTopologyValidator rejects duplicate canonical routes, participant-shared
records without a group, unknown groups, and cross-project group assignments.
An owner record may acquire a group without moving stores: CloudKit shares
records from the owner's private database and exposes them in each participant's
shared database. These checks are owner-authoritative storage rules; they are
not participant-editable roles or UI visibility flags.

V12 begins the additive physical migration:

- SharingGroup and ShareParticipant persist owner-authoritative group metadata
  and invitation state without Core Data relationships.
- Document adds optional projectID, parentID, and sharingGroupID scalar UUIDs.
- SemanticEntity adds optional projectID and sharingGroupID scalar UUIDs.
- Annotation adds an optional sharingGroupID scalar UUID.

V11 libraries migrate with no groups or participants, so every existing library
remains private. On first open, project and parent UUIDs are backfilled from the
legacy relationships; subsequent saves keep those scalar IDs aligned. The
legacy connected relationships remain temporarily available to the existing
application and are not safe to share until application reads and writes have
moved fully to the scalar topology.

AuthorDataStore loads named Private and Shared physical stores. The Private
store mirrors the owner's private CloudKit database; the Shared store mirrors
records accepted from other owners. EntityRepository inserts are assigned to
the selected store and fetches use affectedStores to avoid ambiguous
cross-store lookup. Existing convenience repositories remain pinned to Private
until their features adopt explicit group-aware routing.

## Ownership and document hierarchy

`WritingProject` is the aggregate root. `Document` models every ordered Scrivener binder item, not only prose: draft folders, folders, text, images, PDFs, and unknown future kinds remain distinguishable through `kind`. The self-referential parent/children relationship stores hierarchy; `orderIndex` stores sibling order independently of unordered Core Data relationship storage.

V11 adds `storyBibleOrderIndex: NSNumber?` to both `Document` and
`SemanticEntity`. Each is an optional Core Data Integer 64 with
`usesScalarValueType="NO"` and no default, so migrated and newly created
records distinguish an unset position (`nil`) from position zero. It stores
mixed document/entity ordering at a Story Bible category's root, independently
of `Document.parent` and `Document.orderIndex`; those remain authoritative for
nested documents and Narrative ordering. An unset category retains the legacy
presentation (alphabetical entities, then sibling-ordered documents); the first
manual reorder establishes positions for the complete category. Ordering policy,
including UUID tie-breakers and appending new entries, belongs in the controller,
not in the migration.

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

`StoryBibleCard` is the native, non-RTF card for a Story Bible entry. It
belongs to one project and one `SemanticEntity`, cascade-owns ordered
`StoryBibleNote` records, and reuses the entity's gallery items for photos.
Location cards record a description, unique features, freeform location,
international street address, GPS coordinates, and sight/sound/smell
descriptors. Their related characters, artifact owners, and organization
members are separate to-many foreign-key relationships to `CharacterProfile`;
they are nullified if a character is removed. All newly created Story Bible
entries use cards rather than narrative scene documents.

`StoryBibleRelationship` is a single, typed link between any two
`SemanticEntity` records in the same project. Each endpoint exposes the same
link through outgoing or incoming relationships, so an organization owning an
artifact, a character belonging to an organization, or a place containing an
artifact is visible from both cards without duplicating data. Deleting either
endpoint cascades to delete its relationship links.

`Annotation` has a controlled kind (`note`, `comment`, `highlight`, `todo`, `question`, `warning`, or `modelSuggestion`), lifecycle status, author/source, and optional document range. `Revision` records immutable text snapshots with sequence and content hash.

Generated interpretations should be stored as typed semantic entities, mentions, annotations, metadata values, or revisions with `source = "model"` and a `ProvenanceEvent`. They must not be embedded in opaque binary payloads. `ProvenanceEvent` records agent, version, timestamp, source URI/identifier, content hash, and concise human-readable details.

## Extensible metadata

`MetadataField` defines a project-scoped key, display name, scalar value type, and semantic purpose. `MetadataValue` has separate string, integer, double, boolean, and date columns so values remain filterable. Unknown Scrivener metadata is retained under stable `scrivener.*` keys with its source XML path; custom fields become keys such as `scrivener.MetaData.Custom.sexualcontent`.

## Project preferences (section types, labels, statuses, custom metadata)

`LabelDefinition`, `StatusDefinition`, and `SectionTypeDefinition` are project-scoped vocabularies parsed from the Scrivener project XML's `<LabelSettings>`, `<StatusSettings>`, and `<SectionTypes><TypeDefinitions>` blocks (siblings of `<Binder>`). Each stores the source ID (Scrivener's numeric label/status ID or section type GUID), a display `title`, `orderIndex` for stable ordering, and — for labels — an optional RGB color parsed from Scrivener's `"R G B"` color string. `LabelDefinition.isDefault`/`StatusDefinition.isDefault` reflect Scrivener's `DefaultLabelID`/`DefaultStatusID`. `Document.labelIdentifier`, `statusIdentifier`, and `sectionTypeIdentifier` reference these definitions' `sourceIdentifier` values.

V11 adds optional `SemanticEntity.labelIdentifier: String?` and
`SemanticEntity.statusIdentifier: String?`, referencing the same project-scoped
definition identifiers, not their titles. Both default to `nil` (None).
Document-backed imported characters continue to use their source document's
label/status identifiers as the source of truth; migration does not copy those
values into the dossier's semantic entity. Definition validation and clearing
references when definitions are deleted are controller responsibilities.

`CustomMetaDataSettings/MetaDataField` entries populate `MetadataField` rows keyed as `scrivener.MetaData.Custom.<fieldID>` (matching the keys `upsertMetadata` derives per document), with `MetadataField.sourceIdentifier` set to the Scrivener field ID and `displayName`/`valueType` taken from the settings block rather than inferred from the key. Import order matters: per-document metadata is imported first (creating placeholder fields if needed), then `importProjectSettings` runs so the authoritative titles/types from the settings block win.

These four definitions back `ProjectPreferencesView` (`AuthorUI`), a project-level preferences pane (opened via the binder toolbar's gear icon) for viewing and editing Section Types, Labels, Statuses, and Custom Metadata fields, including adding/renaming/deleting entries and recoloring labels. User-created entries use a synthesized `native.<uuid>` (or `custom.<uuid>` key) source identifier since they have no Scrivener origin.

## Identity and migration

Source-owned UUIDs remain unchanged. Derived IDs are deterministic within the project namespace, making imports repeatable. Source identifier/path compound constraints provided additional conflict protection through `AuthorDataV6`; as of `AuthorDataV7` these are enforced only in the Swift API (via `upsert`), not as Core Data uniqueness constraints, since CloudKit mirroring does not support them (see "iCloud sync" below).

The persistent container enables automatic model migration and inferred mappings. `AuthorDataV1` preserves the original schema, and `AuthorDataV11` is current; the compiled `AuthorData.momd` contains V1–V11 versions so existing SQLite stores migrate through an inferred lightweight mapping. V11 is an additive evolution of V10: only the four optional attributes described above are added, with no changes to existing attributes, relationships, or historical models. `Persistence.swift` loads the current version selected by the compiled bundle's `VersionInfo.plist`; no hard-coded model version needs updating. Future schema changes should add a new version under `AuthorData.xcdatamodeld`, select it in `.xccurrentversion`, regenerate `AuthorData.momd` with `xcrun momc`, and add a migration test opening a store created from the previous model. Use explicit mapping models when a change cannot be inferred without data loss.

`StoryBibleMigrationTests` creates a synthetic V10 SQLite store, opens it through
`AuthorDataStore`, and checks identity, imported document metadata, definitions,
document hierarchy, dossiers, cards, notes, aliases, mentions, and semantic links.
The new fields must migrate as `nil`, then persist assigned values across reopen.
A separate latest-model on-disk round trip checks assignment and clearing back
to `nil`, including 64-bit order values.

The Swift API and importer treat aggregate relationships as required and validate them before saving imported data, even though every relationship is modeled as optional (required for CloudKit compatibility, see below).

## iCloud sync (V7 onward)

`AuthorDataStore` uses `NSPersistentCloudKitContainer` so every project, document, and related record mirrors to the signed-in user's private iCloud database and stays in sync across their devices in near real time. `AuthorDataStore.open(storeURL:)` is the app entry point: it enables CloudKit mirroring and surfaces schema, migration, and corruption failures rather than silently disabling sync. It falls back to a local-only store only when an unsigned development process (for example, a plain `swift run`) lacks the iCloud/CloudKit entitlement. Call `AuthorDataStore.init(storeURL:inMemory:cloudKitSyncEnabled:)` directly only when you need explicit control (tests default `cloudKitSyncEnabled` to `false`).

`AuthorDataV7` made the schema CloudKit-compatible:
- Removed all `uniquenessConstraints` (unsupported by CloudKit; the `id` uniqueness constraint from earlier versions is gone).
- Every non-optional attribute lacking a default value either gained an empty-string default (`String`) or became optional (`UUID`/`Date`); the generated Swift classes still expose these as non-optional properties, so callers must keep setting them immediately on creation, as `EntityRepository.create`/`upsert` already do.
- Relationships were already modeled as optional going back to `AuthorDataV1`, which CloudKit also requires.

`AuthorDataV8` completes that compatibility work by assigning zero defaults to the six required scalar attributes that V7 missed: `DocumentEntityMention.location`, `DocumentEntityMention.length`, `Revision.sequence`, and the three `ImportRun` counters. `testCurrentModelMeetsCloudKitAttributeRequirements` audits every model attribute so future required attributes cannot omit a default unnoticed.

All four V11 attributes are optional and introduce no uniqueness constraints or
relationship changes, preserving the CloudKit schema requirements. Local
migration/reopen tests do not substitute for a signed-in cross-device sync smoke
test.

The Xcode app target (`Inkstone`) declares `com.apple.developer.icloud-container-identifiers` (`iCloud.com.robertrhea.scribe`) and `com.apple.developer.icloud-services` (`CloudKit`) in `Sources/AuthorApp/AuthorApp.entitlements`, wired in via `CODE_SIGN_ENTITLEMENTS`. The container's legacy identifier is retained to preserve existing iCloud data. It must remain registered under the signing team (already done via [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → iCloud Containers) for sync to work on a real device/build.


## AI Editor reviews (V5)

`EditorialReview` is project-owned and cascade-owns inputs, findings, and processing chunks. Inputs preserve exact submitted text, hashes, source UUID/title/path/order, and manuscript/context role. Findings contain typed category, severity, explanation, recommendation and independent human tracking fields. Multiple `EditorialFindingAnchor` records point into immutable input snapshots using verified UTF-16 ranges. Invalid or ambiguous quotations fall back to document-level references.

Deleting a target document or persona nullifies the live reference without erasing review snapshots. Deleting a project or review cascades through its review records. Persona presets are idempotently seeded; customized personas and each run's effective rubric are independent. History keeps selected provider/model, prompt/schema versions, timestamps, parameters, OS/app version, reported token usage when available, and rerun links. `ProvenanceEvent` records terminal review outcomes.

States distinguish completed, partial, failed, refused, cancelled and interrupted runs. Startup marks abandoned active runs interrupted without resending text. Chunk records preserve coverage and intermediate summaries; synthesis is hierarchical and no manuscript input is silently truncated. This is an editorial subsystem: review execution never writes manuscript prose or rich-text resources.
# Canonical sharing boundary (V13)

Model V13 turns the group design proven by Issue #10 into the production persistence boundary. A manuscript `Document` remains the one canonical current manuscript record. Before its first share, legacy relationships that cross authorization boundaries are converted to stable UUID references and cleared from the document's persistent relationship graph. The document is then related only to its `SharingGroup`, so Core Data's deep CloudKit traversal cannot pull in the private project, revisions, metadata, resources, editorial inputs, or Story Bible records.

The application resolves project/document navigation through `projectID` and `parentID`; sidecars use their corresponding UUID fields. This is an ID join, not a copied manuscript or synchronization layer. Existing libraries migrate additively and remain private until an author explicitly creates a share.

Separate groups enforce separate CloudKit permissions:

- `manuscript`: canonical eligible documents; read-only for viewers/reviewers and read-write for editors/collaborators.
- `feedback`: participant-writable annotations joined to manuscript records by `documentID`; no relationship to manuscript text.
- `storyContext`: explicitly granted Story Bible entities, independent of manuscript permission.

`SharingGroup` is the only share root. Its relationships contain only records authorized for that group. A canonical record with an existing different `sharingGroupID` is rejected instead of copied into another share.
