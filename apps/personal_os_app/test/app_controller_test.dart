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
    final controller = _controller(gateway)
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
  });

  test('UX consent cannot bypass missing persisted consent revision', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway, includeGrant: false)
      ..unlockVault()
      ..setConsent(true);

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
}

AppController _controller(
  _CountingGateway gateway, {
  bool includeGrant = true,
}) {
  final store = InMemoryEventStore();
  final ids = _Ids();
  return AppController(
    analyzeAppearance: AnalyzeAppearanceUseCase(
      eventStore: store,
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
      eventStore: store,
      ids: ids,
      clock: const _Clock(),
    ),
    profileId: EntityId('me'),
    actor: ActorRef(
      actorId: 'me',
      actorType: ActorType.user,
      authoritySource: 'test',
    ),
  );
}

final class _CountingGateway implements AppearanceAnalysisGateway {
  int calls = 0;

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    calls++;
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
