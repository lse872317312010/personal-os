import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory_policy/in_memory_policy.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 8, 20);

  ConsentGrant grant({
    required int revision,
    ConsentStatus status = ConsentStatus.active,
    DateTime? validUntil,
    Set<String> purposes = const {'appearance_review'},
  }) =>
      ConsentGrant(
        consentId: 'consent-1',
        revision: revision,
        subjectId: 'profile-1',
        authorizedActorId: 'user-1',
        purposes: purposes,
        resources: const {'portrait'},
        actions: const {'derive'},
        maximumSensitivity: Sensitivity.d3,
        validFrom: start,
        validUntil: validUntil ?? start.add(const Duration(days: 1)),
        status: status,
      );

  test('finds only the exact consent id and revision', () async {
    final repository = InMemoryConsentRevisionRepository(
      initialGrants: [grant(revision: 1), grant(revision: 2)],
    );

    expect(
        (await repository.findRevision(
          consentId: 'consent-1',
          revision: 1,
        ))
            ?.revision,
        1);
    expect(
        await repository.findRevision(
          consentId: 'consent-1',
          revision: 3,
        ),
        isNull);
    expect(
        await repository.findRevision(
          consentId: 'another-consent',
          revision: 2,
        ),
        isNull);
  });

  test('does not fall back to latest revision', () async {
    final repository = InMemoryConsentRevisionRepository(
      initialGrants: [grant(revision: 8)],
    );

    expect(
        await repository.findRevision(
          consentId: 'consent-1',
          revision: 7,
        ),
        isNull);
  });

  test('returns revoked and expired revisions without filtering', () async {
    final revoked = grant(revision: 1, status: ConsentStatus.revoked);
    final expired = grant(revision: 2, validUntil: start);
    final repository = InMemoryConsentRevisionRepository(
      initialGrants: [revoked, expired],
    );

    expect(
        (await repository.findRevision(
          consentId: 'consent-1',
          revision: 1,
        ))
            ?.status,
        ConsentStatus.revoked);
    expect(
        (await repository.findRevision(
          consentId: 'consent-1',
          revision: 2,
        ))
            ?.validUntil,
        start);
  });

  test('takes collection snapshots and returns fresh value snapshots',
      () async {
    final mutablePurposes = <String>{'appearance_review'};
    final repository = InMemoryConsentRevisionRepository();
    repository.add(grant(revision: 1, purposes: mutablePurposes));
    mutablePurposes.add('unexpected');

    final first = await repository.findRevision(
      consentId: 'consent-1',
      revision: 1,
    );
    final second = await repository.findRevision(
      consentId: 'consent-1',
      revision: 1,
    );

    expect(first?.purposes, {'appearance_review'});
    expect(() => first?.purposes.add('mutate'), throwsUnsupportedError);
    expect(identical(first, second), isFalse);
  });

  test('rejects replacement of an existing revision', () {
    final repository = InMemoryConsentRevisionRepository(
      initialGrants: [grant(revision: 1)],
    );

    expect(() => repository.add(grant(revision: 1)), throwsStateError);
  });

  test('fixed clock returns the injected instant in UTC', () {
    final localInstant = DateTime.parse('2026-08-20T21:30:00+09:00');
    final clock = FixedPolicyClock(localInstant);

    expect(clock.now(), DateTime.utc(2026, 8, 20, 12, 30));
    expect(clock.now().isUtc, isTrue);
  });
}
