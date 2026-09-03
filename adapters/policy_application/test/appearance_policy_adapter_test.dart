import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);
  final actor = ActorRef(
    actorId: 'user-1',
    actorType: ActorType.user,
    authoritySource: 'local',
  );
  final profileId = EntityId('profile-1');
  final ref = ObjectRef(
    type: 'consent',
    id: EntityId('consent-1'),
    revision: Revision(7),
  );
  final externalRef = ObjectRef(
    type: 'consent',
    id: EntityId('external-consent-1'),
    revision: Revision(3),
  );

  ConsentGrant grant({
    String consentId = 'consent-1',
    ConsentStatus status = ConsentStatus.active,
    DateTime? validUntil,
    int revision = 7,
    String subjectId = 'profile-1',
    String actorId = 'user-1',
    Set<String> purposes = const {'appearance_review'},
    Set<String> resources = const {'portrait'},
    Set<String> actions = const {'derive'},
    Sensitivity maximumSensitivity = Sensitivity.d3,
  }) =>
      ConsentGrant(
        consentId: consentId,
        revision: revision,
        subjectId: subjectId,
        authorizedActorId: actorId,
        purposes: purposes,
        resources: resources,
        actions: actions,
        maximumSensitivity: maximumSensitivity,
        validFrom: now.subtract(const Duration(days: 1)),
        validUntil: validUntil ?? now.add(const Duration(days: 1)),
        status: status,
      );

  Future<PolicyVerdict> authorize(ConsentGrant? stored) async =>
      await AppearancePolicyAdapter(
        consents: _Repository(stored),
        clock: _FixedClock(now),
      ).authorizeAnalysis(
        actor: actor,
        profileId: profileId,
        consentRefs: [ref],
        sensitivity: Sensitivity.d3,
      );

  test('denies missing consent', () async {
    final result = await authorize(null);
    expect(result.allowed, isFalse);
    expect(result.reasonCode, PolicyReason.consentMissing);
  });

  test('denies revoked consent', () async {
    final result = await authorize(grant(status: ConsentStatus.revoked));
    expect(result.allowed, isFalse);
    expect(result.reasonCode, PolicyReason.consentInactive);
  });

  test('denies expired consent at the exclusive boundary', () async {
    final result = await authorize(grant(validUntil: now));
    expect(result.allowed, isFalse);
    expect(result.reasonCode, PolicyReason.consentExpired);
  });

  test('denies every mismatched scope dimension', () async {
    final cases = <(ConsentGrant, String)>[
      (grant(subjectId: 'other-profile'), PolicyReason.consentSubjectMismatch),
      (grant(actorId: 'other-actor'), PolicyReason.consentActorMismatch),
      (
        grant(purposes: {'another_purpose'}),
        PolicyReason.consentPurposeMismatch,
      ),
      (
        grant(resources: {'another_resource'}),
        PolicyReason.consentResourceMismatch
      ),
      (grant(actions: {'another_action'}), PolicyReason.consentActionMismatch),
      (
        grant(maximumSensitivity: Sensitivity.d2),
        PolicyReason.consentSensitivityExceeded,
      ),
      (grant(revision: 8), PolicyReason.consentRevisionMismatch),
    ];
    for (final (stored, reason) in cases) {
      final result = await authorize(stored);
      expect(result.allowed, isFalse);
      expect(result.reasonCode, reason);
    }
  });

  test('allows exact pinned scope', () async {
    final result = await authorize(grant());
    expect(result.allowed, isTrue);
    expect(result.reasonCode, isNull);
  });

  test('external processing requires a separate exact consent scope',
      () async {
    final externalGrant = grant(
      consentId: 'external-consent-1',
      revision: 3,
      purposes: {'external_processing'},
      actions: {'transmit'},
    );
    final adapter = AppearancePolicyAdapter(
      consents: _MultiRepository({
        'consent-1@7': grant(),
        'external-consent-1@3': externalGrant,
      }),
      clock: _FixedClock(now),
    );

    final result = await adapter.authorizeAnalysis(
      actor: actor,
      profileId: profileId,
      consentRefs: [ref, externalRef],
      sensitivity: Sensitivity.d3,
      processingBoundary: AppearanceProcessingBoundary.externalProcessor,
    );

    expect(result.allowed, isTrue);
  });

  test('external processing fails closed without transmit consent', () async {
    final secondRef = ObjectRef(
      type: 'consent',
      id: EntityId('consent-2'),
      revision: Revision(1),
    );
    final adapter = AppearancePolicyAdapter(
      consents: _MultiRepository({
        'consent-1@7': grant(),
        'consent-2@1': grant(consentId: 'consent-2', revision: 1),
      }),
      clock: _FixedClock(now),
    );

    final result = await adapter.authorizeAnalysis(
      actor: actor,
      profileId: profileId,
      consentRefs: [ref, secondRef],
      sensitivity: Sensitivity.d3,
      processingBoundary: AppearanceProcessingBoundary.externalProcessor,
    );

    expect(result.allowed, isFalse);
    expect(
      result.reasonCode,
      AppearancePolicyReason.externalProcessingConsentRequired,
    );
  });

  test('external processing rejects duplicate consent references', () async {
    final adapter = AppearancePolicyAdapter(
      consents: _Repository(grant()),
      clock: _FixedClock(now),
    );

    final result = await adapter.authorizeAnalysis(
      actor: actor,
      profileId: profileId,
      consentRefs: [ref, ref],
      sensitivity: Sensitivity.d3,
      processingBoundary: AppearanceProcessingBoundary.externalProcessor,
    );

    expect(result.reasonCode, AppearancePolicyReason.invalidConsentReference);
  });

  test('denies unpinned, duplicate, and wrong-type references', () async {
    final adapter = AppearancePolicyAdapter(
      consents: _Repository(grant()),
      clock: _FixedClock(now),
    );
    for (final refs in <List<ObjectRef>>[
      [ObjectRef(type: 'consent', id: EntityId('consent-1'))],
      [ref, ref],
      [
        ObjectRef(
            type: 'claim', id: EntityId('consent-1'), revision: Revision(7))
      ],
    ]) {
      final result = await adapter.authorizeAnalysis(
        actor: actor,
        profileId: profileId,
        consentRefs: refs,
        sensitivity: Sensitivity.d3,
      );
      expect(result.reasonCode, AppearancePolicyReason.invalidConsentReference);
    }
  });

  test('repository failure and classification downgrade fail closed', () async {
    final failing = AppearancePolicyAdapter(
      consents: _Repository.fail(),
      clock: _FixedClock(now),
    );
    var result = await failing.authorizeAnalysis(
      actor: actor,
      profileId: profileId,
      consentRefs: [ref],
      sensitivity: Sensitivity.d3,
    );
    expect(result.reasonCode, AppearancePolicyReason.repositoryFailure);

    result = await AppearancePolicyAdapter(
      consents: _Repository(grant()),
      clock: _FixedClock(now),
    ).authorizeAnalysis(
      actor: actor,
      profileId: profileId,
      consentRefs: [ref],
      sensitivity: Sensitivity.d2,
    );
    expect(result.reasonCode, AppearancePolicyReason.invalidSensitivity);
  });
}

final class _Repository implements ConsentRevisionRepository {
  _Repository(this.value) : throwsOnRead = false;
  _Repository.fail()
      : value = null,
        throwsOnRead = true;

  final ConsentGrant? value;
  final bool throwsOnRead;

  @override
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  }) async {
    if (throwsOnRead) throw StateError('unavailable');
    return value;
  }
}

final class _MultiRepository implements ConsentRevisionRepository {
  const _MultiRepository(this.values);

  final Map<String, ConsentGrant> values;

  @override
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  }) async =>
      values['$consentId@$revision'];
}

final class _FixedClock implements PolicyClock {
  const _FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}
