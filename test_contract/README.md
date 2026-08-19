# M1 contract-test runner checklist

This directory defines how implementations consume the language-neutral files
under `fixtures/`. The normative behavior remains in `specs/`; fixtures make a
first executable slice of it concrete.

## Minimal runner

- [ ] Parse every `fixtures/event_sequences/*.json` without loss.
- [ ] Validate each file against `fixtures/contract-fixture.schema.json`.
- [ ] Replay the event array in arrival order and collect one stable result per
  input occurrence.
- [ ] Resolve JSON Pointer assertions against a canonical projection.
- [ ] Compare JSON structurally: object key order is irrelevant; array order and
  JSON number values are significant.
- [ ] Replay twice from empty state and compare canonicalized projections.
- [ ] Run the same corpus against Dart and Rust adapters when both exist.
- [ ] Report unsupported tests as skipped with a reason; never count them as
  passed.

Recommended command contract for future runners:

```text
contract-test --manifest test_contract/manifest.json --adapter <adapter-name>
```

Exit `0` only when all selected assertions pass. Test output must not include
D2/D3 payload copies.

## Initial coverage map

| Contract tests | Initial executable evidence | Remaining work |
|---|---|---|
| CT-001–005 | S1 deterministic replay; S4 duplicate | snapshot, unknown-field and unknown-version fixtures |
| CT-101–105 | S1 legal transitions and active-plan invariant | transition matrix and invalid-transition fixtures |
| CT-201–207 | S4 late event/conflict; S2 fixed revision | concurrent-revision pair fixtures |
| CT-301–307 | S1 valid consent; S3 revoked consent | expiry, scope, D4, actor, R3, sensitivity fixtures |
| CT-351–355 | Schema file establishes versioned envelope | upcaster and quarantine fixture generations |
| CT-401–406 | S2 revision; S3 complete deletion | partial deletion and unavailable-reference fixtures |
| CT-501–504 | S1, S2, S3, S4 | fully represented in first corpus |

`manifest.json` is the machine-readable inventory and explicitly identifies
which tests have direct fixtures versus planned coverage. A fixture reference is
evidence for a test, not permission to omit its other assertions from the prose
contract.

## Cross-language determinism

Canonical result documents should be serialized using RFC 8785 JSON
Canonicalization Scheme before byte comparison. Implementations may use native
domain objects internally, but fixture IDs, reason codes, JSON Pointer paths,
and enum strings cross the adapter boundary unchanged.

Do not place runtime databases, generated snapshots, keys, images, or user data
in these directories.

