# Personal OS Policy Core

Pure Dart, fail-closed policy decisions shared by every client and adapter.
It depends only on `personal_os_domain` and has no Flutter or storage imports.

Covered invariants:

- D4 data is rejected at processing and persistence boundaries.
- Derived sensitivity is at least the maximum input sensitivity and declared
  output floor.
- Consent is pinned to an exact revision and requires matching subject, actor,
  purpose, resource, action, sensitivity ceiling, active status, and time.
- Only a user actor may grant Consent or accept a Review.
- R2 requires explicit confirmation. In the MVP, R3 is always draft-only and
  cannot execute an external action even when the user has confirmed it;
  action-level confirmation is reserved for a future capability. R4 is always
  denied.
- Every result carries a stable, non-sensitive reason code for auditing.

Run from this directory:

```sh
dart pub get
dart test
dart analyze
```
