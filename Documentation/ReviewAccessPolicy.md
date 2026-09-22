# Review Access Policy

`ReviewAccessPolicyResolver` is the single eligibility decision point for review
preview and publication. It consumes owner-authored policy and grants plus a
scalar record manifest. It never trusts participant-editable role data and does
not fetch through Core Data relationships.

The policy is deliberately conservative:

- Reviewable statuses are configured by stable identifier. Missing, deleted, or
  unconfigured statuses are excluded.
- `includeInCompile == false` excludes the record and its descendants. Status is
  not inherited from folders; every manuscript-text record must independently
  have an allowed status.
- Structural records may contribute only navigation identity. The resolver does
  not expose their title, path, notes, text, or assets.
- Private resources and feedback always remain in separate authorization
  boundaries.
- Story Bible access is independently granted as none, selected IDs, full read,
  or edit. A selected record does not grant related records or descendants.

Preview returns included and excluded counts, per-record exclusion reasons, app
capabilities, and a token covering the policy version, grant, and complete input
manifest. Publication recomputes the same policy and rejects a stale token. Its
records move from `pendingCloudPublication` to `serverEnforced` only when that
check succeeds; capabilities remain app-enforced within the CloudKit boundary.
Comparing the last published result with a new preview yields explicit publish
and withdrawal ID sets when status, ancestry, flags, or grants change.

The existing `ReviewScopeResolver` continues to serve local author-only AI
review. Issue 12 does not change its behavior.
