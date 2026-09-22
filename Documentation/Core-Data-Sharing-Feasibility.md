# Core Data sharing feasibility (issue #10)

## Decision

**No-go for automatic `NSPersistentCloudKitContainer` sharing with the current
V11 model.** Do not expose a Share command for manuscript records and do not
deploy a sharing schema to production. Return to issue #2 for approval of a
custom CloudKit synchronization design or a deliberately repartitioned model.

This is a confidentiality decision, not a UI limitation. A successful
invitation would not satisfy the requirements.

## Reproducible preflight evidence

Apple documents that `share(_:to:completion:)` performs a deep traversal of all
relationships and moves the connected object graph into the share's record
zone. It also rejects objects already assigned to another share and does not
support relationships across shares.

Inkstone V11 has this path:

```text
selected Document -> project -> documents -> every sibling Document
                            \-> resources
                            \-> semanticEntities / characterProfiles / storyBibleCards
                            \-> metadata and definition records
```

The inverse relationships are enough to expose the private project and its
other manuscripts when a single scene is shared. Scene relationships also reach
resources, metadata values, annotations, revisions, links, and mentions.

`CoreDataSharingPreflight.audit(root:allowedObjectIDs:)` mirrors the realized
relationship traversal locally. The regression test constructs a reviewer scene
and an excluded private sibling, then proves that starting at the reviewer scene
reaches both the private `WritingProject` and the excluded sibling. The isolated
control record reaches only itself.

Run:

```sh
swift test --filter CoreDataSharingPreflightTests
```

This preflight is a safety gate, not a replacement for server-side testing.
CloudKit shares complete records, so it cannot remove private attributes from an
otherwise allowed record.

## Acceptance matrix

| Requirement | Result | Evidence / consequence |
| --- | --- | --- |
| Excluded text, private titles/metadata, resources, and history never enter the share | **Fail** | Deep traversal reaches the project, sibling documents, resources, metadata values, and revisions. CloudKit has no per-field share filter. |
| Adding one scene cannot traverse into its project, other books, or Story Bible | **Fail** | The checked-in preflight regression demonstrates `Document.project.documents`; the same project reaches Story Bible entities. |
| Withdrawal preserves canonical author content without a duplicate | **Not safely implementable** | Apple's purge API deletes the local object graph as well as remote zone records. Apple's suggested preservation mechanism is a deep copy, which violates the no-duplicate requirement. Removing a participant preserves the owner's zone but cannot recall data already downloaded. |
| Withdrawal per document versus group | **Group only** | Access is revoked at `CKShare`/zone participant scope. A document can have its own share only by consuming a separate zone and invitation; the existing graph cannot be split across those shares. |
| Private edits after withdrawal, pending invitations, offline owner reconnect | **Blocked by earlier confidentiality failure** | These propagation tests cannot turn a graph that already discloses private records into a valid design. Acceptance and propagation must remain separate states in any replacement design. |
| Read-only manuscript plus writable feedback | **Fail in one graph/share** | Participant permission applies to the share. Read-only text and writable feedback require independently shared record groups with ID-only references. Current Core Data relationships cannot cross those shares. |
| Two recipients with overlapping scopes | **Fail** | A managed object can belong to only one share, so overlapping per-recipient scopes cannot reuse the same canonical record in separate shares. One broad shared zone weakens scope and revocation. |
| Collaborator with private draft access | **Requires separate approved scope** | Share-wide read/write permission grants mutation rights to every included non-root record; it cannot express Editor text-only versus Collaborator structural rights. |
| Practical zone/invitation limits | **Fail as a per-document strategy** | Core Data creates a zone per share and CloudKit limits zones. Per-document sharing also creates unacceptable invitation and management overhead. Do not assume one Book equals one share. |

## Supported API sequence for a future bounded prototype

Only run this sequence in a signed development build against the **development**
CloudKit environment after issue #2 approves a model whose preflight is clean:

1. Owner saves canonical records and waits for a successful CloudKit export.
2. Run the local object-graph preflight. Abort on any unexpected record.
3. Call `share(_:to:completion:)` with no existing share, configure the returned
   `CKShare` as private, set participant permission, and persist changes with
   `persistUpdatedShare(_:in:completion:)`.
