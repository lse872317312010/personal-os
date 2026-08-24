# ADR-0012 — Sync Envelope Format (v1)

**Status**: accepted (wire contract only; cryptographic implementation pending)
**Date**: 2026-08-24
**Tracks**: A · Core Contract
**Refines**: `packages/sync_api/lib/src/sync_port.dart` (`EncryptedSyncEnvelope`) and `architecture/SYNC_PROTOCOL.md` § Sync Envelope

## 背景

The previous draft mixed a JSON wire representation with an underspecified
"canonical bytes" expression. In particular, it did not say whether Ed25519
signs a textual concatenation, its SHA-256 digest, or the JSON serialization.
That ambiguity would make independent Dart, Go, Python, and Rust relays
incompatible.

This ADR freezes the v1 wire shape and the signing preimage. It does not claim
that the current MVP has a production relay, a trusted device-key registry, or
Ed25519 verification. Those remain implementation work.

## 决定

### 1. JSON wire shape

The relay transport uses JSON with these required fields:

```json
{
  "protocol_version": 1,
  "envelope_id": "<uuid v4 string>",
  "account_pseudonym": "<opaque non-PII string>",
  "sender_device_id": "<device id string>",
  "recipient_epoch": "<epoch label string>",
  "sequence": { "first": 0, "last": 7 },
  "ciphertext_length": 32,
  "ciphertext": "<base64 of ciphertext bytes>",
  "signature": "<base64 of exactly 64 signature bytes>"
}
```

Unknown top-level fields are tolerated for forward compatibility. Required fields
may not be omitted. `ciphertext_length` is the decoded byte count, not the
base64 character count. Empty ciphertext and empty signatures are invalid.

The relay may validate the envelope shape without being able to authenticate
it. Authentication requires resolving `sender_device_id` to a trusted public
key in a device registry outside this envelope.

### 2. Metadata boundary

Business fields remain inside `ciphertext`. The JSON metadata must not contain
event type, object or subject identifiers, timestamps, sensitivity, consent
references, correlation IDs, or event payloads.

The v1 wire contract accepts metadata leakage from ciphertext length, sequence
range, and a stable account pseudonym. Padding and pseudonym rotation are
future protocol work.

### 3. Canonical signing bytes (unambiguous)

The Ed25519 message is the byte sequence named `canonical_preimage_v1` below.
Ed25519 signs these bytes directly. There is **no implicit JSON serialization,
delimiter escaping, or SHA-256 step** in the signing input.

All integer values are unsigned big-endian. Text values are UTF-8 encoded exactly
as represented by the JSON string; no Unicode normalization is performed by this
contract. `u32be(n)` and `u64be(n)` mean fixed-width 4- and 8-byte
unsigned big-endian integers.

```text
canonical_preimage_v1 =
  ASCII("personal-os/sync-envelope/v1") ||
  u32be(protocol_version) ||
  u32be(byte_length(UTF8(envelope_id))) ||
  UTF8(envelope_id) ||
  u32be(byte_length(UTF8(account_pseudonym))) ||
  UTF8(account_pseudonym) ||
  u32be(byte_length(UTF8(sender_device_id))) ||
  UTF8(sender_device_id) ||
  u32be(byte_length(UTF8(recipient_epoch))) ||
  UTF8(recipient_epoch) ||
  u64be(sequence.first) ||
  u64be(sequence.last) ||
  u64be(ciphertext_length) ||
  ciphertext_bytes
```

The four text length prefixes make field boundaries unambiguous even when a
future implementation permits punctuation or non-ASCII metadata. The final
ciphertext byte count must equal `ciphertext_length`. A signer signs
`canonical_preimage_v1` with Ed25519; the resulting 64 bytes are encoded in
the JSON `signature` field.

A SHA-256 digest of the canonical preimage may be printed by tooling as a
diagnostic test-vector aid. That digest is **not** the signature and matching it
does not prove authenticity.

### 4. Verification responsibility and current limitation

A production relay/device adapter must:

1. resolve `sender_device_id` to a currently trusted Ed25519 public key;
2. reconstruct `canonical_preimage_v1` from the parsed envelope;
3. verify the 64-byte signature against that trusted key;
4. reject verification failures before accepting or forwarding the envelope.

The repository contract validator in this phase performs only structural checks
and canonical-preimage derivation. It deliberately does not verify Ed25519,
because no production key registry or cryptography adapter exists yet.
Synthetic fixtures use a 64-byte zero signature and are always labelled
`unverified`.

### 5. Versioning and cursor

`protocol_version=1` is required for this wire contract. A required-field
semantic or type change requires version 2; optional unknown fields may be added
without a version bump. Required fields are not silently deleted.

`OpaqueSyncCursor` is returned by the relay and must be round-tripped without
client parsing. If a relay invalidates old cursors, it returns
`cursor_invalidated` and the client starts from `OpaqueSyncCursor.initial()`.

### 6. Boundary with export and recovery packages

A Sync Envelope is an encrypted event transport object, not a vault export or
recovery package. It must never contain a keystore master key, epoch key,
recovery code, or business plaintext. Export and recovery contracts have
separate formats and lifecycle rules.

## 影响与后续工作

This ADR is sufficient for independent implementations to produce identical
signing bytes, but it does not make those implementations available in the MVP.
The following work is explicitly pending:

- add a trusted-device public-key registry and an adapter-neutral verification
  port;
- implement Ed25519 signing/verification behind that port;
- add a real signed test vector generated by the production adapter;
- add relay acceptance tests for signature failure, revoked devices, and epoch
  mismatch.

Until those items land, CI may report only `SYNC_ENVELOPE_SCHEMA=pass` and
`SYNC_ENVELOPE_SIGNATURE=unverified`. It must not report a verified
signature, a production relay, or cryptographic evidence.

## 参照

- ADR-0003 — local-authoritative encrypted hybrid architecture
- ADR-0005 — offline recovery package and trusted device migration
- `architecture/SYNC_PROTOCOL.md` — sync protocol proposal v0.1
- `packages/sync_api/lib/src/sync_port.dart` — Dart envelope shape
