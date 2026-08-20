# Personal OS Recovery

Pure Dart orchestration for Recovery Protocol v1. It deliberately contains no
KDF, AEAD, key storage, device binding, network, or database implementation.
Those security-sensitive capabilities are ports supplied by reviewed platform
adapters. `TEST-ONLY-SYNTHETIC-v1` belongs in tests only and is not a production
cryptographic suite.

The session is single-use and monotonic. It authenticates the package, binds a
new device, stages and applies revocations → account epoch → deletion
tombstones, then syncs and checks the vault before enabling business reads.
Recovery code bytes are caller-provided, never logged, and best-effort zeroed
immediately after the authentication call. Calling `restore` transfers secret
lifecycle responsibility to the session: every exit path clears it, including
malformed envelopes, local status gates, and attempts to reuse a terminal
session. `destroy` is idempotent so immediate and outer cleanup may both run.

`RecoveryEnvelope` contains only Relay-visible fields. Recovery generation is
accepted exclusively from the authenticated inner payload. Package lifecycle
status and an optional package-ID binding live in the separate, trusted-local
`RecoveryPackageRecord`; neither is encoded into the outer envelope. Audit
records keep generation null until package authentication succeeds.
