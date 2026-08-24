# storage_api

Pure Dart persistence ports. Implementations may use SQLite, encrypted files,
or memory, but those details cannot cross this boundary.

`EventStore.appendAll` is atomic and ordered. The API deliberately exposes no
update/delete operation because M1 events are immutable.

Blob deletion does not alter that event log: events retain an opaque `BlobRef`
and projections must tolerate a missing blob.

## Event export security contract

`EventExportPort` is a read-only port over immutable `EventEnvelope` values. It
does not expose append, update, delete, filesystem/share, or plaintext
serialization operations.

- Every request must provide an explicit `EventExportPolicy` with a maximum
  sensitivity. D4 is rejected independently and cannot be exported.
- Events are validated before an adapter receives them. Payloads, integrity
  fields, and extensions must not contain raw keys, key aliases, secrets,
  passwords, tokens, paths, URIs, URLs, digests, or content hashes.
- The result is `OpaqueEventExport`: callers receive only a defensive copy of
  opaque bytes and safe envelope metadata (format, schema, count, sensitivity
  ceiling, and creation time).
- Metadata deliberately excludes event IDs, subject IDs, paths, hashes, key
  identifiers, SQL details, and content-derived fields.
- This package does not implement encryption, a filesystem, sharing, or a
  plaintext fallback. A production adapter must produce authenticated,
  encrypted bytes and prove that behavior separately on the target platform.

## BlobStore security contract

- Reads and writes are streaming. Implementations must keep memory bounded and
  failed writes must not publish partial blobs.
- `BlobRef` must never encode a file path, URI, plaintext/content hash,
  encryption key, or key identifier. Its encoded token must not be logged.
- `BlobMetadata` is intentionally narrow. Adapters must not add paths, hashes,
  key material, EXIF, or other content-derived metadata.
- Every operation requires an auditable `BlobAccessContext` containing actor,
  purpose, and optional consent reference. The context has no D4 permission.
- D4 is permanently forbidden from processing and persistence. Every adapter
  must call `validateBlobPersistenceSensitivity` before consuming the input
  stream. D4 always throws `BlobAccessDenied` with the stable code
  `D4_PERSISTENCE_FORBIDDEN`.
- No consent, actor, purpose, capability, policy result, adapter configuration,
  or future extension may bypass the D4 persistence rejection. This is a data
  invariant, not an authorization decision.
- `delete` is idempotent and removes or cryptographically erases the primary
  object and adapter-managed partials. Other derived artifacts have their own
  lifecycle command.
- A byte range is only a performance hint; integrity and authorization checks
  still apply.

Adapter contract tests should cover bounded-memory streaming, interrupted
writes, authenticated-read failure, unconditional D4 denial, range boundaries, repeated
deletion, and absence of forbidden data in refs, metadata, and logs.
