# model_fixture

Deterministic `AppearanceAnalysisGateway` for tests and UI demos. It enables the
appearance action loop without bundling a model or sending personal data away
from the device.

## Safety boundary

- accepts only non-empty opaque `blob://...` references;
- never opens the blob and has no filesystem or network dependency;
- performs no image processing and makes no claim about a real person;
- labels every fixture finding/action as synthetic;
- derives a stable trace reference from the request without exposing the blob
  reference in that trace.

This adapter must not be presented as a production analysis provider.

## Usage

```dart
const gateway = FixtureAppearanceAnalysisGateway();
final result = await gateway.analyze(
  AppearanceAnalysisInput(
    imageRef: 'blob://vault/demo-photo',
    observationContext: 'demo only',
  ),
);
```

Set `behavior` to `emptyResult` to exercise incomplete-result handling, or to
`failure` (with an optional `failureMessage`) to exercise provider failures.

Run `dart test` from this directory. The workspace `tool/check_dart_core.sh`
also discovers this package automatically.
