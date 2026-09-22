# CloudKit Sharing Lifecycle

Inkstone uses the named Private and Shared stores from Issue 11. Owners create
private CKShare zones from canonical records in the Private store; accepted
invitations import into the Shared store. Public permission is always `.none`.
Repository fetches remain constrained with `affectedStores`.

`CloudKitSharingService` uses only `NSPersistentCloudKitContainer` sharing APIs:
share object graphs, accept metadata into the shared-scope store, persist updated
shares, fetch shares, and purge a participant's shared zone on departure. Owner
revocation removes participants and retains the owner's private canonical graph.
Participant cleanup is rejected for owners.

Invitation metadata may arrive before startup is ready and is deduplicated in
`CloudKitInvitationInbox`. Platform targets must route cold/warm scene callbacks
to this inbox and set `CKSharingSupported = YES` in their generated Info.plist.
Multiple manuscript, feedback, and context groups are reported independently;
partial success is recoverable and never described as atomic.

Local-only or unsigned builds return `localOnlyBuild` and never claim success.
UI must distinguish missing account, network failure, permission denial,
revoked/expired invitations, and retryable partial failure. Withdrawal blocks
new publication immediately, but CloudKit propagation is asynchronous and
content already copied by a participant cannot be recalled.
