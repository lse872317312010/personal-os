import 'package:personal_os_application/application.dart';
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

  test('denied policy fails closed before model or storage access', () async {
    final store = _MemoryEventStore();
    final model = _FakeModelGateway(_completeAnalysis());
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: model,
      policy: const _FixedPolicy(PolicyVerdict.deny('consent_missing')),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    await expectLater(
      useCase.execute(_command(actor)),
      throwsA(
        isA<AppearanceUseCaseFailure>()
            .having((e) => e.code, 'code', AppearanceFailureCode.policyDenied)
            .having((e) => e.detail, 'detail', 'consent_missing'),
      ),
    );
    expect(model.calls, 0);
    expect(store.appendCalls, 0);
  });

  test('complete analysis atomically emits the minimal action loop', () async {
    final store = _MemoryEventStore();
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: _FakeModelGateway(_completeAnalysis()),
      policy: const _FixedPolicy(PolicyVerdict.allow()),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    final result = await useCase.execute(_command(actor));

    expect(store.appendCalls, 1);
    expect(store.events, hasLength(5));
    expect(
      store.events.map((event) => event.eventType),
      <String>[
        EventTypes.claimProposed,
        EventTypes.claimProposed,
        EventTypes.goalCreated,
        EventTypes.planDrafted,
        EventTypes.taskPlanned,
      ],
    );
    expect(store.events.every((event) => event.sensitivity == Sensitivity.d3),
        isTrue);
    expect(
        store.events.every((event) => event.correlationId == 'corr-1'), isTrue);
    expect(result.claimIds, hasLength(2));
    expect(result.taskIds, hasLength(1));
    expect(result.eventIds, hasLength(5));
  });

  test('passes external processing boundary through policy and audit events',
      () async {
    final store = _MemoryEventStore();
    final policy = _RecordingPolicy();
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: _FakeModelGateway(_completeAnalysis()),
      policy: policy,
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );
    final command = AnalyzeAppearanceCommand(
      profileId: EntityId('profile-1'),
      imageRef: 'blob://photo-1',
      actor: actor,
      correlationId: 'corr-external',
      observationContext: '正面自然光照片',
      consentRefs: <ObjectRef>[
        ObjectRef(
          type: 'consent',
          id: EntityId('consent-1'),
          revision: Revision(1),
        ),
        ObjectRef(
          type: 'consent',
          id: EntityId('external-consent-1'),
          revision: Revision(1),
        ),
      ],
      processingBoundary: AppearanceProcessingBoundary.externalProcessor,
    );

    await useCase.execute(command);

    expect(
      policy.processingBoundary,
      AppearanceProcessingBoundary.externalProcessor,
    );
    final claim = store.events.firstWhere(
      (event) => event.eventType == EventTypes.claimProposed,
    );
    expect(claim.payload['processing_boundary'], 'externalProcessor');
  });

  test('incomplete analysis writes nothing', () async {
    final store = _MemoryEventStore();
    final model = _FakeModelGateway(
      AppearanceAnalysisResult(
        findings: const <AppearanceFinding>[],
        actions: <AppearanceActionSuggestion>[
          AppearanceActionSuggestion(title: '理发', rationale: '轮廓更清晰'),
        ],
        modelTraceRef: 'trace-1',
      ),
    );
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: model,
      policy: const _FixedPolicy(PolicyVerdict.allow()),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    await expectLater(
      useCase.execute(_command(actor)),
      throwsA(
        isA<AppearanceUseCaseFailure>().having(
          (e) => e.code,
          'code',
          AppearanceFailureCode.emptyAnalysis,
        ),
      ),
    );
    expect(store.events, isEmpty);
  });

  test('prompt-version mismatch fails closed and writes nothing', () async {
    final store = _MemoryEventStore();
    final analysis = _completeAnalysis(promptVersion: 'appearance-v2');
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: _FakeModelGateway(analysis),
      policy: const _FixedPolicy(PolicyVerdict.allow()),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    await expectLater(
      useCase.execute(_command(actor)),
      throwsA(
        isA<AppearanceUseCaseFailure>().having(
          (error) => error.code,
          'code',
          AppearanceFailureCode.invalidAnalysis,
        ),
      ),
    );
    expect(store.events, isEmpty);
  });

  test('persists stable audit fields but not risk or confirmation prose',
      () async {
    final store = _MemoryEventStore();
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: _FakeModelGateway(_completeAnalysis()),
      policy: const _FixedPolicy(PolicyVerdict.allow()),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    await useCase.execute(_command(actor));

    final claim = store.events.first;
    expect(claim.payload['model_id'], 'fixture-model-v1');
    expect(claim.payload['prompt_version'], 'appearance-v1');
    expect(claim.payload['input_summary_ref'], 'audit://input/fixture-1');
    expect(claim.payload['finding_kind'], 'uncertainInference');
    final plan = store.events.singleWhere(
      (event) => event.eventType == EventTypes.planDrafted,
    );
    expect(plan.payload['risk_codes'], <String>['low_light']);
    expect(
      plan.payload['human_confirmation_codes'],
      <String>['confirm_hair_shape'],
    );
    final encodedPayloads = store.events.map((event) => event.payload).join();
    expect(encodedPayloads, isNot(contains('private risk prose')));
    expect(encodedPayloads, isNot(contains('private confirmation prompt')));
  });

  test('event-store append failure is stable and publishes no events',
      () async {
    final store = _MemoryEventStore()..failAppend = true;
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: _FakeModelGateway(_completeAnalysis()),
      policy: const _FixedPolicy(PolicyVerdict.allow()),
      ids: _SequentialIds(),
      clock: _FixedClock(),
    );

    await expectLater(
      useCase.execute(_command(actor)),
      throwsA(isA<AppearanceUseCaseFailure>()
          .having((e) => e.code, 'code', AppearanceFailureCode.analysisFailed)
          .having((e) => e.toString(), 'safe', isNot(contains('secret')))),
    );
    expect(store.events, isEmpty);
  });

  test('history query uses profile subject and limit', () async {
    final store = _MemoryEventStore();
    final handler = AppearanceHistoryQueryHandler(store);
    await handler.execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1'), limit: 12),
    );
    expect(store.lastReadSubject?.type, 'profile');
    expect(store.lastReadSubject?.id.value, 'profile-1');
    expect(store.lastReadLimit, 12);
  });
}

