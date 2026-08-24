import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';

import 'package:personal_os_app/src/controller/app_controller.dart';

void main() {
  test('locked vault rejects analysis before any gateway call', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.errorCode, 'vault_locked');
    expect(gateway.calls, 0);
  });

  test('raw path is rejected before any gateway call', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway)
      ..unlockVault()
      ..setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: '/storage/emulated/0/DCIM/portrait.jpg',
      observationContext: 'front',
    );

    expect(controller.errorCode, 'blob_reference_required');
    expect(gateway.calls, 0);
  });

  test('consented blob reference completes the application loop', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway, withObservation: true)
      ..unlockVault()
      ..setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.submission, SubmissionStatus.succeeded);
    expect(controller.result?.claimIds, hasLength(2));
    expect(controller.result?.taskIds, hasLength(1));
    expect(gateway.calls, 1);
    expect(gateway.eventTypesAtCall, contains('observation.recorded'));
  });

  test('observation failure is fail-closed before any gateway call', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway, withObservation: true)
      ..unlockVault()
      ..setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: '',
    );

    expect(controller.submission, SubmissionStatus.failed);
    expect(controller.errorCode, ObservationFailureCode.invalidContext);
    expect(gateway.calls, 0);
  });

  test('UX consent cannot bypass missing persisted consent revision', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway, includeGrant: false)..unlockVault();
    await controller.setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.errorCode, AppearanceFailureCode.policyDenied);
    expect(gateway.calls, 0);
  });

  test('guided navigation stays gated until analysis succeeds', () async {
    final controller = _controller(_CountingGateway())..unlockVault();

    controller.continueFromClaims();
    controller.startPlan();
    expect(controller.destination.name, 'home');

    controller.setConsent(true);
    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    expect(controller.completedStep, 2);

    controller.continueFromClaims();
    expect(controller.destination.name, 'plan');
    controller.startPlan();
    expect(controller.destination.name, 'tasks');
  });

  test(
      'bootstrap reconstructs the analysis session after controller recreation',
      () async {
    final store = InMemoryEventStore();
    final writer = _controller(_CountingGateway(), store: store);
    writer.unlockVault();
    await writer.setConsent(true);
    await writer.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    final reader = _controller(
      _CountingGateway(),
      store: store,
      withSessionQuery: true,
    )..unlockVault();
    await reader.bootstrap();

    expect(reader.result?.claimIds, hasLength(2));
    expect(reader.result?.taskIds, hasLength(1));
    expect(reader.planStarted, isTrue);
    expect(reader.taskState(reader.result!.taskIds.single), 'planned');
    expect(reader.consentGranted, isTrue);
  });

  test('bootstrap restores observation metadata without exposing its reference',
      () async {
    final store = InMemoryEventStore();
    final writer = _controller(
      _CountingGateway(),
      store: store,
      withObservation: true,
    )..unlockVault();
    await writer.setConsent(true);
    await writer.analyzeBlobReference(
      blobReference: 'blob://vault/private-photo',
      observationContext: 'front',
    );

    final reader = _controller(
      _CountingGateway(),
      store: store,
      withSessionQuery: true,
    )..unlockVault();
    await reader.bootstrap();

    expect(reader.observationCount, 1);
    expect(reader.latestObservation?.mediaType, 'image/*');
    expect(reader.latestObservation?.occurredAt, isNotNull);
    expect(reader.observations.toString(), isNot(contains('private-photo')));

    reader.lockVault();
    expect(reader.observationCount, 0);
    expect(reader.latestObservation, isNull);
  });

  test('locking clears volatile session state before the next unlock',
      () async {
    final controller = _controller(_CountingGateway())..unlockVault();
    await controller.setConsent(true);
    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    controller.startPlan();

    controller.lockVault();

    expect(controller.vaultUnlocked, isFalse);
    expect(controller.result, isNull);
    expect(controller.consentGranted, isFalse);
    expect(controller.planStarted, isFalse);
    expect(controller.reviewId, isNull);
  });

  test('repeated bootstrap is a no-op after the first projection', () async {
    final controller = _controller(
      _CountingGateway(),
      withSessionQuery: true,
    )..unlockVault();
    await controller.bootstrap();
    await controller.bootstrap();
    expect(controller.vaultUnlocked, isTrue);
    expect(controller.errorCode, isNull);
  });

  test('bootstrap failure while locked does not expose persisted state',
      () async {
    final controller = _controller(
      _CountingGateway(),
      withSessionQuery: true,
    );
    await controller.bootstrap();
    expect(controller.vaultUnlocked, isFalse);
    expect(controller.result, isNull);
    expect(controller.consentGranted, isFalse);
    expect(controller.errorCode, isNull);
  });

  test('locking after bootstrap clears every protected projection', () async {
    final store = InMemoryEventStore();
    final writer = _controller(_CountingGateway(), store: store);
    writer.unlockVault();
    await writer.setConsent(true);
    await writer.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    final controller = _controller(
      _CountingGateway(),
      store: store,
      withSessionQuery: true,
    )..unlockVault();
    await controller.bootstrap();
    controller.lockVault();
    expect(controller.result, isNull);
    expect(controller.planStarted, isFalse);
    expect(controller.observationCount, 0);
    expect(controller.consentGranted, isFalse);
  });
}

