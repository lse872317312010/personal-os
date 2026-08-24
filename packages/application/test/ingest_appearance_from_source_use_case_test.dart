import 'package:personal_os_application/application.dart';
import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final source = OpaqueSourceToken('source_token_0001');
  final consent = ObjectRef(type: 'consent', id: EntityId('consent-1'));
  final access = BlobAccessContext(
    actorRef: 'user:owner',
    purpose: 'appearance-analysis',
    consentRef: 'consent:appearance-v1',
  );
  final actor = ActorRef(
    actorId: 'user-1',
    actorType: ActorType.user,
    authoritySource: 'local-session',
  );

  IngestAppearanceFromSourceUseCase _buildUseCase(
    _SourceIngestion ingestion,
    _Store store,
    _Model model,
  ) =>
      IngestAppearanceFromSourceUseCase(
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

  IngestAppearanceFromSourceCommand _buildCommand() =>
      IngestAppearanceFromSourceCommand(
        source: source,
        mediaType: 'image/jpeg',
        access: access,
        profileId: EntityId('profile-1'),
        observationContext: 'profile appearance capture',
        consentRef: consent,
        actor: actor,
        correlationId: 'corr-appearance-source',
      );

  test('success passes only token in and BlobRef into events and analysis',
      () async {
    final ingestion = _SourceIngestion();
    final store = _Store();
    final model = _Model();

    final result = await _buildUseCase(ingestion, store, model).execute(_buildCommand());

    expect(result.blobRef, BlobRef('blob://opaque-source-1'));
    expect(ingestion.sources, [source]);
    expect(model.inputs.single.imageRef, 'blob://opaque-source-1');
    expect(store.events, hasLength(5));
    expect(
      store.events.expand((event) => _flatten(event.payload)),
      everyElement(isNot(anyOf(
        contains('source_token'),
        contains('/tmp/'),
        contains('file://'),
        contains('provider'),
        contains('raw-image'),
      ))),
    );
    expect(
      store.events.every(
        (event) => event.payload.values.every((value) => value is! List<int>),
      ),
      isTrue,
    );
  });

  test('expired source fails before analysis and appends nothing', () async {
    final ingestion = _SourceIngestion()
      ..failure = const SourceBlobIngestionException('source_expired');
    final store = _Store();

    await expectLater(
      _buildUseCase(ingestion, store, _Model()).execute(_buildCommand()),
      throwsA(isA<SourceBlobIngestionException>().having(
        (error) => error.code,
        'code',
        'source_expired',
      )),
    );
    expect(store.events, isEmpty);
  });

  test('D4 source request is rejected before native ingestion', () async {
    final ingestion = _SourceIngestion()
      ..failure =
          const SourceBlobIngestionException('d4_persistence_forbidden');
    final store = _Store();

    await expectLater(
      _buildUseCase(ingestion, store, _Model()).execute(_buildCommand()),
      throwsA(isA<SourceBlobIngestionException>().having(
        (error) => error.code,
        'code',
        'd4_persistence_forbidden',
      )),
    );
    expect(ingestion.sources, isEmpty);
    expect(store.events, isEmpty);
  });

  test('analysis failure rolls back the encrypted BlobRef', () async {
    final ingestion = _SourceIngestion();
    final store = _Store();
    final model = _Model()..failure = StateError('raw exception /tmp/path');

    await expectLater(
      _buildUseCase(ingestion, store, model).execute(_buildCommand()),
      throwsA(isA<AppearanceUseCaseFailure>().having(
        (error) => error.code,
        'code',
        AppearanceFailureCode.analysisFailed,
      )),
    );
    expect(ingestion.discarded, [BlobRef('blob://opaque-source-1')]);
    expect(store.events, hasLength(1));
  });

}

Iterable<Object?> _flatten(Object? value) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _flatten(entry.key);
      yield* _flatten(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) yield* _flatten(item);
  } else {
    yield value;
  }
}

final class _SourceIngestion implements SourceBlobIngestionPort {
  SourceBlobIngestionException? failure;
  final List<OpaqueSourceToken> sources = <OpaqueSourceToken>[];
  final List<BlobRef> discarded = <BlobRef>[];

  @override
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    if (failure != null) throw failure!;
    sources.add(source);
    return BlobRef('blob://opaque-source-1');
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {
    discarded.add(ref);
  }
}

final class _Model implements AppearanceAnalysisGateway {
  Exception? failure;
  final List<AppearanceAnalysisInput> inputs = <AppearanceAnalysisInput>[];

  @override
  Future<AppearanceAnalysisResult> analyze(
    AppearanceAnalysisInput input,
  ) async {
    inputs.add(input);
    if (failure != null) throw failure!;
    return AppearanceAnalysisResult(
      findings: [
        AppearanceFinding(
          dimension: 'hair',
          statement: 'synthetic',
          confidence: .8,
        ),
      ],
      actions: [
        AppearanceActionSuggestion(title: 'review', rationale: 'synthetic'),
      ],
      modelTraceRef: 'synthetic-trace',
    );
  }
}

final class _Store implements EventStore {
  final List<EventEnvelope> events = <EventEnvelope>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async =>
      this.events.addAll(events);

  @override
  Future<EventEnvelope?> readById(String eventId) async =>
      events.where((event) => event.eventId == eventId).firstOrNull;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      events.where((event) => event.subjectRefs.contains(subject)).toList();
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String nextId(String namespace) => namespace + '-' + (++value).toString();
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
