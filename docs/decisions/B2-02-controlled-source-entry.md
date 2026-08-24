# B2-02 Controlled Source Entry

Status: implemented wiring, runtime/device unverified

Base: `main` at `bddbecd2ba8b10a6427c8661d402f5d8c8c2865a`

The Android secure composition now implements the controlled source boundary:

- system Photo Picker is the native entry and requests no media/storage
  permission;
- the selected `Uri` stays native and becomes a short-lived opaque token;
- native consumption streams through the native Vault blob sink and returns an
  opaque `BlobRef` only;
- Dart records the observation and invokes the existing analysis use case with
  that reference;
- raw bytes, paths, URIs, provider metadata, and exception details do not
  cross the MethodChannel.

This is a code contract and wiring claim only. Camera remains unavailable:
the current capability reports `camera: false` and `capturePhoto` fails closed.
Android API-level, runtime, Redmi, offline, and exact-commit device evidence
are still pending. The current model gateway is a deterministic synthetic
fixture, not production AI or proof that a person was analyzed.

## Method contract

| Method | Request | Success | Failure |
|---|---|---|---|
| capabilities | none | `{photoPicker: bool, camera: bool}` | `source.unavailable` |
| pickPhoto | none | `{token: opaque}` | allowlisted `source.*` |
| capturePhoto | none | unavailable in current implementation | allowlisted `source.*` |
| consume | `{token: opaque}` | `{blobRef: opaque}` | allowlisted `source.*` |
| release | `{token: opaque}` | null | allowlisted `source.*` |

The token is a native capability handle, not a URI or file path. It expires or
is released natively and is never persisted as a durable user-data reference.
