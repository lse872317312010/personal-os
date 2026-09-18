import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:personal_os_source_api/source_api.dart';

import '../controller/app_controller.dart';
import '../controller/strategy_loop_controller.dart';
import 'android_platform_security_bridge.dart';
import 'method_channel_appearance_analysis_gateway.dart';
import 'method_channel_controlled_source_port.dart';
import 'method_channel_source_blob_ingestion_port.dart';
import 'native_sqlcipher_event_store.dart';
import 'native_sqlcipher_session_coordinator.dart';

enum AppExperienceMode { syntheticDemo, secureVault }

/// Replace this composition root with encrypted persistence, keystore-backed
/// unlock, and a real model adapter. Widgets never reach those adapters.
final class AppComposition {
  AppComposition({
    required this.controller,
    required this.strategyController,
    required this.eventStore,
    required this.mode,
  });

  final AppController controller;
  final StrategyLoopController strategyController;
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
  /// Android is the primary vault platform and exercises the native
  /// authenticated vault path by default. Platforms without an equivalent
  /// secure adapter must fail closed rather than silently entering the
  /// synthetic demo. Tests and previews may request [inMemoryDemo] explicitly.
  factory AppComposition.forCurrentPlatform() =>
      AppComposition.forTargetPlatform(defaultTargetPlatform);

  /// Explicit target-platform selection keeps the production platform policy
  /// testable without mutating Flutter's process-wide platform override.
  factory AppComposition.forTargetPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.android
          ? AppComposition.secureVault()
          : AppComposition.unsupportedSecurePlatform();

  /// Fail-closed shell for a shipped platform that does not yet have a trusted
  /// vault adapter. The UI can start and explain that unlock is unavailable,
  /// but it cannot unlock, ingest media, persist user events, or invoke a
  /// synthetic/real model gateway.
  factory AppComposition.unsupportedSecurePlatform() {
    const eventStore = _UnavailableEventStore();
    return _build(
      eventStore: eventStore,
      mode: AppExperienceMode.secureVault,
      vaultSession: DefaultVaultSession(const _UnavailableSecureUnlockPort()),
      secureVault: const _UnavailableSecureVaultPort(),
      modelGateway: const _UnavailableAppearanceAnalysisGateway(),
    );
  }

  /// Secure composition never falls back to a synthetic model gateway.
  factory AppComposition.secureVault({
    PlatformSecurityBridge? securityBridge,
    MethodChannel? channel,
    MethodChannel? modelChannel,
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
      modelGateway: MethodChannelAppearanceAnalysisGateway(
        channel: modelChannel,
      ),
    );
  }

  static AppComposition _build({
    required EventStore eventStore,
    required AppExperienceMode mode,
    Iterable<ConsentGrant> initialGrants = const <ConsentGrant>[],
    VaultSession? vaultSession,
    SecureVaultPort? secureVault,
    SecureSessionCoordinator? sessionCoordinator,
    ControlledSourcePort? sourcePort,
    SourceBlobIngestionPort? sourceBlobIngestion,
    AppearanceAnalysisGateway? modelGateway,
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
    final resolvedModelGateway = modelGateway ??
        const FixtureAppearanceAnalysisGateway(
          behavior: FixtureAppearanceBehavior.syntheticSuccess,
        );
    final useCase = AnalyzeAppearanceUseCase(
      eventStore: eventStore,
      modelGateway: resolvedModelGateway,
      policy: AppearancePolicyAdapter(
        consents: policyConsentRepository,
        clock: policyClock,
      ),
      ids: ids,
      clock: clock,
    );
    final profileId = EntityId('primary-user');
    final userActor = ActorRef(
      actorId: 'primary-user',
      actorType: ActorType.user,
      authoritySource: 'local-vault-session',
    );
    final strategyLoop = StrategyLoopUseCase(
      eventStore: eventStore,
      ids: ids,
      clock: clock,
    );
    final actionFeedback = ActionFeedbackUseCase(
      eventStore: eventStore,
      ids: ids,
      clock: clock,
    );
    final protocol = PersonalOsAgentProtocolService(
      eventStore: eventStore,
      strategyLoop: strategyLoop,
      actionFeedback: actionFeedback,
      contextSource: EventBackedAgentContextSource(
        eventStore: eventStore,
        profileId: profileId,
      ),
      ids: ids,
      clock: clock,
    );
    final strategyController = StrategyLoopController(
      protocol: protocol,
      strategyLoop: strategyLoop,
      actionFeedback: actionFeedback,
      profileId: profileId,
      user: userActor,
    );
    return AppComposition(
      eventStore: eventStore,
      mode: mode,
      strategyController: strategyController,
      controller: AppController(
        analyzeAppearance: useCase,
        actionFeedback: actionFeedback,
        profileId: profileId,
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
        modelCapabilities:
            resolvedModelGateway is AppearanceModelCapabilityGateway
                ? resolvedModelGateway as AppearanceModelCapabilityGateway
                : null,
        modelCredentials:
            resolvedModelGateway is AppearanceModelCredentialGateway
                ? resolvedModelGateway as AppearanceModelCredentialGateway
                : null,
        actor: userActor,
        onVaultLocked: strategyController.reset,
        vaultSession: vaultSession,
        secureVault: secureVault,
        sessionCoordinator: sessionCoordinator,
      ),
    );
  }
}

final class _UnavailableEventStore implements EventStore {
  const _UnavailableEventStore();

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    throw const PersistenceException.writeFailed();
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    throw const PersistenceException.readFailed();
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    throw const PersistenceException.readFailed();
  }
}

final class _UnavailableSecureUnlockPort implements SecureUnlockPort {
  const _UnavailableSecureUnlockPort();

  @override
  Future<UnlockGrant> requestUnlock(UnlockRequest request) async {
    throw const SecurityException(SecurityErrorCode.unlockUnavailable);
  }
}

final class _UnavailableSecureVaultPort implements SecureVaultPort {
  const _UnavailableSecureVaultPort();

  @override
  Future<OpaqueVaultSession> open({required UnlockGrant grant}) async {
    throw const SecurityException(SecurityErrorCode.providerUnavailable);
  }

  @override
  Future<void> close(OpaqueVaultSession session) async {
    throw const SecurityException(SecurityErrorCode.providerUnavailable);
  }
}

final class _UnavailableAppearanceAnalysisGateway
    implements AppearanceAnalysisGateway, AppearanceModelCapabilityGateway {
  const _UnavailableAppearanceAnalysisGateway();

  @override
  Future<AppearanceAnalysisResult> analyze(AppearanceAnalysisInput input) async {
    throw AppearanceModelGatewayFailure(
      AppearanceModelGatewayFailureCode.adapterUnavailable,
    );
  }

  @override
  Future<AppearanceModelCapabilities> inspectCapabilities() async =>
      AppearanceModelCapabilities(
        configured: false,
        supportedBoundaries: const <AppearanceProcessingBoundary>{},
        runtimeCredentialReady: false,
      );
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
