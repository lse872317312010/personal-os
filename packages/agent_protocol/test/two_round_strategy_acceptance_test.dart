import 'dart:convert';

import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('two Agent rounds preserve evidence and strategy lineage', () async {
    final store = _Store();
    final ids = _Ids();
    const clock = _Clock();
    final profileId = EntityId('primary-user');
    final user = ActorRef(
      actorId: 'primary-user',
      actorType: ActorType.user,
      authoritySource: 'android',
    );
    final strategyLoop = StrategyLoopUseCase(
      eventStore: store,
      ids: ids,
      clock: clock,
    );
    final feedback = ActionFeedbackUseCase(
      eventStore: store,
      ids: ids,
      clock: clock,
    );
    final protocol = PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: strategyLoop,
      actionFeedback: feedback,
      contextSource: EventBackedAgentContextSource(
        eventStore: store,
        profileId: profileId,
      ),
      ids: ids,
      clock: clock,
    );

    final firstGrant = await protocol.openSession(
      agent: _agent('harness-a'),
      profileId: profileId,
      purpose: 'first strategy round',
      requestedCapabilities: const <String>[
        'context.query',
        'proposal.submit',
      ],
    );
    final firstAgent =
        _agent('harness-a', sessionId: firstGrant.sessionId.value);
    final first = await protocol.submitProposal(
      bundleJson: _proposal(
        sessionId: firstGrant.sessionId.value,
        proposalId: 'proposal-v1',
        title: 'Strategy v1',
      ),
      agent: firstAgent,
      profileId: profileId,
      expectedSessionRevision: firstGrant.revision,
    );
    await strategyLoop.decideProposal(
      DecideStrategyProposalCommand(
        actor: user,
        profileId: profileId,
        correlationId: 'accept-v1',
        strategyId: first.objectId,
        expectedRevision: 1,
        decision: ProposalDecision.accept,
      ),
    );
    await strategyLoop.activateStrategy(
      ActivateStrategyCommand(
        actor: user,
        profileId: profileId,
        correlationId: 'activate-v1',
        strategyId: first.objectId,
        expectedRevision: 2,
      ),
    );
    final execution = await strategyLoop.recordExecution(
      RecordStrategyExecutionCommand(
        actor: user,
        profileId: profileId,
        correlationId: 'execute-v1',
        strategyRef: ObjectRef(
          type: 'strategy',
          id: first.objectId,
          revision: Revision(3),
        ),
        actionId: EntityId('action-1'),
        status: ExecutionStatus.completed,
      ),
    );
    final outcome = await strategyLoop.recordOutcome(
      RecordStrategyOutcomeCommand(
        actor: user,
        profileId: profileId,
        correlationId: 'outcome-v1',
        executionRef: ObjectRef(
          type: 'execution',
          id: execution.objectId,
          revision: Revision(1),
        ),
        observation: 'The bounded experiment produced measurable evidence.',
        valence: OutcomeValence.positive,
      ),
    );
    await protocol.closeSession(
      sessionId: firstGrant.sessionId,
      profileId: profileId,
      expectedRevision: 2,
      agent: firstAgent,
    );

    final secondGrant = await protocol.openSession(
      agent: _agent('harness-b'),
      profileId: profileId,
      purpose: 'review and migrate strategy',
      requestedCapabilities: const <String>[
        'context.query',
        'proposal.submit',
        'review.submit',
      ],
    );
    final secondAgent =
        _agent('harness-b', sessionId: secondGrant.sessionId.value);
    final contextJson = await protocol.queryContext(
      sessionId: secondGrant.sessionId,
      purpose: 'review and migrate strategy',
      objectTypes: const <String>{
        'strategy',
        'execution',
        'outcome',
        'review',
      },
    );
    final context = jsonDecode(contextJson) as Map<String, Object?>;
    final objects =
        (context['objects']! as List<Object?>).cast<Map<String, Object?>>();
    final contextKeys = objects.map((object) {
      final ref = object['ref']! as Map<String, Object?>;
      return '${ref['type']}:${ref['id']}@${ref['revision']}';
    }).toSet();
    expect(
      contextKeys,
      containsAll(<String>[
        'strategy:${first.objectId.value}@3',
        'execution:${execution.objectId.value}@1',
        'outcome:${outcome.objectId.value}@1',
      ]),
    );

    final review = await protocol.submitReview(
      bundleJson: _review(
        sessionId: secondGrant.sessionId.value,
        strategyId: first.objectId.value,
        executionId: execution.objectId.value,
        outcomeId: outcome.objectId.value,
      ),
      agent: secondAgent,
      profileId: profileId,
    );
    await feedback.decideReview(
      DecideReviewCommand(
        reviewId: EntityId(review.reviewId),
        profileId: profileId,
        expectedReviewRevision: 1,
        actor: user,
        correlationId: 'accept-review-v1',
        decision: ReviewDecision.accept,
      ),
    );

    final second = await protocol.submitProposal(
      bundleJson: _proposal(
        sessionId: secondGrant.sessionId.value,
        proposalId: 'proposal-v2',
        title: 'Strategy v2',
        parentStrategyId: first.objectId.value,
      ),
      agent: secondAgent,
      profileId: profileId,
      expectedSessionRevision: secondGrant.revision,
    );

    final secondEvents = await store.readBySubject(
      ObjectRef(type: 'strategy', id: second.objectId),
    );
    final proposed = secondEvents.singleWhere(
      (event) => event.eventType == EventTypes.strategyProposed,
    );
    expect(
      proposed.payload['parent_strategy'],
      <String, Object?>{
        'type': 'strategy',
        'id': first.objectId.value,
        'revision': 3,
      },
    );
    expect(
      store.events.map((event) => event.eventType),
      contains(EventTypes.reviewAccepted),
    );
    expect(proposed.actor.actorId, 'harness-b');
  });
}

