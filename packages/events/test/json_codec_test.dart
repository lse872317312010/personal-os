import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  group('EventEnvelopeJsonCodec', () {
    test('event deeply copies and freezes caller-owned containers', () {
      final nestedList = <Object?>[
        <String, Object?>{'score': 1},
      ];
      final payload = <String, Object?>{'items': nestedList};
      final integrityNested = <String, Object?>{'digest': 'before'};
      final integrity = <String, Object?>{'proof': integrityNested};
      final extensionList = <Object?>['before'];
      final extensions = <String, Object?>{'values': extensionList};

      final event = _eventWithContainers(payload, integrity, extensions);
      (nestedList.single as Map<String, Object?>)['score'] = 2;
      nestedList.add('after');
      payload['new_key'] = true;
      integrityNested['digest'] = 'after';
      integrity['new_key'] = true;
      extensionList[0] = 'after';
      extensions['new_key'] = true;

      final frozenItems = event.payload['items']! as List<Object?>;
      expect(frozenItems, [<String, Object?>{'score': 1}]);
      expect(event.integrity['proof'], <String, Object?>{'digest': 'before'});
      expect(event.extensions['values'], ['before']);
      expect(event.payload, isNot(contains('new_key')));
      expect(event.integrity, isNot(contains('new_key')));
      expect(event.extensions, isNot(contains('new_key')));
      expect(() => frozenItems.add('mutation'), throwsUnsupportedError);
      expect(
        () => (frozenItems.single as Map<String, Object?>)['score'] = 3,
        throwsUnsupportedError,
      );
      expect(
        () => (event.integrity['proof']! as Map<String, Object?>).clear(),
        throwsUnsupportedError,
      );
    });

    test('round-trips every envelope field including pinned revisions', () {
      final event = _event();

      final decoded = EventEnvelopeJsonCodec.decodeString(
        EventEnvelopeJsonCodec.encodeString(event),
      );

      expect(decoded.eventId, event.eventId);
      expect(decoded.eventType, event.eventType);
      expect(decoded.eventVersion, 1);
      expect(decoded.occurredAt, event.occurredAt);
      expect(decoded.recordedAt, event.recordedAt);
      expect(decoded.actor.actorId, 'user-1');
      expect(decoded.actor.actorType, ActorType.user);
      expect(decoded.actor.sessionOrRunId, 'session-1');
      expect(decoded.actor.capabilityRefs, ['appearance.capture']);
      expect(decoded.subjectRefs.single.revision, Revision(7));
      expect(decoded.sourceRefs.single.revision, Revision(2));
      expect(decoded.consentRefs.single.revision, Revision(4));
      expect(decoded.correlationId, 'correlation-1');
      expect(decoded.causationId, 'cause-1');
      expect(decoded.sensitivity, Sensitivity.d3);
      expect(decoded.payload, event.payload);
      expect(decoded.integrity, event.integrity);
      expect(decoded.extensions, event.extensions);
    });

    test('emits stable recursively key-sorted JSON', () {
      final first = EventEnvelopeJsonCodec.encodeString(_event());
      final second = EventEnvelopeJsonCodec.encodeString(_event());

      expect(first, second);
      expect(first.indexOf('"actor"'), lessThan(first.indexOf('"event_id"')));
      expect(first.indexOf('"a_nested"'), lessThan(first.indexOf('"z_nested"')));
      expect(first.indexOf('"alpha"'), lessThan(first.indexOf('"zeta"')));
    });

    test('rejects unknown schema and event versions without guessing', () {
      final json = EventEnvelopeJsonCodec.encode(_event());

      expect(
        () => EventEnvelopeJsonCodec.decode({...json, 'schema_version': 2}),
        _reason(EventCodecReason.unsupportedSchemaVersion),
      );
      expect(
        () => EventEnvelopeJsonCodec.decode({...json, 'event_version': 2}),
        _reason(EventCodecReason.unsupportedEventVersion),
      );
    });

    test('rejects unknown security-critical enum values', () {
      final json = EventEnvelopeJsonCodec.encode(_event());
      expect(
        () => EventEnvelopeJsonCodec.decode({...json, 'sensitivity': 'd5'}),
        _reason(EventCodecReason.unknownSensitivity),
      );
      expect(
        () => EventEnvelopeJsonCodec.decode({
          ...json,
          'actor': {
            ...(json['actor']! as Map<String, Object?>),
            'actor_type': 'future_superuser',
          },
        }),
        _reason(EventCodecReason.unknownActorType),
      );
    });

    test('permanently refuses D4 persistence on encode and decode', () {
      expect(
        () => EventEnvelopeJsonCodec.encode(_event(Sensitivity.d4)),
        _reason(EventCodecReason.d4PersistenceForbidden),
      );
      final json = EventEnvelopeJsonCodec.encode(_event());
      expect(
        () => EventEnvelopeJsonCodec.decode({...json, 'sensitivity': 'd4'}),
        _reason(EventCodecReason.d4PersistenceForbidden),
      );
    });

    test('retains explicit extensions but rejects unknown top-level fields', () {
      final encoded = EventEnvelopeJsonCodec.encode(_event());
      final decoded = EventEnvelopeJsonCodec.decode(encoded);
      expect(decoded.extensions['future_hint'], 'preserved');

      expect(
        () => EventEnvelopeJsonCodec.decode({...encoded, 'future_hint': true}),
        _reason(EventCodecReason.unknownField),
      );
    });

    test('requires explicit UTC timestamps', () {
      final json = EventEnvelopeJsonCodec.encode(_event());
      expect(
        () => EventEnvelopeJsonCodec.decode({
          ...json,
          'occurred_at': '2026-08-17T10:00:00+08:00',
        }),
        _reason(EventCodecReason.invalidTimestamp),
      );
    });
  });

  group('ObjectProjectionJsonCodec', () {
    test('projection deeply copies and freezes attributes', () {
      final nested = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'value': 'before'},
        ],
      };
      final projection = ObjectProjection(
        objectType: 'goal',
        id: EntityId('goal-immutable'),
        revision: Revision(1),
        state: 'active',
        lastEventId: 'event-immutable',
        attributes: nested,
      );

      ((nested['items']! as List<Object?>).single
          as Map<String, Object?>)['value'] = 'after';
      (nested['items']! as List<Object?>).add('after');

      final frozen = projection.attributes['items']! as List<Object?>;
      expect(frozen, [<String, Object?>{'value': 'before'}]);
      expect(() => frozen.clear(), throwsUnsupportedError);
      expect(
        () => (frozen.single as Map<String, Object?>)['value'] = 'mutation',
        throwsUnsupportedError,
      );
    });

    test('round-trips and emits stable JSON', () {
      final projection = ObjectProjection(
        objectType: 'appearance_observation',
        id: EntityId('observation-1'),
        revision: Revision(9),
        state: 'recorded',
        lastEventId: 'event-9',
        attributes: const {
          'zeta': 2,
          'alpha': 1,
          'nested': {'z': false, 'a': true},
        },
      );

      final encoded = ObjectProjectionJsonCodec.encodeString(projection);
      final decoded = ObjectProjectionJsonCodec.decodeString(encoded);
      expect(decoded.objectType, projection.objectType);
      expect(decoded.id, projection.id);
      expect(decoded.revision, projection.revision);
      expect(decoded.state, projection.state);
      expect(decoded.lastEventId, projection.lastEventId);
      expect(decoded.attributes, projection.attributes);
      expect(encoded, ObjectProjectionJsonCodec.encodeString(decoded));
      expect(encoded.indexOf('"alpha"'), lessThan(encoded.indexOf('"zeta"')));
    });

    test('rejects unknown version and unknown fields', () {
      final base = <String, Object?>{
        'schema_version': 1,
        'object_type': 'goal',
        'id': 'goal-1',
        'revision': 1,
        'state': 'active',
        'last_event_id': 'event-1',
        'attributes': <String, Object?>{},
      };
      expect(
        () => ObjectProjectionJsonCodec.decode({...base, 'schema_version': 2}),
        _reason(EventCodecReason.unsupportedSchemaVersion),
      );
      expect(
        () => ObjectProjectionJsonCodec.decode({...base, 'surprise': true}),
        _reason(EventCodecReason.unknownField),
      );
    });
  });
}

