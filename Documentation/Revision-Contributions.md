# Revision Contributions and Trust Boundary

`RevisionContributionArchive` is the durable causal history for manuscript and
Story Bible changes. Each contribution has a unique ID, zero or more causal
parents, actor and device claims, affected fields, before/after values, policy
version, provenance source, and private or authorized-group visibility. Plain
and rich text, moves, tombstones, status and publication flags, annotations,
and Story Bible edits use the same typed value envelope.

The archive accepts out-of-order delivery and deduplicates both contribution IDs
and delivery IDs. Divergent heads are conflicts; no branch is silently selected.
Restoring an old value creates a new contribution whose parents are the current
heads. Per-store persistent-history tokens are checkpoints for ingestion only;
the archive, not purgeable Core Data transaction history, is the durable record.

Owner-private history and group-authorized contributions are separate archive
views. Publishing current manuscript content does not publish old private
drafts. There remains one editable canonical manuscript; the archive contains
immutable historical contributions, not a synchronized manuscript copy.

Platform-verified actor identifiers are stored separately from client-reported
names and device IDs. A writable CKShare cannot provide tamper-proof or truly
append-only audit guarantees against a malicious writer. Full adversarial audit
retention requires another owner-controlled or server-controlled trust boundary;
Inkstone must not claim that guarantee until such a boundary exists.