ActorRef _agent(String id, {String? sessionId}) => ActorRef(
      actorId: id,
      actorType: ActorType.agent,
      authoritySource: 'offline_bundle',
      sessionOrRunId: sessionId,
      onBehalfOf: 'primary-user',
      capabilityRefs: const <String>[
        'context.query',
        'proposal.submit',
        'review.submit',
      ],
    );

String _proposal({
  required String sessionId,
  required String proposalId,
  required String title,
  String? parentStrategyId,
}) =>
    jsonEncode(<String, Object?>{
      'protocol_version': personalOsProtocolV0,
      'proposal_id': proposalId,
      'session_id': sessionId,
      'created_at': '2026-09-18T12:00:00Z',
      'strategy': <String, Object?>{
        'title': title,
        'rationale': parentStrategyId == null
            ? 'Start a bounded experiment.'
            : 'Migrate the accepted review into the next strategy.',
        'goal_refs': <Object?>[
          <String, Object?>{
            'type': 'goal',
            'id': 'goal-1',
            'revision': 2,
          },
        ],
        'asset_refs': <Object?>[],
        if (parentStrategyId != null)
          'parent_strategy': <String, Object?>{
            'type': 'strategy',
            'id': parentStrategyId,
            'revision': 3,
          },
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action-1',
            'instruction': 'Run the next bounded experiment.',
          },
        ],
      },
    });

String _review({
  required String sessionId,
  required String strategyId,
  required String executionId,
  required String outcomeId,
}) =>
    jsonEncode(<String, Object?>{
      'protocol_version': personalOsProtocolV0,
      'review_id': 'review-v1',
      'session_id': sessionId,
      'created_at': '2026-09-18T12:00:00Z',
      'review': <String, Object?>{
        'strategy_ref': <String, Object?>{
          'type': 'strategy',
          'id': strategyId,
          'revision': 3,
        },
        'summary': 'The experiment worked and should be retained.',
        'conclusion': 'effective',
        'execution_refs': <Object?>[
          <String, Object?>{
            'type': 'execution',
            'id': executionId,
            'revision': 1,
          },
        ],
        'outcome_refs': <Object?>[
          <String, Object?>{
            'type': 'outcome',
            'id': outcomeId,
            'revision': 1,
          },
        ],
        'keep': <Object?>['bounded experiment'],
        'change': <Object?>['shorten setup'],
        'unknowns': <Object?>['long-term durability'],
      },
    });

final class _Store implements EventStore {
  final List<EventEnvelope> events = <EventEnvelope>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    this.events.addAll(events);
  }

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

final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 18, 12);
}
