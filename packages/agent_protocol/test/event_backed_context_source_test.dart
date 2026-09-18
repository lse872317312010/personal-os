import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final profileId = EntityId('primary-user');
  final sessionId = EntityId('session-1');
  final user = ActorRef(
    actorId: 'primary-user',
    actorType: ActorType.user,
    authoritySource: 'test',
  );
  final agent = ActorRef(
    actorId: 'harness-a',
    actorType: ActorType.agent,
    authoritySource: 'offline_bundle',
    sessionOrRunId: sessionId.value,
    onBehalfOf: user.actorId,
  );

  EventEnvelope event({
    required String id,
    required String type,
    required ActorRef actor,
    required ObjectRef subject,
    required Map<String, Object?> payload,
    List<ObjectRef> otherSubjects = const <ObjectRef>[],
  }) =>
      EventEnvelope(
        eventId: id,
        eventType: type,
        eventVersion: 1,
        occurredAt: DateTime.utc(2026, 9, 18),
        recordedAt: DateTime.utc(2026, 9, 18),
        actor: actor,
        subjectRefs: <ObjectRef>[subject, ...otherSubjects],
        correlationId: 'context-test',
        sensitivity: Sensitivity.d2,
        payload: payload,
      );

  final sessionOpened = event(
    id: 'event-session',
    type: EventTypes.agentSessionOpened,
    actor: agent,
    subject: ObjectRef(type: 'agent_session', id: sessionId),
    otherSubjects: <ObjectRef>[
      ObjectRef(type: 'profile', id: profileId),
    ],
    payload: const <String, Object?>{
      'expected_revision': 0,
      'purpose': 'strategy review',
    },
  );
  final goalCreated = event(
    id: 'event-goal-created',
    type: EventTypes.goalCreated,
    actor: user,
    subject: ObjectRef(type: 'goal', id: EntityId('goal-1')),
    otherSubjects: <ObjectRef>[
      ObjectRef(type: 'profile', id: profileId),
    ],
    payload: const <String, Object?>{
      'expected_revision': 0,
      'statement': 'Improve recovery',
    },
  );
  final goalActivated = event(
    id: 'event-goal-activated',
    type: EventTypes.goalActivated,
    actor: user,
    subject: ObjectRef(type: 'goal', id: EntityId('goal-1')),
    otherSubjects: <ObjectRef>[
      ObjectRef(type: 'profile', id: profileId),
    ],
    payload: const <String, Object?>{'expected_revision': 1},
  );
  final constraint = event(
    id: 'event-constraint',
    type: EventTypes.constraintRecorded,
    actor: user,
    subject: ObjectRef(type: 'constraint', id: EntityId('constraint-1')),
    otherSubjects: <ObjectRef>[
      ObjectRef(type: 'profile', id: profileId),
    ],
    payload: const <String, Object?>{
      'expected_revision': 0,
      'statement': 'No late training',
    },
  );

  test('query returns paged current projections with pinned references',
      () async {
    final source = EventBackedAgentContextSource(
      eventStore: _EventStore(
        <EventEnvelope>[
          sessionOpened,
          goalCreated,
          goalActivated,
          constraint,
        ],
      ),
      profileId: profileId,
    );

    final first = await source.query(
      sessionId: sessionId,
      purpose: 'strategy review',
      objectTypes: const <String>{'goal', 'constraint'},
      limit: 1,
    );
    final second = await source.query(
      sessionId: sessionId,
      purpose: 'strategy review',
      objectTypes: const <String>{'goal', 'constraint'},
      cursor: first.cursor,
      limit: 1,
    );

    expect(first.records, hasLength(1));
    expect(first.hasMore, isTrue);
    expect(first.cursor, '1');
    expect(second.records, hasLength(1));
    expect(second.hasMore, isFalse);
    expect(
      <String>{first.records.single.ref.type, second.records.single.ref.type},
      <String>{'goal', 'constraint'},
    );
    final goal = <ContextRecord>[
      ...first.records,
      ...second.records,
    ].singleWhere((record) => record.ref.type == 'goal');
    expect(goal.ref.revision, Revision(2));
    expect(goal.data['state'], GoalState.active.name);
    expect(goal.data['statement'], 'Improve recovery');
  });

  test('get reconstructs the exact requested object revision', () async {
    final source = EventBackedAgentContextSource(
      eventStore: _EventStore(
        <EventEnvelope>[sessionOpened, goalCreated, goalActivated],
      ),
      profileId: profileId,
    );

    final record = await source.get(
      sessionId: sessionId,
      ref: ObjectRef(
        type: 'goal',
        id: EntityId('goal-1'),
        revision: Revision(1),
      ),
    );

    expect(record, isNotNull);
    expect(record!.ref.revision, Revision(1));
    expect(record.data['state'], GoalState.draft.name);
  });

  test('query rejects a session owned by another profile', () async {
    final source = EventBackedAgentContextSource(
      eventStore: _EventStore(<EventEnvelope>[sessionOpened]),
      profileId: EntityId('other-user'),
    );

    expect(
      () => source.query(
        sessionId: sessionId,
        purpose: 'strategy review',
        objectTypes: const <String>{'goal'},
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.invalidRequest,
        ),
      ),
    );
  });
}

final class _EventStore implements EventStore {
  const _EventStore(this.events);

  final List<EventEnvelope> events;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async =>
      throw UnsupportedError('read-only test store');

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    for (final event in events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    final matches = events
        .where(
          (event) => event.subjectRefs.any(
            (candidate) =>
                candidate.type == subject.type && candidate.id == subject.id,
          ),
        )
        .toList(growable: false);
    return limit == null
        ? matches
        : matches.take(limit).toList(growable: false);
  }
}
