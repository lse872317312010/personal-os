import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final actor = ActorRef(
    actorId: 'user-1',
    actorType: ActorType.user,
    authoritySource: 'local-session',
  );

  test('grant writes requested then granted atomically', () async {
    final store = _Store();
    final useCase = ConsentLifecycleUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );

    final result = await useCase.grant(
      GrantConsentCommand(
        profileId: EntityId('profile-1'),
        consentId: 'consent-1',
        consentRevision: 1,
        actor: actor,
        correlationId: 'corr-grant',
      ),
    );

    expect(result.stateRevision, 2);
    expect(store.events.map((event) => event.eventType), <String>[
      EventTypes.consentRequested,
      EventTypes.consentGranted,
    ]);
    expect(
        store.events.every((event) => event.subjectRefs.length == 2), isTrue);
    expect(store.events.last.causationId, store.events.first.eventId);
  });

  test('revoke uses expected revision and writes no raw diagnostics', () async {
    final store = _Store();
    final useCase = ConsentLifecycleUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );

    final result = await useCase.revoke(
      RevokeConsentCommand(
        profileId: EntityId('profile-1'),
        consentId: 'consent-1',
        consentRevision: 1,
        expectedConsentStateRevision: 2,
        actor: actor,
        correlationId: 'corr-revoke',
      ),
    );

    expect(result.stateRevision, 3);
    expect(store.events.single.eventType, EventTypes.consentRevoked);
    expect(store.events.single.expectedRevision, 2);
    expect(store.events.single.payload, {
      'expected_revision': 2,
      'consent_revision': 1,
    });
  });

  test('external processing grant writes a separate transmit scope', () async {
    final store = _Store();
    final useCase = ConsentLifecycleUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );

    await useCase.grant(
      GrantConsentCommand(
        profileId: EntityId('profile-1'),
        consentId: 'external-processing-consent-1',
        consentRevision: 1,
        actor: actor,
        correlationId: 'corr-external-grant',
        scope: ConsentScope.externalProcessing,
      ),
    );

    final payload = store.events.last.payload;
    expect(payload['purposes'], <String>['external_processing']);
    expect(payload['resources'], <String>['portrait']);
    expect(payload['actions'], <String>['transmit']);
    expect(payload['scope'], 'externalProcessing');
  });

  test('non-user cannot grant consent', () async {
    final store = _Store();
    final useCase = ConsentLifecycleUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );

    await expectLater(
      useCase.grant(
        GrantConsentCommand(
          profileId: EntityId('profile-1'),
          consentId: 'consent-1',
          consentRevision: 1,
          actor: ActorRef(
            actorId: 'agent-1',
            actorType: ActorType.agent,
            authoritySource: 'delegation',
            onBehalfOf: 'user-1',
          ),
          correlationId: 'corr',
        ),
      ),
      throwsA(isA<ConsentUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ConsentFailureCode.userActorRequired,
      )),
    );
    expect(store.events, isEmpty);
  });
}

final class _Store implements EventStore {
  final events = <EventEnvelope>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    this.events.addAll(events);
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject,
          {int? limit}) async =>
      const <EventEnvelope>[];
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String nextId(String namespace) => '$namespace-${++value}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 8, 24, 10);
}
