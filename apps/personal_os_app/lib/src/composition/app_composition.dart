import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import '../controller/app_controller.dart';
import 'android_platform_security_bridge.dart';
import 'method_channel_appearance_analysis_gateway.dart';
import 'method_channel_controlled_source_port.dart';
import 'method_channel_source_blob_ingestion_port.dart';
import 'native_sqlcipher_event_store.dart';
import 'native_sqlcipher_session_coordinator.dart';
import 'windows_platform_security_bridge.dart';

enum AppExperienceMode { syntheticDemo, secureVault }

/// Composition root for the shipped application and explicit test/demo modes.
/// Widgets never reach persistence, security, source, or model adapters directly.
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

  /// Runtime composition used by the shipped application.
  ///
  /// Android owns the current complete native vault path. Windows has a
  /// dedicated security protocol boundary but storage remains deliberately
  /// unavailable until a trusted Windows Vault adapter is implemented. Every
  /// other unsupported platform fails closed rather than entering demo mode.
  factory AppComposition.forCurrentPlatform() =>
      AppComposition.forTargetPlatform(defaultTargetPlatform);

  /// Explicit target selection keeps production dispatch testable without
  /// mutating Flutter's process-wide platform override.
  factory AppComposition.forTargetPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android => AppComposition.secureVault(),
        TargetPlatform.windows => AppComposition.windowsSecureBoundary(),
        _ => AppComposition.unsupportedSecurePlatform(),
      };

  /// Windows production boundary before encrypted storage is available.
  ///
  /// User-presence/authentication can be wired to the dedicated Windows native
  /// channel without duplicating the Dart security protocol. Even if native
  /// authentication succeeds, [_UnavailableSecureVaultPort] still refuses to
  /// open a Vault, so the shell cannot expose or persist protected state until
  /// Windows key protection + SQLCipher are implemented and reviewed.
  factory AppComposition.windowsSecureBoundary({
    PlatformSecurityBridge? securityBridge,
    MethodChannel? securityChannel,
  }) {
    final bridge = securityBridge ??
        WindowsPlatformSecurityBridge(channel: securityChannel);
    const eventStore = _UnavailableEventStore();
    return _build(
      eventStore: eventStore,
      mode: AppExperienceMode.secureVault,
      vaultSession: DefaultVaultSession(DeviceSecureUnlockAdapter(bridge)),
      secureVault: const _UnavailableSecureVaultPort(),
      modelGateway: const _UnavailableAppearanceAnalysisGateway(),
    );
  }

  /// Fail-closed shell for a shipped platform without a trusted native adapter.
  /// The UI can start and explain that unlock is unavailable, but it cannot
  /// unlock, ingest media, persist user events, or invoke any model gateway.
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

  /// Android secure composition never falls back to a synthetic model gateway.
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
        modelCapabilities:
            resolvedModelGateway is AppearanceModelCapabilityGateway
                ? resolvedModelGateway as AppearanceModelCapabilityGateway
                : null,
        modelCredentials:
            resolvedModelGateway is AppearanceModelCredentialGateway
                ? resolvedModelGateway as AppearanceModelCredentialGateway
                : null,
        actor: ActorRef(
          actorId: 'primary-user',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
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
