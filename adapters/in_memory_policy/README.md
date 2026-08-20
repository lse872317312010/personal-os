# In-memory policy adapter

Test and spike implementations used by the Flutter composition root before a
durable encrypted consent store is connected.

```dart
final consents = InMemoryConsentRevisionRepository(
  initialGrants: [consentRevision],
);
final policy = AppearancePolicyAdapter(
  consents: consents,
  clock: FixedPolicyClock(DateTime.utc(2026, 8, 20, 12)),
);
```

## Guarantees

- lookup is exact by `consentId + revision`;
- a missing revision returns `null` and never falls back to latest;
- stored revisions are append-only and cannot be replaced;
- inputs and reads are immutable value snapshots;
- revoked, superseded, future, and expired grants are returned unchanged so
  the policy layer remains the sole authorization authority;
- `FixedPolicyClock` makes validity-boundary tests deterministic.

This adapter is intentionally non-durable and must not be used as the
production consent store.
