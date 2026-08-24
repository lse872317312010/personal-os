import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:personal_os_source_api/source_api.dart';

import '../controller/app_controller.dart';
import 'android_platform_security_bridge.dart';
import 'native_sqlcipher_event_store.dart';
import 'native_sqlcipher_session_coordinator.dart';
import 'method_channel_controlled_source_port.dart';
import 'method_channel_source_blob_ingestion_port.dart';

enum AppExperienceMode { syntheticDemo, secureVault }

/// Replace this composition root with encrypted persistence, keystore-backed
/// unlock, and a real model adapter. Widgets never reach those adapters.
final class AppComposition {
  AppComposition({
    required this.controller,
    required this.eventStore,
    required this.mode,
  });

  final AppController controller;
  final EventStore eventStore;
  final AppExperienceMode mode;

  factory AppComposition.inMemoryDemo() {
    final policyClock = _SystemPolicyClock();
    return _build(
      eventStore: InMemoryEventStore(),
      mode: AppExperienceMode.syntheticDemo,
      initialGrants: <ConsentGrant>[
        _demoAppearanceConsent(policyClock.now()),
      ],
    );
  }

  /// The runtime composition used by the shipped application.
  ///
  /// Android is the primary vault platform, so it must exercise the native
  /// authenticated vault path by default. Other platforms keep the synthetic
  /// composition until they have an equivalent secure adapter. Tests and
  /// previews should continue to request [inMemoryDemo] explicitly.
  factory AppComposition.forCurrentPlatform() =>
      defaultTargetPlatform == TargetPlatform.android
          ? AppComposition.secureVault()
          : AppComposition.inMemoryDemo();

  /// Secure composition. The model remains a synthetic fixture by design;
  /// this factory only wires native authentication and encrypted persistence.
  factory AppComposition.secureVault({
    PlatformSecurityBridge? securityBridge,
    MethodChannel? channel,
  }) {
    final bridge =
        securityBridge ?? AndroidPlatformSecurityBridge(channel: channel);
    final eventStore = NativeSqlCipherEventStore(channel: channel);
    final sourcePort = MethodChannelControlledSourcePort(channel: channel);
    final sourceBlobIngestion =
        MethodChannelSourceBlobIngestionPort(sourcePort);
    final coordinator = NativeSqlCipherSessionCoordinator(
      bridge: bridge,
      eventStore: eventStore,
    );
    return _build(
      eventStore: eventStore,
      mode: AppExperienceMode.secureVault,
      vaultSession: DefaultVaultSession(DeviceSecureUnlockAdapter(bridge)),
      sessionCoordinator: coordinator,
      sourcePort: sourcePort,
      sourceBlobIngestion: sourceBlobIngestion,
    );
  }

  static AppComposition _build({
    required EventStore eventStore,
    required AppExperienceMode mode,
    Iterable<ConsentGrant> initialGrants = const <ConsentGrant>[],
    VaultSession? vaultSession,
    SecureSessionCoordinator? sessionCoordinator,
    ControlledSourcePort? sourcePort,
    SourceBlobIngestionPort? sourceBlobIngestion,
  }) {
    final clock = _SystemClock();
    final policyClock = _SystemPolicyClock();
    final consentRepository = InMemoryConsentRevisionRepository(
      initialGrants: initialGrants,
    );
    final policyConsentRepository = EventBackedConsentRevisionRepository(
      eventStore: eventStore,
      fallback: consentRepository,
    );
    final ids = _SequentialIds();
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: const FixtureAppearanceAnalysisGateway(
        behavior: FixtureAppearanceBehavior.syntheticSuccess,
      ),
      policy: AppearancePolicyAdapter(
        consents: policyConsentRepository,
        clock: policyClock,
      ),
      ids: ids,
      clock: clock,
    );
    return AppComposition(
      eventStore: eventStore,
      mode: mode,
      controller: AppController(
        analyzeAppearance: useCase,
        actionFeedback: ActionFeedbackUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        profileId: EntityId('primary-user'),
        sessionQuery: AppearanceSessionQueryHandler(eventStore),
        consentLifecycle: ConsentLifecycleUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        recordObservation: RecordObservationUseCase(
          eventStore: eventStore,
          ids: ids,
          clock: clock,
        ),
        sourcePort: sourcePort,
        ingestAppearanceFromSource: sourceBlobIngestion == null
            ? null
            : IngestAppearanceFromSourceUseCase(
                ingestion: sourceBlobIngestion,
                recordObservation: RecordObservationUseCase(
                  eventStore: eventStore,
                  ids: ids,
                  clock: clock,
                ),
                analyzeAppearance: useCase,
              ),
        actor: ActorRef(
          actorId: 'primary-user',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
        vaultSession: vaultSession,
        sessionCoordinator: sessionCoordinator,
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
