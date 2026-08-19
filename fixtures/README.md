# M1 machine-readable fixtures

These fixtures are implementation-independent inputs for future Dart, Rust, or
other test runners. JSON is the interchange format; no fixture relies on a
language-specific serializer.

## Layout

- `event_sequences/`: ordered inputs derived from `specs/EVENT_SEQUENCES.md`.
- `contract-fixture.schema.json`: structural schema for every sequence file.

## Runner contract

1. Read JSON as UTF-8 and preserve unknown object members.
2. Feed `events` to the system in array order (the audit/arrival order).
3. Interpret each `expectations.event_results` entry by `event_id`:
   `applied`, `ignored_duplicate`, `rejected`, `quarantined`, or `conflict`.
4. Compare the final projection only at the JSON Pointers listed in
   `expectations.projection_assertions`. Unlisted implementation metadata is
   deliberately unconstrained.
5. Treat timestamps as RFC 3339 instants. `occurred_at` is domain time;
   `recorded_at` plus input order is the stable audit order.
6. A missing optional field and JSON `null` are not automatically equivalent.

The `integrity` values are deterministic fixture markers, not production
cryptographic signatures. Payloads contain identifiers and synthetic metadata,
never raw D2/D3 content.

