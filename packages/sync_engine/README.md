# Sync engine

Pure Dart trusted-device orchestration. It strictly encodes/decodes event
batches, authenticates envelope metadata through `SyncCryptographyPort`, and
atomically appends validated inbound batches. No cryptographic implementation
belongs in this package.
