# Sync engine

Pure Dart trusted-device orchestration. It strictly encodes/decodes event
batches, authenticates envelope metadata through `SyncCryptographyPort`, and
atomically appends validated inbound pages. A page is prepared in memory first;
if any envelope is rejected, the page cursor, sender sequence state, and all
prepared events remain unchanged. Duplicate delivery is accepted only for an
already-known envelope ID; a durable sequence number alone is not sufficient to
prove replay identity. Reusing an accepted sequence with a new envelope ID is
rejected.

Inbound D4 events are rejected before storage. Failures are returned as stable
reason codes and never include transport, native, SQL, key, or exception
details. No cryptographic implementation belongs in this package.
