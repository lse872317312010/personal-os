import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_application/application.dart';
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

import 'package:personal_os_app/src/composition/native_sqlcipher_session_coordinator.dart';
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

  test('source entry stays fail-closed without a source port', () async {
    final controller = _controller(_CountingGateway())..unlockVault();
    await controller.setConsent(true);

    await controller.pickPhotoAndAnalyze(observationContext: 'front');

    expect(controller.submission, SubmissionStatus.failed);
    expect(controller.errorCode, 'source_unavailable');
  });

  test('photo-picker cancellation remains a distinct safe outcome', () async {
    final gateway = _CountingGateway();
    final source = FakeControlledSourcePort()
      ..nextFailure = ControlledSourceFailureCode.cancelled;
    final ingestion = _SourceIngestion();
    final controller = _controller(
      gateway,
      sourcePort: source,
      sourceBlobIngestion: ingestion,
    )..unlockVault();
    await controller.setConsent(true);

    await controller.pickPhotoAndAnalyze(observationContext: 'front');

    expect(controller.errorCode, 'source_cancelled');
    expect(gateway.calls, 0);
    expect(ingestion.calls, 0);
  });

  test('unconfigured model is rejected before observation or gateway access',
      () async {
    final store = InMemoryEventStore();
    final gateway = _CountingGateway();
    final controller = _controller(
      gateway,
      store: store,
      withObservation: true,
      modelCapabilities: const _FixedCapabilities(configured: false),
    )..unlockVault();
    await controller.setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.errorCode, 'model.adapter_unavailable');
    expect(gateway.calls, 0);
    expect(
      store.readEvents().map((record) => record.event.eventType),
      isNot(contains(EventTypes.observationRecorded)),
    );
  });

  test('external consent is persisted and revoked independently', () async {
    final store = InMemoryEventStore();
    final controller = _controller(
      _CountingGateway(),
      store: store,
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
      ),
    )..unlockVault();
    await controller.setConsent(true);

    await controller.setExternalProcessingConsent(true);

    expect(controller.externalProcessingConsentGranted, isTrue);
    expect(controller.consentGranted, isTrue);
    expect(
      store.readEvents().map((record) => record.event).where(
            (event) =>
                event.eventType == EventTypes.consentGranted &&
                event.payload['scope'] == 'externalProcessing',
          ),
      hasLength(1),
    );

    final restored = _controller(
      _CountingGateway(),
      store: store,
      withSessionQuery: true,
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
      ),
    )..unlockVault();
    await restored.bootstrap();
    expect(restored.externalProcessingConsentGranted, isTrue);
    expect(restored.consentGranted, isTrue);

    await controller.setExternalProcessingConsent(false);

    expect(controller.externalProcessingConsentGranted, isFalse);
    expect(controller.consentGranted, isTrue);
  });

  test('external-only model is rejected before access without consent',
      () async {
    final gateway = _CountingGateway();
    final controller = _controller(
      gateway,
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
      ),
    )..unlockVault();
    await controller.setConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.errorCode, 'external_processing_consent_required');
    expect(gateway.calls, 0);
  });

  test('external transport configuration is visible without credentials',
      () async {
    final controller = _controller(
      _CountingGateway(),
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
        credentialReady: false,
      ),
    )..unlockVault();

    await Future<void>.delayed(Duration.zero);

    expect(controller.modelConfigured, isTrue);
    expect(controller.externalProcessingConfigured, isTrue);
    expect(controller.externalProcessingAvailable, isFalse);
    expect(controller.onDeviceProcessingAvailable, isFalse);
    expect(controller.analysisPreflightReady, isFalse);
  });

  test('runtime credential configure and clear refresh capability state',
      () async {
    final credentials = _CredentialCapabilities();
    final controller = _controller(
      _CountingGateway(),
      modelCapabilities: credentials,
      modelCredentials: credentials,
    )..unlockVault();
    await Future<void>.delayed(Duration.zero);

    await controller.configureExternalModelCredential();

    expect(credentials.configureCalls, 1);
    expect(controller.externalProcessingAvailable, isTrue);
    expect(controller.credentialOperationRunning, isFalse);
    expect(controller.analysisPreflightReady, isFalse);

    await controller.setConsent(true);
    await controller.setExternalProcessingConsent(true);
    expect(controller.analysisPreflightReady, isTrue);

    await controller.clearExternalModelCredential();

    expect(credentials.clearCalls, 1);
    expect(controller.externalProcessingAvailable, isFalse);
    expect(controller.externalProcessingConfigured, isTrue);
    expect(controller.analysisPreflightReady, isFalse);
  });

  test('one-call external credential is refreshed after analysis', () async {
    final credentials = _CredentialCapabilities();
    final controller = _controller(
      _CountingGateway(),
      eventBackedPolicy: true,
      modelCapabilities: credentials,
      modelCredentials: credentials,
    )..unlockVault();
    await Future<void>.delayed(Duration.zero);
    await controller.setConsent(true);
    await controller.configureExternalModelCredential();
    await controller.setExternalProcessingConsent(true);
    credentials.consumeReadyOnInspect = true;

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
      externalTransmissionConfirmed: true,
    );

    expect(controller.submission, SubmissionStatus.succeeded);
    expect(controller.externalProcessingAvailable, isFalse);
    expect(controller.externalProcessingConfigured, isTrue);
  });

  test('locking the vault clears an unused native model credential', () async {
    final credentials = _CredentialCapabilities();
    final controller = _controller(
      _CountingGateway(),
      modelCapabilities: credentials,
      modelCredentials: credentials,
    )..unlockVault();
    await Future<void>.delayed(Duration.zero);
    await controller.configureExternalModelCredential();

    controller.lockVault();
    await Future<void>.delayed(Duration.zero);

    expect(credentials.clearCalls, 1);
    expect(credentials.ready, isFalse);
    expect(controller.vaultUnlocked, isFalse);
  });

  test('external consent selects external boundary with both consent refs',
      () async {
    final store = InMemoryEventStore();
    final gateway = _CountingGateway();
    final controller = _controller(
      gateway,
      store: store,
      eventBackedPolicy: true,
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
      ),
    )..unlockVault();
    await controller.setConsent(true);
    await controller.setExternalProcessingConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
      externalTransmissionConfirmed: true,
    );

    expect(controller.submission, SubmissionStatus.succeeded);
    expect(
      gateway.lastInput?.processingBoundary,
      AppearanceProcessingBoundary.externalProcessor,
    );
    final claimEvent = store
        .readEvents()
        .map((record) => record.event)
        .firstWhere((event) => event.eventType == EventTypes.claimProposed);
    expect(claimEvent.consentRefs, hasLength(2));
  });

  test('external analysis requires a fresh transmission confirmation',
      () async {
    final store = InMemoryEventStore();
    final gateway = _CountingGateway();
    final controller = _controller(
      gateway,
      store: store,
      withObservation: true,
      eventBackedPolicy: true,
      modelCapabilities: const _FixedCapabilities(
        configured: true,
        external: true,
        onDevice: false,
      ),
    )..unlockVault();
    await controller.setConsent(true);
    await controller.setExternalProcessingConsent(true);

    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );

    expect(controller.errorCode, 'external_transmission_confirmation_required');
    expect(gateway.calls, 0);
    expect(
      store.readEvents().map((record) => record.event.eventType),
      isNot(contains(EventTypes.observationRecorded)),
    );
  });

  test('consent change during capability refresh cannot bypass confirmation',
      () async {
    final gateway = _CountingGateway();
    final capabilities = _BlockingCapabilities();
    final controller = _controller(
      gateway,
      eventBackedPolicy: true,
      modelCapabilities: capabilities,
    )..unlockVault();
    await Future<void>.delayed(Duration.zero);
    await controller.setConsent(true);
    capabilities.blockNextInspection();

    final analysis = controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    await capabilities.inspectionBlocked;
    await controller.setExternalProcessingConsent(true);
    capabilities.releaseInspection();
    await analysis;

    expect(controller.errorCode, 'external_transmission_confirmation_required');
    expect(gateway.calls, 0);
  });

  test('raw path is rejected before any gateway call', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway)..unlockVault();
    await controller.setConsent(true);

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
      ..unlockVault();
    await controller.setConsent(true);

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

  test('failed retry clears the prior success and stays out of claims',
      () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway)..unlockVault();
    await controller.setConsent(true);
    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    expect(controller.result, isNotNull);

    gateway.fail = true;
    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/two',
      observationContext: 'front',
    );

    expect(controller.submission, SubmissionStatus.failed);
    expect(controller.errorCode, AppearanceFailureCode.analysisFailed);
    expect(controller.result, isNull);
    expect(controller.completedStep, 0);
  });

  test('observation failure is fail-closed before any gateway call', () async {
    final gateway = _CountingGateway();
    final controller = _controller(gateway, withObservation: true)
      ..unlockVault();
    await controller.setConsent(true);

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

    await controller.setConsent(true);
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

  test('native session expiry clears protected state and re-unlocks cleanly',
      () async {
    final coordinator = _FakeSecureSessionCoordinator();
    final vaultSession = _FakeVaultSession();
    final controller = _controller(
      _CountingGateway(),
      withSessionQuery: false,
      vaultSession: vaultSession,
      sessionCoordinator: coordinator,
    );

    controller.unlockVault();
    await Future<void>.delayed(Duration.zero);
    await controller.setConsent(true);
    await controller.analyzeBlobReference(
      blobReference: 'blob://vault/one',
      observationContext: 'front',
    );
    expect(controller.result, isNotNull);

    coordinator.invalidate(SecurityErrorCode.unlockExpired);

    expect(controller.vaultUnlocked, isFalse);
    expect(controller.result, isNull);
    expect(controller.consentGranted, isFalse);
    expect(controller.destination.name, 'home');
    expect(controller.errorCode, SecurityErrorCode.unlockExpired.wireValue);
    expect(vaultSession.isUnlocked, isFalse);

    controller.unlockVault();
    await Future<void>.delayed(Duration.zero);
    expect(controller.vaultUnlocked, isTrue);
  });

  test('secure unlock exposes progress and ignores repeated taps', () async {
    final coordinator = _FakeSecureSessionCoordinator();
    final vaultSession = _BlockingVaultSession();
    final controller = _controller(
      _CountingGateway(),
      vaultSession: vaultSession,
      sessionCoordinator: coordinator,
    );

    controller.unlockVault();
    controller.unlockVault();

    expect(controller.vaultUnlocking, isTrue);
    expect(controller.vaultUnlocked, isFalse);
    expect(vaultSession.unlockCalls, 1);

    vaultSession.completeUnlock();
    await Future<void>.delayed(Duration.zero);

    expect(controller.vaultUnlocking, isFalse);
    expect(controller.vaultUnlocked, isTrue);
    expect(controller.errorCode, isNull);
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
  VaultSession? vaultSession,
  SecureSessionCoordinator? sessionCoordinator,
  AppearanceModelCapabilityGateway? modelCapabilities,
  AppearanceModelCredentialGateway? modelCredentials,
  bool eventBackedPolicy = false,
  ControlledSourcePort? sourcePort,
  SourceBlobIngestionPort? sourceBlobIngestion,
}) {
  final eventStore = store ?? InMemoryEventStore();
  final ids = _Ids();
  gateway.eventStore = eventStore;
  final fallbackConsents = InMemoryConsentRevisionRepository(
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
  );
  final policy = AppearancePolicyAdapter(
    consents: eventBackedPolicy
        ? EventBackedConsentRevisionRepository(
            eventStore: eventStore,
            fallback: fallbackConsents,
          )
        : fallbackConsents,
    clock: FixedPolicyClock(DateTime.utc(2026, 8, 20)),
  );
  final analyzeAppearance = AnalyzeAppearanceUseCase(
    eventStore: eventStore,
    modelGateway: gateway,
    policy: policy,
    ids: ids,
    clock: const _Clock(),
  );
  return AppController(
    analyzeAppearance: analyzeAppearance,
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
    vaultSession: vaultSession,
    sessionCoordinator: sessionCoordinator,
    modelCapabilities: modelCapabilities,
    modelCredentials: modelCredentials,
    sourcePort: sourcePort,
    ingestAppearanceFromSource: sourceBlobIngestion == null
        ? null
        : IngestAppearanceFromSourceUseCase(
            ingestion: sourceBlobIngestion,
            recordObservation: RecordObservationUseCase(
              eventStore: eventStore,
              ids: ids,
              clock: const _Clock(),
            ),
            analyzeAppearance: analyzeAppearance,
          ),
    actor: ActorRef(
      actorId: 'me',
      actorType: ActorType.user,
      authoritySource: 'test',
    ),
  );
}

final class _SourceIngestion implements SourceBlobIngestionPort {
  int calls = 0;

  @override
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    calls++;
    return BlobRef('blob://fake-source-00000001');
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {}
}

final class _CountingGateway implements AppearanceAnalysisGateway {
  int calls = 0;
  bool fail = false;
  InMemoryEventStore? eventStore;
  List<String> eventTypesAtCall = const <String>[];
  AppearanceAnalysisInput? lastInput;

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    calls++;
    lastInput = input;
    if (fail) throw StateError('test failure');
    eventTypesAtCall =
        eventStore?.readEvents().map((e) => e.event.eventType).toList() ??
            const <String>[];
    final fixtureInput = input.processingBoundary ==
            AppearanceProcessingBoundary.onDevice
        ? input
        : AppearanceAnalysisInput(
            imageRef: input.imageRef,
            observationContext: input.observationContext,
            locale: input.locale,
            promptVersion: input.promptVersion,
          );
    return const FixtureAppearanceAnalysisGateway(
      behavior: FixtureAppearanceBehavior.syntheticSuccess,
    ).analyze(fixtureInput);
  }
}

final class _FixedCapabilities implements AppearanceModelCapabilityGateway {
  const _FixedCapabilities({
    required this.configured,
    this.onDevice = true,
    this.external = false,
    this.credentialReady,
  });

  final bool configured;
  final bool onDevice;
  final bool external;
  final bool? credentialReady;

  @override
  Future<AppearanceModelCapabilities> inspectCapabilities() async =>
      AppearanceModelCapabilities(
        configured: configured,
        supportedBoundaries: configured
            ? <AppearanceProcessingBoundary>{
                if (onDevice) AppearanceProcessingBoundary.onDevice,
                if (external) AppearanceProcessingBoundary.externalProcessor,
              }
            : const <AppearanceProcessingBoundary>{},
        runtimeCredentialReady: credentialReady ?? (configured && external),
      );
}

final class _CredentialCapabilities
    implements
        AppearanceModelCapabilityGateway,
        AppearanceModelCredentialGateway {
  bool ready = false;
  bool consumeReadyOnInspect = false;
  int configureCalls = 0;
  int clearCalls = 0;

  @override
  Future<AppearanceModelCapabilities> inspectCapabilities() async {
    final advertisedReady = ready;
    if (consumeReadyOnInspect && ready) {
      ready = false;
      consumeReadyOnInspect = false;
    }
    return AppearanceModelCapabilities(
      configured: true,
      supportedBoundaries: const <AppearanceProcessingBoundary>{
        AppearanceProcessingBoundary.externalProcessor,
      },
      runtimeCredentialReady: advertisedReady,
    );
  }

  @override
  Future<bool> configureRuntimeCredential() async {
    configureCalls++;
    ready = true;
    return true;
  }

  @override
  Future<void> clearRuntimeCredential() async {
    clearCalls++;
    ready = false;
  }
}

final class _BlockingCapabilities
    implements AppearanceModelCapabilityGateway {
  Completer<void>? _blocked;
  Completer<void>? _release;

  Future<void> get inspectionBlocked => _blocked!.future;

  void blockNextInspection() {
    _blocked = Completer<void>();
    _release = Completer<void>();
  }

  void releaseInspection() {
    _release!.complete();
  }

  @override
  Future<AppearanceModelCapabilities> inspectCapabilities() async {
    final blocked = _blocked;
    final release = _release;
    if (blocked != null && !blocked.isCompleted) {
      blocked.complete();
      await release!.future;
    }
    return AppearanceModelCapabilities(
      configured: true,
      supportedBoundaries: <AppearanceProcessingBoundary>{
        AppearanceProcessingBoundary.onDevice,
        AppearanceProcessingBoundary.externalProcessor,
      },
      runtimeCredentialReady: true,
    );
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

final class _FakeVaultSession implements VaultSession {
  VaultSessionState _state = VaultSessionState.locked;

  @override
  VaultSessionState get state => _state;

  @override
  bool get isUnlocked => state == VaultSessionState.unlocked;

  @override
  Future<void> unlock({required String reason}) async {
    _state = VaultSessionState.unlocked;
  }

  @override
  Future<void> lock() async {
    _state = VaultSessionState.locked;
  }

  @override
  UnlockGrant requireGrant({DateTime? at}) => UnlockGrant.opaque(
        id: 'fake-ticket',
        expiresAt: DateTime.utc(2099, 1, 1),
      );
}

final class _BlockingVaultSession implements VaultSession {
  final Completer<void> _unlockCompleter = Completer<void>();
  VaultSessionState _state = VaultSessionState.locked;
  int unlockCalls = 0;

  @override
  VaultSessionState get state => _state;

  @override
  bool get isUnlocked => state == VaultSessionState.unlocked;

  @override
  Future<void> unlock({required String reason}) async {
    unlockCalls++;
    await _unlockCompleter.future;
    _state = VaultSessionState.unlocked;
  }

  void completeUnlock() => _unlockCompleter.complete();

  @override
  Future<void> lock() async {
    _state = VaultSessionState.locked;
  }

  @override
  UnlockGrant requireGrant({DateTime? at}) => UnlockGrant.opaque(
        id: 'blocking-ticket',
        expiresAt: DateTime.utc(2099, 1, 1),
      );
}

final class _FakeSecureSessionCoordinator
    implements SecureSessionCoordinator {
  void Function(SecurityException error)? _handler;
  _FakeOpaqueSession? _active;

  @override
  set onSessionInvalidated(void Function(SecurityException error) handler) {
    _handler = handler;
  }

  @override
  Future<OpaqueVaultSession> open({required UnlockGrant grant}) async {
    final session = _FakeOpaqueSession();
    _active = session;
    return session;
  }

  @override
  Future<void> close(OpaqueVaultSession session) async {
    (session as _FakeOpaqueSession).active = false;
    if (identical(_active, session)) _active = null;
  }

  void invalidate(SecurityErrorCode code) {
    _active?.active = false;
    _active = null;
    _handler?.call(SecurityException(code));
  }
}

final class _FakeOpaqueSession implements OpaqueVaultSession {
  bool active = true;

  @override
  bool get isActive => active;
}