EventEnvelope _event([Sensitivity sensitivity = Sensitivity.d3]) => EventEnvelope(
      eventId: 'event-1',
      eventType: EventTypes.observationRecorded,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 17, 10, 11, 12, 123, 456),
      recordedAt: DateTime.utc(2026, 8, 17, 10, 12, 13, 654, 321),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'local_session',
        sessionOrRunId: 'session-1',
        capabilityRefs: const ['appearance.capture'],
      ),
      subjectRefs: [
        ObjectRef(
          type: 'appearance_observation',
          id: EntityId('observation-1'),
          revision: Revision(7),
        ),
      ],
      correlationId: 'correlation-1',
      causationId: 'cause-1',
      sourceRefs: [
        ObjectRef(
          type: 'source',
          id: EntityId('photo-1'),
          revision: Revision(2),
        ),
      ],
      consentRefs: [
        ObjectRef(
          type: 'consent',
          id: EntityId('consent-1'),
          revision: Revision(4),
        ),
      ],
      sensitivity: sensitivity,
      payload: const {
        'expected_revision': 7,
        'z_nested': {'z': 2, 'a': 1},
        'a_nested': true,
      },
      integrity: const {'algorithm': 'none', 'digest': null},
      extensions: const {
        'future_hint': 'preserved',
        'zeta': 2,
        'alpha': 1,
      },
    );

Matcher _reason(String reason) => isA<EventCodecException>()
    .having((error) => error.reasonCode, 'reasonCode', reason);

EventEnvelope _eventWithContainers(
  Map<String, Object?> payload,
  Map<String, Object?> integrity,
  Map<String, Object?> extensions,
) =>
    EventEnvelope(
      eventId: 'event-immutable',
      eventType: EventTypes.observationRecorded,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 8, 17),
      recordedAt: DateTime.utc(2026, 8, 17, 0, 1),
      actor: ActorRef(
        actorId: 'user-1',
        actorType: ActorType.user,
        authoritySource: 'local_session',
      ),
      subjectRefs: [
        ObjectRef(type: 'observation', id: EntityId('observation-immutable')),
      ],
      correlationId: 'correlation-immutable',
      sensitivity: Sensitivity.d2,
      payload: payload,
      integrity: integrity,
      extensions: extensions,
    );