AppController _controller(
  _CountingGateway gateway, {
  bool includeGrant = true,
  InMemoryEventStore? store,
  bool withSessionQuery = false,
  bool withObservation = false,
}) {
  final eventStore = store ?? InMemoryEventStore();
  final ids = _Ids();
  gateway.eventStore = eventStore;
  return AppController(
    analyzeAppearance: AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: gateway,
      policy: AppearancePolicyAdapter(
        consents: InMemoryConsentRevisionRepository(
          initialGrants: includeGrant
              ? <ConsentGrant>[
                  ConsentGrant(
                    consentId: 'local-appearance-consent',
                    revision: 1,
                    subjectId: 'me',
                    authorizedActorId: 'me',
                    purposes: const <String>{'appearance_review'},
                    resources: const <String>{'portrait'},
                    actions: const <String>{'derive'},
                    maximumSensitivity: Sensitivity.d3,
                    validFrom: DateTime.utc(2026, 8, 19),
                    validUntil: DateTime.utc(2026, 8, 21),
                    status: ConsentStatus.active,
                  ),
                ]
              : const <ConsentGrant>[],
        ),
        clock: FixedPolicyClock(DateTime.utc(2026, 8, 20)),
      ),
      ids: ids,
      clock: const _Clock(),
    ),
    actionFeedback: ActionFeedbackUseCase(
      eventStore: eventStore,
      ids: ids,
      clock: const _Clock(),
    ),
    recordObservation: withObservation
        ? RecordObservationUseCase(
            eventStore: eventStore,
            ids: ids,
            clock: const _Clock(),
          )
        : null,
    profileId: EntityId('me'),
    sessionQuery:
        withSessionQuery ? AppearanceSessionQueryHandler(eventStore) : null,
    consentLifecycle: ConsentLifecycleUseCase(
      eventStore: eventStore,
      ids: ids,
      clock: const _Clock(),
    ),
    actor: ActorRef(
      actorId: 'me',
      actorType: ActorType.user,
      authoritySource: 'test',
    ),
  );
}

final class _CountingGateway implements AppearanceAnalysisGateway {
  int calls = 0;
  InMemoryEventStore? eventStore;
  List<String> eventTypesAtCall = const <String>[];

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    calls++;
    eventTypesAtCall =
        eventStore?.readEvents().map((e) => e.event.eventType).toList() ??
            const <String>[];
    return const FixtureAppearanceAnalysisGateway(
      behavior: FixtureAppearanceBehavior.syntheticSuccess,
    ).analyze(input);
  }
}

final class _Ids implements IdGenerator {
  int value = 0;
  @override
  String nextId(String namespace) => '$namespace-${++value}';
}

final class _Clock implements Clock {
  const _Clock();
  @override
  DateTime now() => DateTime.utc(2026, 8, 20);
}
