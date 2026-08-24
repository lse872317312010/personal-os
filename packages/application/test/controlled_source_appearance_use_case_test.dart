import 'package:personal_os_application/application.dart';
import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('success commits analysis and observation and retains the blob', () async {
    final source = _Source();
    final ingestion = _Ingestion();
    final store = _Store();
    final result = await ControlledSourceAppearanceUseCase(
      source: source,
      ingest: IngestAppearanceFromSourceUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
        analyzeAppearance: AnalyzeAppearanceUseCase(
          eventStore: store,
          modelGateway: const _WorkingModel(),
          policy: const _AllowPolicy(),
          ids: _Ids(),
          clock: _Clock(),
        ),
      ),
    ).capturePhotoAndAnalyze(
      mediaType: 'image/jpeg',
      access: BlobAccessContext(
        actorRef: 'user:1',
        purpose: 'appearance-analysis',
        consentRef: 'consent:1',
      ),
      profileId: EntityId('profile-1'),
      observationContext: 'front',
      consentRef: ObjectRef(type: 'consent', id: EntityId('consent-1')),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'native',
      ),
      correlationId: 'capture-success',
    );

    expect(result.observation.observationId, isNotEmpty);
    expect(store.events, hasLength(6));
    expect(ingestion.discarded, isEmpty);
    expect(source.released, hasLength(1));
  });

  test('releases the native token when analysis fails', () async {
    final source = _Source();
    final ingestion = _Ingestion();
    final store = _Store();
    final useCase = ControlledSourceAppearanceUseCase(
      source: source,
      ingest: IngestAppearanceFromSourceUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
        analyzeAppearance: AnalyzeAppearanceUseCase(
          eventStore: store,
          modelGateway: const _FailingModel(),
          policy: const _AllowPolicy(),
          ids: _Ids(),
          clock: _Clock(),
        ),
      ),
    );

    await expectLater(
      useCase.capturePhotoAndAnalyze(
        mediaType: 'image/jpeg',
        access: BlobAccessContext(
          actorRef: 'user:1',
          purpose: 'appearance-analysis',
          consentRef: 'consent:1',
        ),
        profileId: EntityId('profile-1'),
        observationContext: 'front',
        consentRef: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        actor: ActorRef(
          actorId: 'user-1',
          actorType: ActorType.user,
          authoritySource: 'native',
        ),
        correlationId: 'capture-1',
      ),
      throwsA(isA<AppearanceUseCaseFailure>().having(
        (error) => error.code,
        'code',
        AppearanceFailureCode.analysisFailed,
      )),
    );
    expect(source.released, hasLength(1));
    expect(ingestion.discarded, hasLength(1));
    expect(store.events, isEmpty);
  });

  test('retains the blob when observation append fails after analysis commits', () async {
    final source = _Source();
    final ingestion = _Ingestion();
    final store = _Store()..failOnAppendCall = 2;
    final useCase = ControlledSourceAppearanceUseCase(
      source: source,
      ingest: IngestAppearanceFromSourceUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
        analyzeAppearance: AnalyzeAppearanceUseCase(
          eventStore: store,
          modelGateway: const _WorkingModel(),
          policy: const _AllowPolicy(),
          ids: _Ids(),
          clock: _Clock(),
        ),
      ),
    );

    await expectLater(
      useCase.capturePhotoAndAnalyze(
        mediaType: 'image/jpeg',
        access: BlobAccessContext(
          actorRef: 'user:1',
          purpose: 'appearance-analysis',
          consentRef: 'consent:1',
        ),
        profileId: EntityId('profile-1'),
        observationContext: 'front',
        consentRef: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        actor: ActorRef(
          actorId: 'user-1',
          actorType: ActorType.user,
          authoritySource: 'native',
        ),
        correlationId: 'capture-append-failure',
      ),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.appendFailed,
      )),
    );
    expect(store.events, hasLength(5));
    expect(ingestion.discarded, isEmpty);
    expect(source.released, hasLength(1));
  });

  test('D4 fails before native ingestion and still releases token', () async {
    final source = _Source();
    final ingestion = _Ingestion();
    final useCase = ControlledSourceAppearanceUseCase(
      source: source,
      ingest: IngestAppearanceFromSourceUseCase(
        ingestion: ingestion,
        recordObservation: _recording(),
        analyzeAppearance: _analysis(),
      ),
    );

    await expectLater(
      useCase.pickPhotoAndAnalyze(
        mediaType: 'image/jpeg',
        access: BlobAccessContext(
          actorRef: 'user:1',
          purpose: 'appearance-analysis',
          consentRef: 'consent:1',
        ),
        profileId: EntityId('profile-1'),
        observationContext: 'front',
        consentRef: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        actor: ActorRef(
          actorId: 'user-1',
          actorType: ActorType.user,
          authoritySource: 'native',
        ),
        correlationId: 'capture-2',
        sensitivity: Sensitivity.d4,
      ),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.d4Forbidden,
      )),
    );
    expect(ingestion.sources, isEmpty);
    expect(source.released, hasLength(1));
  });
}

