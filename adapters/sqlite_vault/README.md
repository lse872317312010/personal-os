# SQLite Vault adapter — schema v1

This package freezes the driver-neutral storage contract for the local Vault.
It includes a driver-neutral event store over `SqlExecutor`, but deliberately
does **not** implement a concrete SQLite or SQLCipher driver yet.

## Guarantees

- immutable events, consent revisions, and deletion tombstones;
- globally unique `event_id` and indexed subject lookup;
- lossless subject references, including pinned revision and original order;
- event, subject links, projection update, and outbox enqueue share one write
  transaction;
- sensitivity is limited to `D0`–`D3`; `D4` cannot be persisted;
- no schema column stores a database key, wrapping key, recovery secret, API key,
  password, or token;
- blobs are referenced by opaque locator and ciphertext digest, never embedded
  in events;
- deletion targets use random, non-derived opaque tokens: never identifiers,
  deterministic hashes, or digests that permit re-identification/linkage;
- deletion propagation is an append-only log, not mutable tombstone state;
- blob integrity uses a digest of ciphertext only, never a plaintext/content
  digest;
- SQLCipher key material must be supplied by the platform security adapter and
  must never be written into this database.

## Files

- `migrations/0001_vault_schema.sql`: schema v1 migration.
- `lib/sqlite_vault_schema.dart`: pure-Dart constants and boundary validator.
- `test/sqlite_vault_schema_test.dart`: pure-Dart contract tests.
- `tool/validate_schema.py`: executable SQLite smoke test using Python's standard
  library. It validates the schema and atomic transaction shape, not SQLCipher
  encryption.

## Required runtime protocol

At database open, the future driver must:

1. obtain an already-unlocked database key from `security_api`;
2. apply the SQLCipher key through a parameter-safe native API (never logging or
   interpolating it into persisted SQL);
3. enable `foreign_keys`, choose WAL mode, and set an appropriate busy timeout;
4. verify `schema_metadata.schema_version` before accepting writes;
5. execute `SqliteVaultSchema.atomicAppendStatements` in one `BEGIN IMMEDIATE`
  transaction and roll back on any failure.

`target_token` must be generated with a cryptographically secure random source
and must not be derived from the deleted identifier. `ciphertext_digest` must be
computed after encryption. Neither value is a replacement for secret key
material.

`PRAGMA key` and WAL configuration are runtime responsibilities because they
cannot be safely or portably embedded in a migration file.
