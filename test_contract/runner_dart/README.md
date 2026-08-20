# Dart contract fixture runner

This package decodes the language-neutral M1 fixtures and executes only the
slice implemented by the current Dart reducer and in-memory adapter.
Every decoded event also passes the current persistence policy gate before it
can reach storage.

```sh
dart pub get
dart test
dart run bin/contract_test.dart --manifest ../manifest.json
```

The command writes exactly one stable JSON document to stdout. It exits `1`
only for real failures and `64` for invalid CLI usage. A corpus containing
honestly reported `unsupported` checks exits `0`, so unsupported coverage is
visible without being misreported as passing evidence.

## Compatibility boundary

The fixtures use compact references (`claim:CL1@1`) and actor types predating
the Dart envelope. The decoder maps model actors to agents, device actors to
connectors, supplies fixture authority metadata, and aliases fixture
`execution_ref` to the reducer's `execution_record_ref`. Original payload keys
remain present.

The reducer now covers the complete event-type vocabulary used by S1-S4. The
runner still reports an event as `unsupported` when an isolated fixture needs a
prior projection/seed that it cannot construct. Each fixture containing JSON
Pointer projection assertions or cross-object invariants also receives an
explicit `<fixture-assertions>` unsupported check. Therefore a successful
lifecycle transition is not evidence that Consent history, traceability,
deletion side effects, active-plan invariants, or late-event replay passed.

The runner does not yet evaluate those higher-level assertions or RFC 8785
canonicalization. These limitations are machine-visible and never counted as
passes.

No event payload is emitted in the report, preventing D2/D3 fixture content
from being copied to logs.