RecordObservationUseCase _recording() => RecordObservationUseCase(
      eventStore: _Store(), ids: _Ids(), clock: _Clock());

AnalyzeAppearanceUseCase _analysis() => AnalyzeAppearanceUseCase(
      eventStore: _Store(),
      modelGateway: const _WorkingModel(),
      policy: const _AllowPolicy(),
      ids: _Ids(),
      clock: _Clock(),
    );

final class _Source implements ControlledSourcePort {
  final token = OpaqueSourceToken('native-token');
  final released = <OpaqueSourceToken>[];
  @override
  Future<ControlledSourceCapabilities> capabilities() async =>
      const ControlledSourceCapabilities(photoPicker: true, camera: true);
  @override
  Future<OpaqueSourceToken> pickPhoto() async => token;
  @override
  Future<OpaqueSourceToken> capturePhoto() async => token;
  @override
  Future<void> release(OpaqueSourceToken token) async => released.add(token);
}

final class _Ingestion implements SourceBlobIngestionPort {
  final sources = <OpaqueSourceToken>[];
  final discarded = <BlobRef>[];
  @override
  Future<BlobRef> ingestSource({required OpaqueSourceToken source, required String mediaType, required Sensitivity sensitivity, required BlobAccessContext access}) async { sources.add(source); return BlobRef('blob://one'); }
  @override
  Future<void> discard({required BlobRef ref, required BlobAccessContext access}) async => discarded.add(ref);
}

final class _FailingModel implements AppearanceAnalysisGateway {
  const _FailingModel();
  @override
  Future<AppearanceAnalysisResult> analyze(AppearanceAnalysisInput input) =>
      Future<AppearanceAnalysisResult>.error(StateError('secret path'));
}

final class _WorkingModel implements AppearanceAnalysisGateway {
  const _WorkingModel();
  @override
  Future<AppearanceAnalysisResult> analyze(AppearanceAnalysisInput input) async =>
      AppearanceAnalysisResult(findings: [AppearanceFinding(dimension: 'x', statement: 'y', confidence: .8)], actions: [AppearanceActionSuggestion(title: 'x', rationale: 'y')], modelTraceRef: 'trace');
}

final class _AllowPolicy implements AppearancePolicyPort {
  const _AllowPolicy();
  @override
  Future<PolicyVerdict> authorizeAnalysis({required ActorRef actor, required EntityId profileId, required List<ObjectRef> consentRefs, required Sensitivity sensitivity}) async => const PolicyVerdict.allow();
}

final class _Store implements EventStore {
  final events = <EventEnvelope>[];
  int appendCalls = 0;
  int? failOnAppendCall;
  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    appendCalls++;
    if (appendCalls == failOnAppendCall) {
      throw StateError('/tmp/secret-store');
    }
    this.events.addAll(events);
  }
  @override Future<EventEnvelope?> readById(String eventId) async => null;
  @override Future<List<EventEnvelope>> readBySubject(ObjectRef subject, {int? limit}) async => events;
}
final class _Ids implements IdGenerator { int n = 0; @override String nextId(String namespace) => '$namespace-${++n}'; }
final class _Clock implements Clock { @override DateTime now() => DateTime.utc(2026, 1, 1); }
