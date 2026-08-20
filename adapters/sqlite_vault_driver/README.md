# SQLite vault platform-driver contract

This package specifies the lifecycle boundary for a future encrypted local
database driver. It is pure Dart and has no production database dependency.
It does **not** implement or prove SQLite, SQLCipher, Android Keystore, hardware
backing, or encryption at rest.

The contract requires:

- opaque key leases, never a key encoded as `String`;
- open -> transactional safety PRAGMAs -> transactional migrations -> unlock;
- rekey in a transaction, with the old lease destroyed only after commit;
- failed unlock/rekey cleanup and stable, redacted public error codes;
- lock/close reference disposal and best-effort key zeroization;
- one contiguous, forward-only migration chain.

`VaultPragma` is an allowlist rather than arbitrary SQL so secrets cannot be
smuggled through logging-friendly text APIs. D4 admission belongs to the event
and persistence layers and is intentionally outside this driver contract.

Platform implementations must add integration tests against the exact database
build they ship before making any encryption claim.
