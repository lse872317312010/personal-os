# sync_api

Pure Dart boundaries for encrypted device synchronization.

`SyncPort` is the untrusted Relay boundary. It transfers only
`EncryptedSyncEnvelope`, opaque cursors, device sequence metadata, ciphertext,
and signatures. It deliberately does not depend on `events` or `domain` and
does not expose event type, object ID, sensitivity, consent, timestamps, or
payload fields.

`SyncCryptographyPort` is a separate trusted-device boundary used by the local
SyncWorker. The worker owns business-event encoding and validation; the crypto
adapter only seals/opens bytes. Relay adapters must implement `SyncPort` only.

## Migration from 0.0.1

- Replace `List<EventEnvelope>` with `List<EncryptedSyncEnvelope>`.
- Replace raw `String` cursors with `OpaqueSyncCursor`.
- Replace `acceptedEventIds` with `acceptedEnvelopeIds`.
- Encode and encrypt batches locally before calling `SyncPort.push`.

Byte buffers and result collections are defensively copied. Diagnostics redact
ciphertext, signatures, and cursor values.
