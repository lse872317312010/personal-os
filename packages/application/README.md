# application

Pure Dart orchestration layer. It owns commands, queries, and use cases while
depending only on domain/event contracts and abstract ports.

The first vertical slice is `AnalyzeAppearanceUseCase`:

1. authorize D3 appearance analysis (fail closed);
2. request provider-neutral analysis for a durable image reference;
3. translate findings/actions into immutable M1 lifecycle events;
4. atomically append claims, a goal, a draft plan, and planned tasks.

No Flutter, Android, filesystem, SQLite, HTTP, or model-vendor type belongs in
this package. Adapters implement the ports at the composition root.

