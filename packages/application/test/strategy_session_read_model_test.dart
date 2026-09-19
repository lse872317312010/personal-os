import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('restores the open strategy loop from complete profile history',
      () async {
    final store = _Store(_activeLoopEvents());
    final view = await StrategySessionQueryHandler(store).execute(
      EntityId('profile-1'),
    );

    expect(store.completeReads, 1);
    expect(view?.sessionId.value, 'session-1');
    expect(view?.sessionRevision, 2);
    expect(view?.agentId, 'harness-a');
    expect(view?.strategyId?.value, 'strategy-1');
    expect(view?.strategyRevision, 3);
    expect(view?.strategyState, 'active');
    expect(view?.proposalTitle, 'Run experiment');
    expect(view?.proposalEvidenceRefs, <String>['goal:goal-1@1']);
    expect(view?.executionId?.value, 'execution-1');
    expect(view?.outcomeId?.value, 'outcome-1');
    expect(view?.reviewId?.value, 'review-1');
    expect(view?.reviewState, ReviewState.accepted.name);
    expect(view?.reviewConclusion, 'effective');
  });

  test('does not restore a closed session', () async {
    final events = _activeLoopEvents()
      ..add(_event(
        id: 'session-closed',
        type: EventTypes.agentSessionClosed,
        subjectType: 'agent_session',
        subjectId: 'session-1',
        expectedRevision: 2,
      ));
    final view = await StrategySessionQueryHandler(_Store(events)).execute(
      EntityId('profile-1'),
    );

    expect(view, isNull);
  });

  test('fails closed when more than one durable session remains open',
      () async {
    final events = <EventEnvelope>[
      _sessionOpened(id: 'session-1', agentId: 'harness-a'),
      _sessionOpened(id: 'session-2', agentId: 'harness-b'),
    ];

    await expectLater(
      StrategySessionQueryHandler(_Store(events)).execute(
        EntityId('profile-1'),
      ),
      throwsA(
        isA<StrategySessionRestoreFailure>().having(
          (error) => error.code,
          'code',
          StrategySessionRestoreFailureCode.ambiguousOpenSessions,
        ),
      ),
    );
  });
}

List<EventEnvelope> _activeLoopEvents() => <EventEnvelope>[
      _sessionOpened(id: 'session-1', agentId: 'harness-a'),
      _event(
        id: 'strategy-proposed',
        type: EventTypes.strategyProposed,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        expectedRevision: 0,
        payload: <String, Object?>{
          'title': 'Run experiment',
          'rationale': 'Measure it',
          'created_by_session': 'session-1',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-1',
              'revision': 1,
            },
          ],
          'asset_refs': const <Object?>[],
          'actions': const <Object?>[],
          'assumptions': const <Object?>[],
        },
      ),
      _event(
        id: 'proposal-submitted',
        type: EventTypes.agentSessionProposalSubmitted,
        subjectType: 'agent_session',
        subjectId: 'session-1',
        expectedRevision: 1,
        payload: <String, Object?>{
          'proposal_ref': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-1',
          },
        },
      ),
      _event(
        id: 'strategy-accepted',
        type: EventTypes.strategyAccepted,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        expectedRevision: 1,
      ),
      _event(
        id: 'strategy-activated',
        type: EventTypes.strategyActivated,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        expectedRevision: 2,
      ),
      _event(
        id: 'execution-recorded',
        type: EventTypes.executionRecorded,
        subjectType: 'execution',
        subjectId: 'execution-1',
        expectedRevision: 0,
        payload: <String, Object?>{
          'strategy_ref': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-1',
            'revision': 3,
          },
          'action_id': 'action-1',
          'status': 'completed',
        },
      ),
      _event(
        id: 'outcome-recorded',
        type: EventTypes.outcomeRecorded,
        subjectType: 'outcome',
        subjectId: 'outcome-1',
        expectedRevision: 0,
        payload: <String, Object?>{
          'execution_ref': <String, Object?>{
            'type': 'execution',
            'id': 'execution-1',
            'revision': 1,
          },
          'observation': 'Worked',
          'valence': 'positive',
        },
      ),
      _event(
        id: 'review-created',
        type: EventTypes.reviewCreated,
        subjectType: 'review',
        subjectId: 'review-1',
        expectedRevision: 0,
        payload: <String, Object?>{
          'reviewed_by_session': 'session-1',
          'strategy_ref': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-1',
            'revision': 3,
          },
          'summary': 'Keep it',
          'conclusion': 'effective',
          'execution_refs': <Object?>[
            <String, Object?>{
              'type': 'execution',
              'id': 'execution-1',
              'revision': 1,
            },
          ],
          'outcome_refs': <Object?>[
            <String, Object?>{
              'type': 'outcome',
              'id': 'outcome-1',
              'revision': 1,
            },
          ],
          'feedback_refs': const <Object?>[],
        },
      ),
      _event(
        id: 'review-user-reviewed',
        type: EventTypes.reviewUserReviewed,
        subjectType: 'review',
        subjectId: 'review-1',
        expectedRevision: 1,
      ),
      _event(
        id: 'review-accepted',
        type: EventTypes.reviewAccepted,
        subjectType: 'review',
        subjectId: 'review-1',
        expectedRevision: 2,
      ),
    ];

EventEnvelope _sessionOpened({
  required String id,
  required String agentId,
}) =>
    _event(
      id: '$id-opened',
      type: EventTypes.agentSessionOpened,
      subjectType: 'agent_session',
      subjectId: id,
      expectedRevision: 0,
      actor: ActorRef(
        actorId: agentId,
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        onBehalfOf: 'profile-1',
      ),
      payload: <String, Object?>{
        'agent_id': agentId,
        'purpose': 'personal strategy proposal',
        'capabilities': const <String>[],
      },
    );

EventEnvelope _event({
  required String id,
  required String type,
  required String subjectType,
  required String subjectId,
  required int expectedRevision,
  ActorRef? actor,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  final instant = DateTime.utc(2026, 9, 19);
  return EventEnvelope(
    eventId: id,
    eventType: type,
    eventVersion: 1,
    occurredAt: instant,
    recordedAt: instant,
    actor: actor ??
        ActorRef(
          actorId: 'profile-1',
          actorType: ActorType.user,
          authoritySource: 'local-vault-session',
        ),
    subjectRefs: <ObjectRef>[
      ObjectRef(type: subjectType, id: EntityId(subjectId)),
      ObjectRef(type: 'profile', id: EntityId('profile-1')),
    ],
    correlationId: 'test-$id',
    sensitivity: Sensitivity.d2,
    payload: <String, Object?>{
      'expected_revision': expectedRevision,
      ...payload,
    },
  );
}

final class _Store implements EventStore, CompleteProfileHistoryReader {
  _Store(this.events);

  final List<EventEnvelope> events;
  int completeReads = 0;

  @override
  Future<List<EventEnvelope>> readCompleteProfileHistory(
    EntityId profileId, {
    int pageSize = 500,
  }) async {
    completeReads += 1;
    return List<EventEnvelope>.of(events);
  }

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {}

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      events.take(limit ?? events.length).toList(growable: false);
}
