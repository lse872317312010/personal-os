# B2-02 Controlled Source Entry

Status: implemented wiring, runtime/device unverified

Base: `main` at `6d23063c5059174240338a6be11d37949fefbab0`

The Android secure composition now implements the controlled source boundary:

- system Photo Picker is a native entry and requests no media/storage
  permission;
- Camera capture is a native entry that requests `android.permission.CAMERA`
  explicitly when capture starts;
- Camera output is written to an app-private cache file exposed only through a
  non-exported Android `FileProvider`; the `Uri`, file, provider metadata, and
  bytes stay native;
- both entries become short-lived opaque source tokens; Dart never receives a
  URI or path;
- native consumption streams through the native Vault blob sink and returns an
  opaque `BlobRef` only;
- cancellation, denial, failed capture, release/expiry, session invalidation,
  and channel teardown clean up the native temporary source; cleanup failure
  returns a stable error, and cleanup failure after blob ingestion deletes the
  stored blob as rollback;
- Dart records the observation and invokes the existing analysis use case with
  that reference;
- raw bytes, paths, URIs, provider metadata, and exception details do not cross
  the MethodChannel.

This is a code contract and wiring claim only. The current capability reports
`camera: true`, and `capturePhoto` follows the explicit permission → native
FileProvider cache → opaque token → native blob sink flow with cleanup/rollback
on failure. Android compile/API-level/runtime, Redmi, offline, production, and
exact-commit device evidence are still pending. The current model gateway is a
deterministic synthetic fixture, not production AI or proof that a person was
analyzed.

## Method contract

| Method | Request | Success | Failure |
|---|---|---|---|
| capabilities | none | `{photoPicker: bool, camera: bool}` | `source.unavailable` |
| pickPhoto | none | `{token: opaque}` | allowlisted `source.*` |
| capturePhoto | none | explicit camera permission → native FileProvider cache → opaque token | allowlisted `source.*`; cleanup/rollback failures are stable errors |
| consume | `{token: opaque}` | `{blobRef: opaque}` | allowlisted `source.*` |
| release | `{token: opaque}` | null | allowlisted `source.*` |

The token is a native capability handle, not a URI or file path. It expires or
is released natively and is never persisted as a durable user-data reference.
