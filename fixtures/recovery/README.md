# Recovery protocol fixtures

These files exercise the state machine and stable error contract in
`architecture/RECOVERY_PROTOCOL.md`.

All values prefixed `synthetic-`, `fixture-`, or `TEST-ONLY-` are inert labels.
They are not keys, recovery codes, nonces, authentication tags, ciphertexts, or
recommended cryptographic parameters. A runner MUST NOT feed them to production
cryptography. Production code MUST reject `TEST-ONLY-SYNTHETIC-v1`.

The fixtures intentionally model wrong recovery code and corrupted ciphertext
with the same `RECOVERY_AUTH_FAILED` result. A runner passes only if it emits no
secret-derived diagnostics and never reaches `unlocked` on a rejected case.
