import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('preserves enumerated redacted model gateway failures', () async {
    final store = _MemoryEventStore();
    final useCase = _useCase(
      store,
      _ThrowingGateway(
        AppearanceModelGatewayFailure(
          AppearanceModelGatewayFailureCode.mediaTooLarge,
        ),
      ),
    );

    await expectLater(
      useCase.execute(_command()),
      throwsA(
        isA<AppearanceUseCaseFailure>()
            .having(
              (failure) => failure.code,
              'code',
              AppearanceModelGatewayFailureCode.mediaTooLarge,
            )
            .having((failure) => failure.detail, 'detail', isNull),
      ),
    );

    expect(store.appendCalls, 0);
  });

  test('redacts arbitrary adapter failures to analysis_failed', () async {
    final store = _MemoryEventStore();
    final useCase = _useCase(
      store,
      _ThrowingGateway(
        StateError('api-key=secret /data/user/0/private.jpg'),
      ),
    );

    await expectLater(
      useCase.execute(_command()),
      throwsA(
        isA<AppearanceUseCaseFailure>()
            .having(
              (failure) => failure.code,
              'code',
              AppearanceFailureCode.analysisFailed,
            )
            .having(
              (failure) => failure.toString(),
              'redacted',
              allOf(isNot(contains('secret')), isNot(contains('/data/'))),
            ),
      ),
    );

    expect(store.appendCalls, 0);
  });

  test('gateway failure contract sanitizes unknown codes', () {
    final failure = AppearanceModelGatewayFailure(
      'provider.secret.raw_failure',
    );

    expect(
      failure.code,
      AppearanceModelGatewayFailureCode.adapterUnavailable,
    );
    expect(failure.toString(), isNot(contains('secret')));
  });
}

AnalyzeAppearanceUseCase _useCase(
  EventStore store,
  AppearanceAnalysisGateway gateway,
) =>
    AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: gateway,
      policy: const _AllowPolicy(),
      ids: _Ids(),
      clock: const _Clock(),
    );

AnalyzeAppearanceCommand _command() => AnalyzeAppearanceCommand(
      profileId: EntityId('profile-1'),
      imageRef: 'blob://1234567890abcdef',
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'test',
      ),
      correlationId: 'corr-1',
      observationContext: 'front-facing natural light',
      consentRefs: <ObjectRef>[
        ObjectRef(
          type: 'consent',
          id: EntityId('consent-1'),
          revision: Revision(1),
        ),
      ],
      processingBoundary: AppearanceProcessingBoundary.externalProcessor,
    );

final class _ThrowingGateway implements AppearanceAnalysisGateway {
  _ThrowingGateway(this.failure);

  final Object failure;

  @override
  Future<AppearanceAnalysisResult> analyze(
    AppearanceAnalysisInput input,
  ) async {
    final value = failure;
    if (value is Exception) throw value;
    if (value is Error) throw value;
    throw StateError('unsupported test failure');
  }
}

final class _MemoryEventStore implements EventStore {
  int appendCalls = 0;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    appendCalls++;
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      const <EventEnvelope>[];
}

final class _AllowPolicy implements AppearancePolicyPort {
  const _AllowPolicy();

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
    AppearanceProcessingBoundary processingBoundary =
        AppearanceProcessingBoundary.onDevice,
  }) async =>
      const PolicyVerdict.allow();
}

final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 14, 16, 33);
}