4. Deliver the system invitation. Record invitation creation separately from
   participant acceptance and data propagation.
5. Recipient accepts metadata into the shared persistent store. Inventory actual
   downloaded record IDs and fields; compare them with the allowed manifest.
6. Owner removes the participant and persists the updated share. Do **not** call
   `purgeObjectsAndRecordsInZone` as an unshare shortcut.
7. Verify server rejection after revocation separately from propagation to each
   online/offline device. State explicitly that previously downloaded copies
   cannot be recalled.
8. Edit privately, reconnect devices, re-invite, and verify stable logical IDs,
   no copied manuscript, pending-invitation behavior, comments, and history.

## Evidence status

| Lifecycle step | Status |
| --- | --- |
| Local connected-graph inventory | **Fail captured by automated test** |
| Production schema/data untouched | **Pass** |
| Signed two-account invitation and acceptance | **Not run: prohibited by failed confidentiality preflight** |
| Offline withdrawal/reconnect | **Not run: prohibited by failed confidentiality preflight** |
| Re-share same logical scene | **Not run: prohibited by failed confidentiality preflight** |

Stopping before uploading known-private records is the required outcome of this
spike. A two-account happy-path run against this model would create the exposure
the issue is intended to prevent and would not change the no-go decision.

## Required follow-up in issue #2

Approve one of these architecture changes before implementation:

- Custom CloudKit synchronization with canonical app IDs, explicit record
  manifests, ID-only cross-scope references, and separate manuscript, feedback,
  and private-context zones; or
- A Core Data redesign that removes all cross-share relationships and accepts
  the one-record/one-share and zone/invitation constraints.

Neither option may introduce a silently maintained reviewer manuscript or claim
that app-only Editor/Collaborator guards are enforced by CloudKit.

## Group-scoped, two-store follow-up prototype

The follow-up prototype tests an ownership-partitioned architecture. It does not
maintain a private manuscript and a reviewer manuscript:

    Private persistent store             Collaboration persistent store
    ------------------------             ------------------------------
    PrivateDocumentContext               SharingGroup
      documentID ----------------------> SharedDocument.id
      private status                       canonical current text
      historical draft                  GroupMember
                                         FeedbackGroup
                                         Feedback.documentID

The arrow is a scalar UUID lookup, not a Core Data relationship. Each field has
exactly one owner. Canonical current text exists only on SharedDocument; the
private store deliberately has no currentText attribute.

Every collaboration group is a disconnected object graph suitable for one
CKShare. Users may be members of multiple groups, but a collaboration record
belongs to exactly one group. Broader access is implemented by membership in
each applicable subgroup, not by placing one record in multiple shares.

Read-only manuscript and writable feedback use separate groups. Feedback points
to the manuscript with a scalar documentID, so its graph cannot traverse into
manuscript text.

### Automated results

GroupScopedSharingPrototypeTests uses two in-memory Core Data persistent stores
with separate model configurations.

| Test | Result |
| --- | --- |
| A manuscript group cannot traverse into the private store | **Pass** |
| A manuscript group cannot traverse into another group | **Pass** |
| Canonical current text exists in exactly one SharedDocument | **Pass** |
| Private context and shared text compose through a UUID-only UI projection | **Pass** |
| Writable feedback cannot traverse into the manuscript graph | **Pass** |
| Removing and restoring membership preserves the canonical object ID without copying text | **Pass** |

Run: swift test --filter GroupScopedSharingPrototypeTests

### Revised decision

**Go for a signed development-CloudKit prototype of group-scoped sharing,
conditional on preserving these invariants.**

Sharing the connected V11 Document graph directly remains a no-go. This
follow-up test proves the local persistence and traversal boundaries, but it
does not claim to prove CloudKit invitation acceptance, participant-removal
propagation, or offline behavior. Those lifecycle checks require a signed
two-account development build. They must remove participants from the share,
never purge the zone, and verify that the owner's canonical SharedDocument
remains unchanged.
