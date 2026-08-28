import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
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

  ConsentGrant grant({
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
        consentId: 'consent-1',
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

final class _FixedClock implements PolicyClock {
  const _FixedClock(this.value);
  final DateTime value;

  @override
  DateTime now() => value;
}
