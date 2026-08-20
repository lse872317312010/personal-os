# In-memory encrypted relay

`InMemoryRelay` is a deterministic `SyncPort` adapter for tests and vertical
spikes. It stores only `EncryptedSyncEnvelope` values and treats ciphertext as
opaque bytes.

## Guarantees

- `envelope_id` is idempotent within an account: retry acknowledgement does
  not duplicate data, while equal opaque IDs in different accounts cannot
  interfere with one another.
- Cursors are opaque capabilities; clients cannot use arbitrary offsets.
- Pull supports bounded pagination and stable insertion order.
- Sender sequence gaps are observable as transport diagnostics, never given
  business meaning and never silently repaired.
- Revoked devices are denied before new pushes are stored.
- Unregistered devices are denied. Control-plane registration binds each
  device to exactly one account pseudonym.
- Pushes are rejected atomically on account mismatch; pulls expose only the
  registered account's log, and cursors cannot be reused across accounts.
- Ingress and egress use defensive copies, including ciphertext/signatures.
- The adapter has no dependency on `events` or `domain`.

## Deliberate privacy boundary

The implementation contains no `EventEnvelope`, event type, object ID,
sensitivity, consent, appearance-analysis field, reducer, or decryption key.
It does not inspect plaintext and cannot make domain decisions. Its only
runtime dependency is `personal_os_sync_api`.

This is an in-memory test adapter, not a durable or network-accessible relay.
