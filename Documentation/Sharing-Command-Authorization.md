# Sharing Command Authorization

All shared-session reads and mutations pass through `PermissionedCommandGateway`.
The gateway checks an owner-issued role, policy version, authorized UUID set,
independent Story Bible grant, and existing external-AI consent before running a
command. Missing identifiers return an opaque unavailable error and never fetch
private titles, bodies, metadata, or relationships.

Viewer is read-only. Reviewer adds feedback only. Editor may edit prose and
metadata but not structure, sharing administration, private history, or Story
Bible by default. Collaborator may author content, structure, resources, and
explicitly granted Story Bible context, but cannot administer ownership or
permissions. CloudKit cannot enforce text-only versus structural writes inside
one writable share, so Editor and Collaborator use separate owner-approved
group topologies; Inkstone does not claim field-level server authorization.

Reviewer manuscript groups are read-only. Feedback is stored in a separate
writable group anchored by document UUID, revision UUID, and content hash.
Anchors explicitly represent stale, deleted, and withdrawn states. Feedback
does not include manuscript text, private revision history, editorial inputs,
provider prompts/settings, or credentials.

Story Bible grants remain none, selected, full-read, or edit. Canonical context
entities may belong to only one authorized group; overlapping assignments fail
closed rather than creating per-recipient copies.
