import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/controller/app_controller.dart';

void main() {
  testWidgets(
    'first launch gates behind Vault and exposes observation history',
    (tester) async {
      await tester.pumpWidget(
        PersonalOsApp(composition: AppComposition.inMemoryDemo()),
      );

      expect(find.byKey(const Key('unlock-vault')), findsOneWidget);
      expect(find.text('今天，从一个小改变开始'), findsNothing);

      await tester.tap(find.byKey(const Key('unlock-vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始首次分析'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('analysis-consent')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('analysis-consent')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('analyze-reference')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('analyze-reference')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('分析'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已记录 1 条观察'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lock-vault')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlock-vault')), findsOneWidget);
    },
  );

  test(
    'controlled source journey returns only opaque BlobRef and restores history',
    () async {
      final harness = _DogfoodHarness();
      final writer = harness.controller();
      writer.unlockVault();
      await writer.setConsent(true);

      await writer.pickPhotoAndAnalyze(observationContext: 'front, daylight');

      expect(writer.submission, SubmissionStatus.succeeded);
      expect(writer.result, isNotNull);
      expect(harness.source.issued, hasLength(1));
      expect(harness.source.released, contains(harness.source.issued.single));
      expect(harness.ingestion.tokens, [harness.source.issued.single]);
      expect(harness.ingestion.discarded, isEmpty);
      expect(harness.store.readEvents().toString(),
          isNot(contains(harness.source.issued.single.value)));

      // This recreates the volatile controller against the same event store.
      // It is a process-restart surrogate; the real process-kill check is in
      // the Redmi runbook and must not be inferred from this test.
      final reader = harness.controller(withSessionQuery: true);
      reader.unlockVault();
      await Future<void>.delayed(Duration.zero);
      await reader.bootstrap();

      expect(reader.observationCount, 1);
      expect(reader.latestObservation?.mediaType, 'image/*');
      expect(reader.observations.toString(),
          isNot(contains(harness.source.issued.single.value)));
      reader.lockVault();
      expect(reader.observationCount, 0);
      expect(reader.result, isNull);
    },
  );

  test('cancel and permission denial stay fail-closed before analysis',
      () async {
    final cancelled = _DogfoodHarness();
    final cancelledController = cancelled.controller()..unlockVault();
    await cancelledController.setConsent(true);
    cancelled.source.nextFailure = ControlledSourceFailureCode.cancelled;
    await cancelledController.pickPhotoAndAnalyze(
      observationContext: 'front, daylight',
    );
    expect(cancelledController.submission, SubmissionStatus.failed);
    expect(cancelledController.errorCode, 'source_unavailable');
    expect(cancelled.ingestion.tokens, isEmpty);

    final denied = _DogfoodHarness();
    final deniedController = denied.controller()..unlockVault();
    await deniedController.setConsent(true);
    denied.source.nextFailure = ControlledSourceFailureCode.denied;
    await deniedController.pickPhotoAndAnalyze(
      observationContext: 'front, daylight',
    );
    expect(deniedController.submission, SubmissionStatus.failed);
    expect(deniedController.errorCode, 'source_denied');
    expect(denied.ingestion.tokens, isEmpty);
  });

  test('locked Vault and missing consent do not invoke the source boundary',
      () async {
    final locked = _DogfoodHarness();
    final lockedController = locked.controller();
    await lockedController.pickPhotoAndAnalyze(
      observationContext: 'front, daylight',
    );
    expect(lockedController.errorCode, 'vault_locked');
    expect(locked.source.issued, isEmpty);

    final noConsent = _DogfoodHarness();
    final noConsentController = noConsent.controller()..unlockVault();
    await noConsentController.pickPhotoAndAnalyze(
      observationContext: 'front, daylight',
    );
    expect(noConsentController.errorCode, 'consent_required');
    expect(noConsent.source.issued, isEmpty);
  });

  test('analysis failure rolls back the newly ingested BlobRef', () async {
    final harness = _DogfoodHarness()..analysisFailure = true;
    final controller = harness.controller()..unlockVault();
    await controller.setConsent(true);

    await controller.pickPhotoAndAnalyze(observationContext: 'front, daylight');

    expect(controller.submission, SubmissionStatus.failed);
    expect(controller.errorCode, AppearanceFailureCode.analysisFailed);
    expect(harness.ingestion.tokens, hasLength(1));
    expect(harness.ingestion.discarded, hasLength(1));
    expect(harness.ingestion.discarded.single.value, startsWith('blob://'));
  });
}

final class _DogfoodHarness {
  final InMemoryEventStore store = InMemoryEventStore();
  final _ControlledSource source = _ControlledSource();
  final _SourceIngestion ingestion = _SourceIngestion();
  bool analysisFailure = false;

  AppController controller({bool withSessionQuery = false}) {
    final ids = _Ids();
    final gateway = _Gateway(() => analysisFailure);
    final policy = AppearancePolicyAdapter(
      consents: InMemoryConsentRevisionRepository(
        initialGrants: <ConsentGrant>[_grant()],
      ),
      clock: FixedPolicyClock(DateTime.utc(2026, 8, 20)),
    );
    final analysis = AnalyzeAppearanceUseCase(
      eventStore: store,
      modelGateway: gateway,
      policy: policy,
      ids: ids,
      clock: const _Clock(),
    );
    return AppController(
      analyzeAppearance: analysis,
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      recordObservation: RecordObservationUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      consentLifecycle: ConsentLifecycleUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      sessionQuery:
          withSessionQuery ? AppearanceSessionQueryHandler(store) : null,
      sourcePort: source,
      ingestAppearanceFromSource: IngestAppearanceFromSourceUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: ids,
          clock: const _Clock(),
        ),
        analyzeAppearance: analysis,
      ),
      profileId: EntityId('primary-user'),
      actor: ActorRef(
        actorId: 'primary-user',
        actorType: ActorType.user,
        authoritySource: 'dogfood-test',
      ),
    );
  }
}

ConsentGrant _grant() => ConsentGrant(
      consentId: 'local-appearance-consent',
      revision: 1,
      subjectId: 'primary-user',
      authorizedActorId: 'primary-user',
      purposes: const <String>{'appearance_review'},
      resources: const <String>{'portrait'},
      actions: const <String>{'derive'},
      maximumSensitivity: Sensitivity.d3,
      validFrom: DateTime.utc(2026, 8, 19),
      validUntil: DateTime.utc(2026, 8, 21),
      status: ConsentStatus.active,
    );

final class _SourceIngestion implements SourceBlobIngestionPort {
  final List<OpaqueSourceToken> tokens = <OpaqueSourceToken>[];
  final List<BlobRef> discarded = <BlobRef>[];

  @override
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    tokens.add(source);
    return BlobRef('blob://dogfood-encrypted-0001');
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {
    discarded.add(ref);
  }
}

final class _ControlledSource implements ControlledSourcePort {
  final List<OpaqueSourceToken> issued = <OpaqueSourceToken>[];
  final Set<String> released = <String>{};
  ControlledSourceFailureCode? nextFailure;

  @override
  Future<ControlledSourceCapabilities> capabilities() async =>
      const ControlledSourceCapabilities(photoPicker: true, camera: false);

  @override
  Future<OpaqueSourceToken> pickPhoto() async {
    _throwIfConfigured();
    final token = OpaqueSourceToken('dogfood_photo_token_01');
    issued.add(token);
    return token;
  }

  @override
  Future<OpaqueSourceToken> capturePhoto() async {
    _throwIfConfigured();
    throw const ControlledSourceException(
      ControlledSourceFailureCode.unavailable,
    );
  }

  @override
  Future<String> ingestToBlob(OpaqueSourceToken token) async =>
      'blob://dogfood-encrypted-0001';

  @override
  Future<void> deleteBlob(String blobRef) async {}

  @override
  Future<void> release(OpaqueSourceToken token) async {
    released.add(token.value);
  }

  void _throwIfConfigured() {
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw ControlledSourceException(failure);
  }
}

final class _Gateway implements AppearanceAnalysisGateway {
  _Gateway(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<AppearanceAnalysisResult> analyze(
      AppearanceAnalysisInput input) async {
    if (shouldFail()) throw StateError('synthetic analysis failure');
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