AnalyzeAppearanceCommand _command(ActorRef actor) => AnalyzeAppearanceCommand(
      profileId: EntityId('profile-1'),
      imageRef: 'blob:photo-1',
      actor: actor,
      correlationId: 'corr-1',
      observationContext: '正面自然光照片',
      consentRefs: <ObjectRef>[
        ObjectRef(type: 'consent', id: EntityId('consent-1')),
      ],
    );

AppearanceAnalysisResult _completeAnalysis({
  String promptVersion = 'appearance-v1',
}) =>
    AppearanceAnalysisResult(
      findings: <AppearanceFinding>[
        AppearanceFinding(
            dimension: 'hair', statement: '顶部体积不足', confidence: .8),
        AppearanceFinding(
            dimension: 'skin', statement: '肤色略不均', confidence: .7),
      ],
      actions: <AppearanceActionSuggestion>[
        AppearanceActionSuggestion(title: '尝试纹理短发', rationale: '增强顶部轮廓'),
      ],
      modelTraceRef: 'trace-1',
      modelId: 'fixture-model-v1',
      promptVersion: promptVersion,
      inputSummaryRef: 'audit://input/fixture-1',
      risks: <AppearanceRisk>[
        AppearanceRisk(code: 'low_light', statement: 'private risk prose'),
      ],
      humanConfirmations: <AppearanceHumanConfirmation>[
        AppearanceHumanConfirmation(
          code: 'confirm_hair_shape',
          prompt: 'private confirmation prompt',
        ),
      ],
    );

final class _MemoryEventStore implements EventStore {
  final events = <EventEnvelope>[];
  int appendCalls = 0;
  bool failAppend = false;
  ObjectRef? lastReadSubject;
  int? lastReadLimit;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    appendCalls++;
    if (failAppend) throw StateError('secret adapter detail');
    this.events.addAll(events);
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async =>
      events.where((event) => event.eventId == eventId).firstOrNull;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    lastReadSubject = subject;
    lastReadLimit = limit;
    return events.take(limit ?? events.length).toList(growable: false);
  }
}

final class _FakeModelGateway implements AppearanceAnalysisGateway {
  _FakeModelGateway(this.result);

  final AppearanceAnalysisResult result;
  int calls = 0;

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    calls++;
    return result;
  }
}

final class _FixedPolicy implements AppearancePolicyPort {
  const _FixedPolicy(this.verdict);

  final PolicyVerdict verdict;

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
    AppearanceProcessingBoundary processingBoundary =
        AppearanceProcessingBoundary.onDevice,
  }) async =>
      verdict;
}

final class _RecordingPolicy implements AppearancePolicyPort {
  AppearanceProcessingBoundary? processingBoundary;

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
    AppearanceProcessingBoundary processingBoundary =
        AppearanceProcessingBoundary.onDevice,
  }) async {
    this.processingBoundary = processingBoundary;
    return const PolicyVerdict.allow();
  }
}

final class _SequentialIds implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 8, 20, 12);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
