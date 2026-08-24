# Blob engine

Pure Dart orchestration for trusted local encrypted blobs.

- `EncryptedBlobEngine` implements the public `BlobStore` boundary.
- `BlobIngestionContract` / `EncryptedBlobIngestion` is the frozen external
  input boundary: it validates Consent, sensitivity, and media type before
  listening to input, then forwards only a bounded stream to `BlobStore`.
- `EncryptedBlobIngestion` requires a positive `maxBytes`; over-limit input
  fails with the stable, redacted `payload_too_large` error. Callers provide a
  stream, never a path or URI.
- `BlobCryptographyPort` owns authenticated streaming cryptography and opaque
  blob keys. This package contains no production cipher.
- `CiphertextBlobRepository` stores only ciphertext and safe logical metadata.
- D4 is rejected before input consumption, key creation, or storage access.
- Failed puts abort partial ciphertext and destroy any newly-created key.
- Delete performs crypto-erasure first, then removes ciphertext.
- Logging accepts only fixed event values and cannot receive refs, paths,
  hashes, key identifiers, or exception messages.

Status: B2 encrypted-ingestion boundary frozen. Implementations must use an
`EncryptedBlobEngine` (or an equivalent encrypted `BlobStore`) behind
`EncryptedBlobIngestion`; this package has no plaintext or in-memory fallback.

Plaintext chunks are defensively copied and best-effort zeroized after the
cryptography boundary consumes them. Dart cannot guarantee compiler/runtime
zeroization; platform crypto adapters must minimize plaintext lifetime too.
