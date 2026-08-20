import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';

import '../controller/app_controller.dart';

/// Replace this composition root with encrypted persistence, keystore-backed
/// unlock, and a real model adapter. Widgets never reach those adapters.
final class AppComposition {
  AppComposition({required this.controller, required this.eventStore});

  final AppController controller;
  final InMemoryEventStore eventStore;

  factory AppComposition.inMemoryDemo() {
    final clock = _SystemClock();
    final policyClock = _SystemPolicyClock();
    final consentRepository = InMemoryConsentRevisionRepository(
      initialGrants: <ConsentGrant>[
        _demoAppearanceConsent(policyClock.now()),
      ],
    );
    final eventStore = InMemoryEventStore();
    final ids = _SequentialIds();
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: const FixtureAppearanceAnalysisGateway(
        behavior: FixtureAppearanceBehavior.syntheticSuccess,
      ),
      policy: AppearancePolicyAdapter(
        consents: consentRepository,
        clock: policyClock,
      ),
      ids: ids,
      clock: clock,
    );
    return AppComposition(
      eventStore: eventStore,
      controller: AppController(
        analyzeAppearance: useCase,
        actionFeedback: ActionFeedbackUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        profileId: EntityId('primary-user'),
        actor: ActorRef(
          actorId: 'primary-user',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
      ),
    );
  }
}

final class _SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

final class _SystemPolicyClock implements PolicyClock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

ConsentGrant _demoAppearanceConsent(DateTime now) => ConsentGrant(
      consentId: 'local-appearance-consent',
      revision: 1,
      subjectId: 'primary-user',
      authorizedActorId: 'primary-user',
      purposes: const <String>{'appearance_review'},
      resources: const <String>{'portrait'},
      actions: const <String>{'derive'},
      maximumSensitivity: Sensitivity.d3,
      validFrom: now.subtract(const Duration(minutes: 5)),
      validUntil: now.add(const Duration(hours: 8)),
      status: ConsentStatus.active,
    );

final class _SequentialIds implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}
