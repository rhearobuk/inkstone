# Bug remediation plan: #18, #19, #20

Date: 2026-09-20

## Scope and evidence

Cover macOS, iPadOS, and visionOS, as confirmed during triage. iPhone support is
not part of this work. Apply the fixes to the shared data/controller layer and
expose equivalent actions in each platform's UI.

This is source-based triage of the current checkout against the three open
0.3.0 reports, not a claim of interactive reproduction on three devices.
Reports #18 and #20 explicitly report all three platforms; #19 names macOS.
The missing shared implementation makes #19 applicable to the other platforms
too, but each platform still needs an acceptance run.

| Report | Assessment | Proposed priority | Scope |
| --- | --- | --- | --- |
| [#20](https://github.com/rhearobuk/inkstone/issues/20): inconsistent deletion | Confirmed implementation gap. Binder actions require a document ID; non-character entity cards have no entry deletion action. Characters have a separate deletion implementation. | High: blocked basic lifecycle operation | Organizations, places, artifacts, events/timelines/conflicts, worldbuilding, and native characters; preserve working imported-character and Research behavior. |
| [#19](https://github.com/rhearobuk/inkstone/issues/19): status/label assignment | Confirmed implementation gap, not missing definition management. Project Preferences already manages definitions, but editors do not assign them. Entity records also lack assignment fields. | High: no assignment workflow | Narrative documents/folders, Research documents, character dossiers, and all other Story Bible entries. |
| [#18](https://github.com/rhearobuk/inkstone/issues/18): Story Bible organization | Confirmed for entity-backed entries; document-backed entries already have some movement support. | Medium: blocked organization workflow | Persistent ordering of native entities and imported/native documents, including mixed categories and existing document folders. |

The central distinction is **Document versus SemanticEntity**, not platform.
Do not assume all Story Bible entries are documents or that all characters
currently share the same binder capabilities.

## Root causes and implementation touchpoints

- `Sources/AuthorUI/AuthorWorkspaceView.swift`: `BinderDragModifier` only drags
  document IDs; row actions and `TouchBinderActionsMenu.hasActions` likewise
  exclude entity-only entries. `BinderDropModifier` treats any category-bearing
  non-document row as a category drop target, including entity rows. Correct
  this distinction when adding entity drop targets.
- `Sources/AuthorUI/WorkspaceController.swift`: `rebuildBinder()` sorts entities
  alphabetically, then concatenates them before documents. `moveDocument`
  handles documents only. `BinderItem` and `ActiveDropTarget` are document-centric.
- `Sources/AuthorUI/StoryBibleCardView.swift`: note deletion exists, but deleting
  the whole entry does not. `CharacterDossierView` has a separate confirmed,
  permanent deletion flow through `deleteCharacterProfile`.
- `Sources/AuthorData/ManagedObjects.swift`: `Document` has label/status
  identifiers and sibling ordering; `SemanticEntity` has none of these.
- `ProjectPreferencesView.swift` already provides label/status definition CRUD.
  `filteredBinderItem()` applies metadata filters only to document-backed rows;
  adding pickers alone would leave Story Bible filtering incorrect.
- The current Core Data model is V10. Both source `.xcdatamodeld` and compiled
  `.momd` ship in the repository. Persistence uses CloudKit-capable Core Data.
- `.github/workflows/swift-tests.yml` currently runs macOS Swift package tests
  only; it does not establish iPadOS or visionOS UI parity.

## Recommended behavior contract

These are proposed implementation choices for approval, not changes already made.

1. **Deletion:** extend the existing confirmed permanent character-deletion
   model to other semantic entries. Keep document-backed Research and other
   document entries on the existing Trash/Restore flow. Label the actions
   distinctly and explain permanence. A unified, restorable entity Trash is a
   separate product decision, not an implicit expansion of this bug fix.
2. **Metadata:** one optional Label and one optional Status per content entry,
   using the project's existing definitions. Interpret "Tags" in #19's title as
   "Labels", consistent with its reproduction and expected result; do not add
   a separate multi-tag feature. Exclude virtual navigation headings.
3. **Organization:** support before/after ordering within a Story Bible
   category, including mixed document/entity rows, plus existing document
   nesting and document category moves. Provide non-drag Move Up/Move Down
   controls. Do not silently turn a character into a place by dropping across
   semantic categories. New entity folders or cross-category type conversion
   require a separate behavior decision.

## Delivery sequence

### 1. Shared targeting and regression fixtures

Introduce a typed content target identifying a document or semantic entity.
Resolve character dossiers and cards to that target rather than duplicating
records. Imported characters displayed through their source document must
resolve consistently for ordering, metadata, and deletion.

Centralize available actions and validation in the controller; reuse those
actions in Mac context menus and iPadOS/visionOS ellipsis menus. Keep platform
presentation separate from persistence logic. Reject missing, cross-project,
trashed, or otherwise invalid targets with explicit errors.

Create original, synthetic fixtures covering every Story Bible category,
native and imported characters, document folders, mixed categories, relationships,
mentions, attached photos, and a second project.

### 2. Restore deletion (#20)

Add a shared semantic-entry deletion operation and wire it into the card/detail
view and platform binder menus. Delegate the character-specific case without
changing its existing imported-source deletion contract.

Review and exercise Core Data cascade/nullify behavior for cards, notes, aliases,
mentions, character links, and incoming/outgoing relationships. Remove owned
records and links, but preserve related characters and narrative text. Preserve
project-owned gallery images by unlinking them unless an existing ownership
contract explicitly requires removal.

Flush or cancel relevant pending editor saves before deleting. After a
successful save, select a surviving category and refresh all affected views.
Report persistence failure without displaying a successful deletion or leaving
the editor pointed at a deleted object.

**Acceptance:** deletion is available for each semantic category on every
platform; cancel is non-destructive; confirmed deletion persists after reopen;
related entries and narrative text survive; Research Trash/Restore and existing
character deletion continue to work.

### 3. Add one compatible schema evolution for #18 and #19

Plan a V11 model rather than editing historical versions. Add optional
label/status identifiers to semantic entities. Retain document identifiers as
the source of truth for document-backed imported characters, avoiding divergent
values between the source document and its dossier.

For mixed Story Bible root ordering, use a persisted optional category-order
value on both documents and semantic entities. Keep document `parent` and
`orderIndex` authoritative for nested document hierarchies; a separate
category-order value avoids perturbing Narrative ordering.

Before the first manual reorder, preserve the existing presentation: alphabetical
entities followed by ordered documents. On first reorder, assign the complete
category sequence deterministically; append new entries thereafter. Use UUID
tie-breakers for equal positions, including concurrent synced edits. Reopening,
refreshing, or changing a name must not discard explicit order.

Keep new attributes CloudKit-compatible, regenerate the compiled model, and
verify V10-to-V11 migration with synthetic SQLite stores. Check the importer's
ownership rules so existing imported metadata remains intact and repeat imports
do not accidentally erase native ordering or create duplicate content.

### 4. Expose assignment controls (#19)

Build a reusable Label/Status editor backed by validated controller setters.
Place it in document/folder editors, character dossiers, and Story Bible card
and semantic-entry detail paths. Include explicit None choices and a route to
the existing project definition manager; handle empty definition lists.

Populate entity binder badges/colors and apply filters to both target types.
Maintain ancestor visibility for matching descendants. Preserve existing
duplicate-title/imported-identifier matching behavior.

Renaming definitions must update displayed values without rewriting identity.
Deleting a definition must clear its exact references on both target types,
including trashed documents; it must not clear another same-titled definition.
Setters must reject definitions from another project.

**Acceptance:** assign, change, and clear either field on every supported
content type; values survive reopen; definition rename/delete, filters, badges,
and imported character views remain consistent on all three platforms.

### 5. Enable Story Bible movement (#18)

Replace document-only drag targeting with typed, project-aware payloads and
typed drop indicators. Category headers, entity rows, and document containers
must be distinguished explicitly. Both drag and menu movement must invoke the
same ordering operation.

Merge entity/document roots by their persisted category order. Preserve
document nesting, cycle prevention, word-count rollups, and selection. Reject
invalid entity nesting and semantic category conversion explicitly. Exercise
document moves between categories and between Narrative and Story Bible so
category markers do not leave an item displayed in its previous category.

Disable ambiguous reordering while search or filters obscure the full order,
with an explanation to clear the filter. Retain navigation and non-ordering
actions while filtered.

**Acceptance:** move first/middle/last entries in both directions; interleave
entities and documents; reopen and retain the exact order; move nested documents
without cycles or changed word totals. Menu movement must work without a mouse
or a successful drag gesture.

## Cross-platform acceptance matrix

Every cell is required before closing the corresponding issue. This is a
planned matrix, not a record of completed device verification.

| Scenario | macOS | iPadOS | visionOS |
| --- | --- | --- | --- |
| #20 delete/cancel every semantic entry kind | Detail action and context menu | Detail action and ellipsis menu | Detail action and ellipsis menu |
| #19 assign/change/clear Label and Status | All editor variants | All editor variants in touch layout | All editor variants in spatial layout |
| #18 reorder entity/document/mixed categories | Pointer drag and move menu | Touch drag and move menu | Supported drag interaction and move menu |
| Existing document nesting and Research Trash/Restore | Required | Required | Required |
| Save/reopen, selection, filters, error presentation | Required | Required | Required |

Run controller and data tests first for the affected suites; include on-disk
round trips, migration, deletion graph integrity, invalid targets, duplicate
names, and imported/native representation parity. Keep every regression as a
discoverable top-level test method: the existing imported-container movement
test is nested inside another test and should be promoted when extending that
coverage.

Then run the complete Swift package suite and build the actual Xcode app for
Mac, iPad Simulator, and visionOS Simulator. Add simulator build coverage to CI
where the required SDKs are available. Use app-level UI tests or recorded manual
steps for the matrix; a shared-code build alone does not verify interactions.
Check accessibility labels, keyboard navigation on Mac, touch hit targets on
iPad, and discoverability without hover/right-click on Vision Pro.

For the new persisted fields, perform a signed-in cross-device sync smoke test:
change order/metadata on one device and observe the other; verify entity deletion
propagates without orphaned links. If account/device access is unavailable,
record that gate as pending rather than claiming sync verification.

## Completion and boundaries

Deliver #20 first after shared targeting, then the common model changes, #19,
and #18. Each issue needs its own regression evidence and three-platform
acceptance results; do not close all three merely because the shared layer works.
Update `Documentation/DataModel.md`, `Documentation/UI-Walkthrough.md`, and
relevant README/help instructions alongside implementation.

No application behavior, issue state, or Git history was changed during this
triage. The pre-existing local change to
`AuthorApp.xcodeproj/project.pbxproj` is outside this plan's edits and must be
preserved during subsequent implementation.
