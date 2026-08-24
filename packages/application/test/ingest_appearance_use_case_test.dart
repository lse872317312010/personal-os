import 'package:personal_os_application/application.dart';
import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final actor = ActorRef(
    actorId: 'user-1',
    actorType: ActorType.user,
    authoritySource: 'local-session',
  );
  final consent = ObjectRef(type: 'consent', id: EntityId('consent-1'));
  final access = BlobAccessContext(
    actorRef: 'user:owner',
    purpose: 'appearance-analysis',
    consentRef: 'consent:appearance-v1',
  );

  IngestAppearanceAnalysisUseCase _buildUseCase(
    _Ingestion ingestion,
    _Store store,
    _Model model,
  ) =>
      IngestAppearanceAnalysisUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
        analyzeAppearance: AnalyzeAppearanceUseCase(
          eventStore: store,
          modelGateway: model,
          policy: const _Policy(),
          ids: _Ids(),
          clock: _Clock(),
        ),
      );

  IngestAppearanceAnalysisCommand _buildCommand(Stream<List<int>> bytes) =>
      IngestAppearanceAnalysisCommand(
        bytes: bytes,
        mediaType: 'image/jpeg',
        access: access,
        profileId: EntityId('profile-1'),
        observationContext: 'profile appearance capture',
        consentRef: consent,
        actor: actor,
        correlationId: 'corr-appearance',
      );

  test('success emits only opaque refs', () async {
    final ingestion = _Ingestion();
    final store = _Store();
    final model = _Model();
    final result = await _buildUseCase(ingestion, store, model).execute(
      _buildCommand(Stream<List<int>>.value(<int>[1, 2, 3])),
    );

    expect(result.blobRef, BlobRef('blob://opaque-1'));
    expect(ingestion.bytes, <int>[1, 2, 3]);
    expect(model.inputs.single.imageRef, 'blob://opaque-1');
    expect(store.events, hasLength(5));
    for (final event in store.events) {
      expect(
          _flatten(event.payload),
          everyElement(isNot(anyOf(
            contains('/tmp/'),
            contains('file://'),
            contains('raw-image'),
            contains('adapter-secret'),
          ))));
      expect(event.payload.values, everyElement(isNot(isA<List<int>>())));
    }
    expect(
      store.events.first.payload,
      containsPair('blob_ref', 'blob://opaque-1'),
    );
    expect(
      store.events
          .where((event) => event.eventType == EventTypes.claimProposed),
      everyElement(
        predicate<EventEnvelope>(
          (event) => event.payload['evidence_blob_ref'] == 'blob://opaque-1',
        ),
      ),
    );
  });

  test('ingestion failure does not append', () async {
    final ingestion = _Ingestion()
      ..failure = const BlobIngestionException('ingestion_failed');
    final store = _Store();
    await expectLater(
      _buildUseCase(ingestion, store, _Model()).execute(
        _buildCommand(Stream<List<int>>.value(<int>[9])),
      ),
      throwsA(isA<BlobIngestionException>().having(
        (error) => error.code,
        'code',
        'ingestion_failed',
      )),
    );
    expect(store.events, isEmpty);
  });

  test('repeated execution uses fresh opaque refs', () async {
    final ingestion = _Ingestion()..incrementRefs = true;
    final store = _Store();
    final model = _Model();
    final useCase = _buildUseCase(ingestion, store, model);
    await useCase.execute(_buildCommand(Stream<List<int>>.value(<int>[4])));
    await useCase.execute(_buildCommand(Stream<List<int>>.value(<int>[5])));

    expect(ingestion.refs, <BlobRef>[
      BlobRef('blob://opaque-1'),
      BlobRef('blob://opaque-2'),
    ]);
    expect(model.inputs.map((input) => input.imageRef), <String>[
      'blob://opaque-1',
      'blob://opaque-2',
    ]);
    expect(
      store.events.every(
        (event) => event.payload.values.every((value) => value is! List<int>),
      ),
      isTrue,
    );
  });

  test('analysis failure rolls back the ingested blob', () async {
    final ingestion = _Ingestion();
    final store = _Store();
    final model = _Model()..failure = StateError('adapter-secret /tmp/db');
    await expectLater(
      _buildUseCase(ingestion, store, model).execute(
        _buildCommand(Stream<List<int>>.value(<int>[7])),
      ),
      throwsA(isA<AppearanceUseCaseFailure>().having(
        (error) => error.code,
        'code',
        AppearanceFailureCode.analysisFailed,
      )),
    );
    expect(ingestion.discarded, <BlobRef>[BlobRef('blob://opaque-1')]);
    expect(store.events, hasLength(1));
  });

  test('discard failure preserves the stable application error', () async {
    final ingestion = _Ingestion()..discardFailure = StateError('/tmp/sql');
    final store = _Store();
    final model = _Model()..failure = StateError('adapter failure');
    await expectLater(
      _buildUseCase(ingestion, store, model).execute(
        _buildCommand(Stream<List<int>>.value(<int>[8])),
      ),
      throwsA(isA<AppearanceUseCaseFailure>().having(
        (error) => error.code,
        'code',
        AppearanceFailureCode.analysisFailed,
      )),
    );
    expect(ingestion.discardCalls, 1);
  });

}

Iterable<Object?> _flatten(Object? value) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _flatten(entry.key);
      yield* _flatten(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      yield* _flatten(item);
    }
  } else {
    yield value;
  }
}

final class _Ingestion implements BlobIngestionContract, BlobIngestionRollback {
  BlobRef ref = BlobRef('blob://opaque-1');
  Exception? failure;
  Exception? discardFailure;
  bool incrementRefs = false;
  int calls = 0;
  int discardCalls = 0;
  final List<int> bytes = <int>[];
  final List<BlobRef> refs = <BlobRef>[];
  final List<BlobRef> discarded = <BlobRef>[];

  @override
  Future<BlobRef> ingest({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    await for (final chunk in bytes) {
      this.bytes.addAll(chunk);
    }
    final value = incrementRefs ? BlobRef('blob://opaque-$calls') : ref;
    refs.add(value);
    return value;
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {
    discardCalls++;
    if (discardFailure != null) throw discardFailure!;
    discarded.add(ref);
  }
}

final class _Model implements AppearanceAnalysisGateway {
  Exception? failure;
  final List<AppearanceAnalysisInput> inputs = <AppearanceAnalysisInput>[];

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    inputs.add(input);
    if (failure != null) throw failure!;
    return AppearanceAnalysisResult(
      findings: <AppearanceFinding>[
        AppearanceFinding(
          dimension: 'hair',
          statement: 'synthetic',
          confidence: .8,
        ),
      ],
      actions: <AppearanceActionSuggestion>[
        AppearanceActionSuggestion(title: 'review', rationale: 'synthetic'),
      ],
      modelTraceRef: 'synthetic-trace',
    );
  }
}

final class _Store implements EventStore {
  final List<EventEnvelope> events = <EventEnvelope>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    this.events.addAll(events);
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async =>
      events.where((event) => event.eventId == eventId).firstOrNull;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      events
          .where((event) => event.subjectRefs.contains(subject))
          .take(limit ?? events.length)
          .toList();
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String nextId(String namespace) => '$namespace-${++value}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 1, 1);
}

final class _Policy implements AppearancePolicyPort {
  const _Policy();

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
  }) async =>
      const PolicyVerdict.allow();
}
