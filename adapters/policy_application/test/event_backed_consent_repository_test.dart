import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:personal_os_policy_application/policy_application.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('persisted revoke overrides an active fallback grant', () async {
    final eventStore = _Store(<EventEnvelope>[
      _event(
        id: 'grant',
        type: EventTypes.consentGranted,
        payload: <String, Object?>{
          'consent_id': 'consent-1',
          'consent_revision': 1,
          'subject_id': 'profile-1',
          'authorized_actor_id': 'user-1',
          'purposes': const <String>['appearance_review'],
          'resources': const <String>['portrait'],
          'actions': const <String>['derive'],
          'maximum_sensitivity': 'd3',
          'valid_from': DateTime.utc(2026, 8, 24).toIso8601String(),
          'valid_until': DateTime.utc(2026, 8, 25).toIso8601String(),
        },
      ),
      _event(
        id: 'revoke',
        type: EventTypes.consentRevoked,
        payload: const <String, Object?>{'consent_revision': 1},
      ),
    ]);
    final repository = EventBackedConsentRevisionRepository(
      eventStore: eventStore,
      fallback: _Fallback(_grant()),
    );

    final result = await repository.findRevision(
      consentId: 'consent-1',
      revision: 1,
    );

    expect(result?.status, ConsentStatus.revoked);
  });

  test('grant event can supply a revision absent from fallback', () async {
    final now = DateTime.utc(2026, 8, 24, 10);
    final event = _event(
      id: 'grant',
      type: EventTypes.consentGranted,
      payload: <String, Object?>{
        'consent_id': 'consent-1',
        'consent_revision': 2,
        'subject_id': 'profile-1',
        'authorized_actor_id': 'user-1',
        'purposes': const <String>['appearance_review'],
        'resources': const <String>['portrait'],
        'actions': const <String>['derive'],
        'maximum_sensitivity': 'd3',
        'valid_from': now.toIso8601String(),
        'valid_until': now.add(const Duration(hours: 8)).toIso8601String(),
      },
    );
    final result = await EventBackedConsentRevisionRepository(
      eventStore: _Store(<EventEnvelope>[event]),
      fallback: _Fallback(null),
    ).findRevision(consentId: 'consent-1', revision: 2);

    expect(result?.revision, 2);
    expect(result?.status, ConsentStatus.active);
  });
}

ConsentGrant _grant() => ConsentGrant(
      consentId: 'consent-1',
      revision: 1,
      subjectId: 'profile-1',
      authorizedActorId: 'user-1',
      purposes: const <String>{'appearance_review'},
      resources: const <String>{'portrait'},
      actions: const <String>{'derive'},
      maximumSensitivity: Sensitivity.d3,
      validFrom: DateTime.utc(2026, 8, 24),
      validUntil: DateTime.utc(2026, 8, 25),
      status: ConsentStatus.active,
    );

EventEnvelope _event({
  required String id,
  required String type,
  required Map<String, Object?> payload,
}) {
  final now = DateTime.utc(2026, 8, 24, 10);
  return EventEnvelope(
    eventId: id,
    eventType: type,
    eventVersion: 1,
    occurredAt: now,
    recordedAt: now,
    actor: ActorRef(
      actorId: 'user-1',
      actorType: ActorType.user,
      authoritySource: 'local-session',
    ),
    subjectRefs: <ObjectRef>[
      ObjectRef(type: 'consent', id: EntityId('consent-1')),
      ObjectRef(type: 'profile', id: EntityId('profile-1')),
    ],
    correlationId: 'corr',
    sensitivity: Sensitivity.d2,
    payload: payload,
  );
}

final class _Fallback implements ConsentRevisionRepository {
  _Fallback(this.value);

  final ConsentGrant? value;

  @override
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  }) async => value?.consentId == consentId && value?.revision == revision
      ? value
      : null;
}

final class _Store implements EventStore {
  _Store(this.events);

  final List<EventEnvelope> events;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {}

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async => events.take(limit ?? events.length).toList(growable: false);
}
