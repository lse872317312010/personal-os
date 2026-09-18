# Personal OS MCP v0 contract

Status: implementation baseline  
Protocol identifier: `personal-os.mcp.v0`

## Boundary

Android is the system of record. External Agents perform all reasoning. An
Agent may read an explicitly scoped context and submit proposals, but it cannot
silently mutate assets, goals, executions, outcomes, reviews, or active
strategies.

Every response carries a `session_id`, `protocol_version`, and pinned object
references. Any accepted write is attributed to the originating Agent session.

## MCP resources

| URI template | Purpose |
|---|---|
| `personal-os://profile/summary` | Minimal user-approved summary |
| `personal-os://assets/{id}?revision={n}` | One pinned personal asset |
| `personal-os://goals/{id}?revision={n}` | One pinned goal |
| `personal-os://strategies/{id}?revision={n}` | Strategy and lineage |
| `personal-os://executions/{id}` | Recorded implementation |
| `personal-os://outcomes/{id}` | Deterministic result or observation |
| `personal-os://reviews/{id}` | Strategy review |
| `personal-os://sessions/{id}` | Agent interaction audit record |

Collection access is exposed through tools so scope, cursor and limits remain
explicit.

## MCP tools

### `personal_os.open_session`

Input:

- `agent_id`: stable Harness/Agent identifier
- `capabilities`: protocol features understood by the caller
- `purpose`: short reason for access

Returns a session ID and the granted capability subset.

### `personal_os.query_context`

Input:

- `session_id`
- optional goal, object-type and time filters
- `cursor` and `limit`

Returns a Context Bundle containing pinned references and redacted records.
The server applies local disclosure and sensitivity policy.

### `personal_os.get_object`

Input: `session_id` plus a pinned object reference.

Returns exactly that revision. Unpinned reads must explicitly request current
state and the returned reference is always pinned.

### `personal_os.submit_proposal`

Input: a Proposal Bundle conforming to
`schemas/personal-os-proposal-v0.schema.json`.

The call validates and stores a proposal in pending state. It does not activate
the strategy.

### `personal_os.submit_review`

Input: a Strategy Review Bundle conforming to
`schemas/personal-os-review-v0.schema.json`.

The Agent must submit through the same Harness identity and session that appear
in the bundle. Strategy, execution, outcome and optional feedback references
must be pinned. The review is stored as a draft; only the user can accept or
reject it.

### `personal_os.close_session`

Closes the audit session with a success or failure status.

## User-owned writes

The Android application, after explicit user confirmation, performs these
commands internally:

- accept, reject or edit a proposal;
- activate, complete or abandon a strategy;
- record execution;
- record outcome;
- accept a review and migrate useful rules into later strategy versions.

These are deliberately not Agent-authoritative MCP tools in v0.

## Offline compatibility

A Context Bundle can be exported as JSON and given to an Agent without a live
MCP connection. The Agent returns the same Proposal Bundle accepted by
`personal_os.submit_proposal`, and may return a Review Bundle accepted by
`personal_os.submit_review`. Both offline imports apply the same session,
identity and pinned-reference validation as live MCP. This is the compatibility path for Agents and
Harnesses that cannot connect to the Android MCP endpoint.

## Error model

All errors use:

```json
{
  "code": "stale_reference",
  "message": "The referenced goal revision is no longer current.",
  "retryable": false,
  "details": {}
}
```

Required codes: `invalid_request`, `unsupported_version`,
`session_closed`, `access_denied`, `not_found`, `stale_reference`,
`validation_failed`, and `internal_error`.

## Compatibility rules

- Unknown JSON fields must be ignored.
- Required fields cannot change within v0.
- Enum additions are allowed only when consumers preserve unknown values.
- Object revisions are immutable.
- The protocol identifies an Agent by capability, never by vendor SDK.
