import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';

/// In-memory exact-revision repository for policy composition and tests.
///
/// Every revision is append-only. Reads return a fresh immutable value snapshot.
/// Status and validity are deliberately not interpreted here: revoked,
/// superseded, future, and expired grants must reach the policy evaluator.
final class InMemoryConsentRevisionRepository
    implements ConsentRevisionRepository {
  InMemoryConsentRevisionRepository({
    Iterable<ConsentGrant> initialGrants = const [],
  }) {
    for (final grant in initialGrants) {
      add(grant);
    }
  }

  final Map<_ConsentRevisionKey, ConsentGrant> _revisions = {};

  /// Adds one immutable revision. Existing revisions cannot be replaced.
  void add(ConsentGrant grant) {
    final key = _ConsentRevisionKey(grant.consentId, grant.revision);
    if (_revisions.containsKey(key)) {
      throw StateError(
        'consent_revision_already_exists:${grant.consentId}:${grant.revision}',
      );
    }
    _revisions[key] = _snapshot(grant);
  }

  @override
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  }) async {
    final stored = _revisions[_ConsentRevisionKey(consentId, revision)];
    return stored == null ? null : _snapshot(stored);
  }

  static ConsentGrant _snapshot(ConsentGrant grant) => ConsentGrant(
        consentId: grant.consentId,
        revision: grant.revision,
        subjectId: grant.subjectId,
        authorizedActorId: grant.authorizedActorId,
        purposes: grant.purposes,
        resources: grant.resources,
        actions: grant.actions,
        maximumSensitivity: grant.maximumSensitivity,
        validFrom: grant.validFrom,
        validUntil: grant.validUntil,
        status: grant.status,
      );
}

final class _ConsentRevisionKey {
  const _ConsentRevisionKey(this.consentId, this.revision);

  final String consentId;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is _ConsentRevisionKey &&
      other.consentId == consentId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(consentId, revision);
}
