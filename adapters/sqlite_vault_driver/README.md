# SQLite vault platform-driver contract

This package specifies the lifecycle boundary for a future encrypted local
database driver. It is pure Dart and has no production database dependency.
It does **not** implement or prove SQLite, SQLCipher, Android Keystore, hardware
backing, or encryption at rest.

The contract requires:

- opaque key leases, never a key encoded as `String`;
- serialized `unlock`, `rekey`, `lock`, and `close` operations, including
  cleanup, so concurrent callers cannot cross lifecycle boundaries;
- open -> transactional safety PRAGMAs -> transactional migrations -> unlock;
- rekey in a transaction, with the old lease destroyed only after commit;
- failed unlock/rekey rollback cleanup and stable, redacted public error
  codes;
- lock/close reference disposal and best-effort key zeroization;
- explicit terminal `closed` state; `close` and `lock` are idempotent after
  teardown, while `unlock` and `rekey` return `vault_closed`;
- one contiguous, forward-only migration chain that fails closed rather than
  jumping over a schema version.

The public failure values are centralized in `VaultDriverFailureCode`. Native
or provider exceptions are never returned by the driver; they are converted to
`vault_unlock_failed` or `vault_rekey_failed` and all cleanup remains
best-effort and fail-closed.

`VaultPragma` is an allowlist rather than arbitrary SQL so secrets cannot be
smuggled through logging-friendly text APIs. D4 admission belongs to the event
and persistence layers and is intentionally outside this driver contract.

Platform implementations must add integration tests against the exact database
build they ship before making any encryption claim.

## Status

This is a pure-Dart lifecycle contract and test fixture. It does not expose key
bytes, filesystem paths, provider aliases, or native error text. The adapter's
serialization, rollback cleanup, rekey ordering, and migration boundaries are
covered by the package tests; platform encryption remains unimplemented and
requires separate integration verification.
