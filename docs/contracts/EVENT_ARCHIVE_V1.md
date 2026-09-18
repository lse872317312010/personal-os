# Personal OS event archive v1

Status: implementation baseline  
Format token: `personal-os.events`  
Schema version: `1`

## Purpose

The archive is the lossless plaintext payload inside an authenticated,
encrypted Android backup. It is not itself a safe share format and must never
be written to public storage without the platform encryption adapter.

## Envelope

- `format`: fixed format token.
- `schema_version`: archive schema version.
- `event_count`: exact number of events.
- `events_sha256`: SHA-256 of the canonical JSON event array.
- `events`: events in durable append order, encoded with
  `EventEnvelopeJsonCodec`.

Object keys are sorted recursively before hashing and encoding. Array order is
preserved because event order is part of the asset history.

## Restore rules

A restore implementation must:

1. authenticate and decrypt the opaque Android backup;
2. verify format, schema, event count, checksum and every event envelope;
3. reject duplicate event IDs;
4. append the entire decoded history in one atomic store operation;
5. leave the target unchanged when any validation or append fails.

The restore service never merges or rewrites event meaning. Conflict handling
belongs to the event store, and silent partial recovery is forbidden.

## Security boundary

D4 data remains non-persistable and therefore cannot appear in an archive.
Existing event export policy still determines which lower-sensitivity events
may leave the vault. The archive codec neither weakens that policy nor exposes
keys, paths, sharing operations or plaintext storage APIs.
