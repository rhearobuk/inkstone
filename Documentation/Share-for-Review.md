# Share for Review

Use **Share for Review** from a Book's context menu or the workspace toolbar.
The workflow defaults to Reviewer, the project's configured reviewable status
identifiers, and no Story Bible access. Before invitations begin it shows the
recipient, role, Book scope, selected statuses, independent context grant, exact
included/excluded counts, and author-only exclusion reasons produced by the
same versioned policy used for publication.

Manuscript, feedback, and context invitations are independent. Each displays
Ready, Pending, Shared, or Failed; partial completion is never labelled fully
shared and failed groups remain retryable. Recipients see only authorized
navigation and content, never the author's exclusion explanations.

A canonical record belongs to at most one sharing group, because a CloudKit record
can live in only one share. Preparation saves group membership before publishing,
so before each attempt Inkstone releases records held by groups that never got a
CKShare (failed, abandoned, or different-scope attempts). Records in a live share
stay put, and the owner sees which item and which shared scope already hold it.

Sharing is asynchronous. Read-only manuscript access, permitted feedback,
Story Bible access, and conflict recovery depend on the role and grants shown in
the workflow. Revocation stops future access after CloudKit propagates, but it
cannot recall content a recipient already copied. Local-only builds explain that
sharing is unavailable rather than reporting success.
# Live invitation and participant workflow

Creating invitations now creates or reuses three independent CloudKit groups: manuscript, feedback, and optional Story Bible context. Each group reports its own success or failure and failed groups can be retried without recreating successful shares. The entered email address is resolved as a private CloudKit participant; public sharing remains disabled.

Once the link exists, the Send Invitation section moves to the top of the sheet. **Copy Link** puts the invitation URL on the pasteboard and is the dependable path; emailing via Mail or sending through the system share picker are the other options. The same actions are available later from Manage Access. While an invitation is being created, the create button shows progress and ignores repeat clicks.

Reviewer manuscript permission is server-enforced read-only. Its feedback group is read-write, and feedback is inserted into the participant shared store with a scalar `documentID` anchor. No reviewer manuscript or reconciliation copy is created. Owners can inspect persisted participants and revoke future access. Revocation is asynchronous and cannot recall content that a participant already downloaded.
