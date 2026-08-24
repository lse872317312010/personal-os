# Personal OS Recovery

Pure Dart orchestration for Recovery Protocol v1. It deliberately contains no
KDF, AEAD, key storage, device binding, network, or database implementation.
Those security-sensitive capabilities are ports supplied by reviewed platform
adapters. `TEST-ONLY-SYNTHETIC-v1` belongs in tests only and is not a production
cryptographic suite.

The session is single-use and monotonic. It authenticates the package, binds a
new device, stages and applies revocations → account epoch → deletion
tombstones, then syncs and checks the vault before enabling business reads.
Staged security state is discarded only while active and before commit; a later
vault failure never rolls back an already committed security state. If staged
cleanup fails, the session returns the fixed
`RECOVERY_STAGED_STATE_CLEANUP_FAILED` code and never enables business reads.

Recovery code bytes are caller-provided, never logged, and zeroed after the
authentication call. Adapters receive a disposable copy rather than the
session's backing buffer; that copy is also wiped when authentication completes.
Calling `restore` transfers secret lifecycle responsibility to the session: every
exit path clears it, including malformed envelopes, local status gates, and
attempts to reuse a terminal session. `destroy` is idempotent so immediate and
outer cleanup may both run.

`RecoveryEnvelope` contains only Relay-visible fields. Recovery generation is
accepted exclusively from the authenticated inner payload. Package lifecycle
status and an optional package-ID binding live in the separate, trusted-local
`RecoveryPackageRecord`; neither is encoded into the outer envelope. Audit
records keep generation null until package authentication succeeds.
