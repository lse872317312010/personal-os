# B2-02 Controlled Source Entry

Status: contract-only, unverified

Base: PR #38 head b898a975ba4ea6242a7e8ccd98f3a953dab5a1ee

This dependent PR defines the smallest boundary for local media acquisition:

- system Photo Picker is the preferred native entry;
- camera is an explicitly separate capability;
- no READ_MEDIA_IMAGES, READ_EXTERNAL_STORAGE, or storage permission is added;
- native code owns picker/camera URIs, temporary files, provider handles, and
  cleanup;
- Dart receives only a bounded opaque source token or a stable allowlisted error;
- raw exceptions, paths, URIs, MIME-provider metadata, and camera output details
  must not cross the MethodChannel;
- AI/model invocation is out of scope.

The Kotlin file in this PR is a protocol and sanitizer test seam. It is not
registered in MainActivity yet, so this PR does not claim a working Android
picker or camera implementation. Registration and native lifecycle handling
must be a later PR with Android API-level tests and exact-commit device evidence.

## Method contract

| Method | Request | Success | Failure |
|---|---|---|---|
| capabilities | none | {photoPicker: bool, camera: bool} | source.unavailable |
| pickPhoto | none | {token: opaque} | allowlisted source.* |
| capturePhoto | none | {token: opaque} | allowlisted source.* |
| release | {token: opaque} | null | allowlisted source.* |

The token is a native capability handle, not a URI or file path. It must expire
or be released natively, and it must never be persisted as a durable user-data
reference.

## Not implemented

- actual ActivityResultContracts/GetContent/MediaStore Photo Picker registration;
- camera capture and FileProvider lifecycle;
- native token registry and expiry;
- conversion from the opaque token into encrypted Blob ingestion;
- real Android, Redmi Turbo, permission, or offline evidence;
- AI or model execution.
