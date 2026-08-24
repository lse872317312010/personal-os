import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'appearance_policy_adapter.dart';

/// Adds the consent event stream as an authoritative overlay to a legacy
/// revision lookup. In particular, a persisted revoke cannot be hidden by an
/// older active fallback grant.
final class EventBackedConsentRevisionRepository
    implements ConsentRevisionRepository {
  const EventBackedConsentRevisionRepository({
    required EventStore eventStore,
    required ConsentRevisionRepository fallback,
  })  : _eventStore = eventStore,
        _fallback = fallback;

  final EventStore _eventStore;
  final ConsentRevisionRepository _fallback;

  @override
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  }) async {
    var grant = await _fallback.findRevision(
      consentId: consentId,
      revision: revision,
    );
    final events = await _eventStore.readBySubject(
      ObjectRef(type: 'consent', id: EntityId(consentId)),
    );
    for (final event in events) {
      final eventRevision = _int(event.payload['consent_revision']);
      if (eventRevision != revision) continue;
      if (event.eventType == EventTypes.consentGranted) {
        // A matching event supersedes fallback state. A malformed grant is
        // untrusted and therefore denied rather than silently falling back.
        grant = _grantFromEvent(event);
      } else if (event.eventType == EventTypes.consentRevoked &&
          grant != null) {
        grant = _withStatus(grant, ConsentStatus.revoked);
      }
    }
    return grant;
  }
}

ConsentGrant? _grantFromEvent(EventEnvelope event) {
  final payload = event.payload;
  final validFrom = _time(payload['valid_from']);
  final validUntil = _time(payload['valid_until']);
  final consentId = payload['consent_id'];
  final subjectId = payload['subject_id'];
  final actorId = payload['authorized_actor_id'];
  final revision = _int(payload['consent_revision']);
  if (consentId is! String ||
      subjectId is! String ||
      actorId is! String ||
      revision == null ||
      validFrom == null ||
      validUntil == null) {
    return null;
  }
  return ConsentGrant(
    consentId: consentId,
    revision: revision,
    subjectId: subjectId,
    authorizedActorId: actorId,
    purposes: _strings(payload['purposes']),
    resources: _strings(payload['resources']),
    actions: _strings(payload['actions']),
    maximumSensitivity: _sensitivity(payload['maximum_sensitivity']),
    validFrom: validFrom,
    validUntil: validUntil,
    status: ConsentStatus.active,
  );
}

ConsentGrant _withStatus(ConsentGrant grant, ConsentStatus status) =>
    ConsentGrant(
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
      status: status,
    );

int? _int(Object? value) => value is int ? value : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

Set<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toSet() : <String>{};

Sensitivity _sensitivity(Object? value) => switch (value) {
      'd0' => Sensitivity.d0,
      'd1' => Sensitivity.d1,
      'd2' => Sensitivity.d2,
      'd4' => Sensitivity.d4,
      _ => Sensitivity.d3,
    };
