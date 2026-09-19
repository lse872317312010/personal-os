import 'dart:convert';

import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('two different Harness identities use the same proposal protocol',
      () async {
    final store = _EventStore();
    final ids = _Ids();
    final service = PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: StrategyLoopUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      contextSource: const _NoContext(),
      ids: ids,
      clock: const _Clock(),
    );

    for (final harnessId in <String>['codex-cli', 'custom-harness']) {
      final grant = await service.openSession(
        agent: _agent(harnessId),
        profileId: EntityId('primary-user'),
        purpose: 'strategy proposal',
        requestedCapabilities: const <String>['proposal.submit'],
      );
      final result = await service.submitProposal(
        bundleJson: _proposal(grant.sessionId.value, harnessId),
        agent: _agent(harnessId, sessionId: grant.sessionId.value),
        profileId: EntityId('primary-user'),
        expectedSessionRevision: grant.revision,
      );

      expect(result.objectId.value, startsWith('strategy-'));
    }

    final proposalEvents = store.events
        .where((event) => event.eventType == EventTypes.strategyProposed)
        .toList(growable: false);
    expect(proposalEvents, hasLength(2));
    expect(
      proposalEvents.map((event) => event.actor.actorId).toSet(),
      <String>{'codex-cli', 'custom-harness'},
    );
  });

  test('proposal submitter cannot reuse another Harness session', () async {
    final store = _EventStore();
    final ids = _Ids();
    final service = PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: StrategyLoopUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      contextSource: const _NoContext(),
      ids: ids,
      clock: const _Clock(),
    );
    final grant = await service.openSession(
      agent: _agent('codex-cli'),
      profileId: EntityId('primary-user'),
      purpose: 'strategy proposal',
      requestedCapabilities: const <String>['proposal.submit'],
    );

    expect(
      () => service.submitProposal(
        bundleJson: _proposal(grant.sessionId.value, 'attempt'),
        agent: _agent('custom-harness', sessionId: grant.sessionId.value),
        profileId: EntityId('primary-user'),
        expectedSessionRevision: grant.revision,
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.accessDenied,
        ),
      ),
    );
  });

  test('granted capabilities and open lifecycle are enforced', () async {
    final store = _EventStore();
    final ids = _Ids();
    final service = PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: StrategyLoopUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      contextSource: const _NoContext(),
      ids: ids,
      clock: const _Clock(),
    );

    final contextOnly = await service.openSession(
      agent: _agent('context-only'),
      profileId: EntityId('primary-user'),
      purpose: 'read context',
      requestedCapabilities: const <String>['context.query'],
    );
    expect(
      () => service.submitProposal(
        bundleJson: _proposal(contextOnly.sessionId.value, 'denied'),
        agent: _agent(
          'context-only',
          sessionId: contextOnly.sessionId.value,
        ),
        profileId: EntityId('primary-user'),
        expectedSessionRevision: contextOnly.revision,
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.accessDenied,
        ),
      ),
    );

    final proposalOnly = await service.openSession(
      agent: _agent('proposal-only'),
      profileId: EntityId('primary-user'),
      purpose: 'write proposal',
      requestedCapabilities: const <String>['proposal.submit'],
    );
    expect(
      () => service.queryContext(
        sessionId: proposalOnly.sessionId,
        purpose: 'unauthorized read',
        objectTypes: const <String>{'goal'},
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.accessDenied,
        ),
      ),
    );

    final boundAgent = _agent(
      'proposal-only',
      sessionId: proposalOnly.sessionId.value,
    );
    await service.closeSession(
      sessionId: proposalOnly.sessionId,
      profileId: EntityId('primary-user'),
      expectedRevision: proposalOnly.revision,
      agent: boundAgent,
    );
    expect(
      () => service.submitProposal(
        bundleJson: _proposal(proposalOnly.sessionId.value, 'closed'),
        agent: boundAgent,
        profileId: EntityId('primary-user'),
        expectedSessionRevision: proposalOnly.revision,
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.sessionClosed,
        ),
      ),
    );
  });

  test('review submitter cannot reuse another Harness session', () async {
    final store = _EventStore();
    final ids = _Ids();
    final service = PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: StrategyLoopUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      contextSource: const _NoContext(),
      ids: ids,
      clock: const _Clock(),
    );
    final grant = await service.openSession(
      agent: _agent('codex-cli'),
      profileId: EntityId('primary-user'),
      purpose: 'strategy review',
      requestedCapabilities: const <String>['review.submit'],
    );

    expect(
      () => service.submitReview(
        bundleJson: _review(grant.sessionId.value),
        agent: _agent('custom-harness', sessionId: grant.sessionId.value),
        profileId: EntityId('primary-user'),
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.accessDenied,
        ),
      ),
    );
  });
}

ActorRef _agent(String id, {String? sessionId}) => ActorRef(
      actorId: id,
      actorType: ActorType.agent,
      authoritySource: 'offline_bundle',
      sessionOrRunId: sessionId,
      onBehalfOf: 'primary-user',
      capabilityRefs: const <String>['proposal.submit'],
    );

String _proposal(String sessionId, String suffix) =>
    jsonEncode(<String, Object?>{
      'protocol_version': personalOsProtocolV0,
      'proposal_id': 'proposal-$suffix',
      'session_id': sessionId,
      'created_at': '2026-09-18T00:00:00Z',
      'strategy': <String, Object?>{
        'title': 'Strategy from $suffix',
        'rationale': 'Compatibility verification',
        'goal_refs': <Object?>[
          <String, Object?>{
            'type': 'goal',
            'id': 'goal-1',
            'revision': 1,
          },
        ],
        'asset_refs': <Object?>[],
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action-1',
            'instruction': 'Run the bounded experiment',
          },
        ],
      },
    });

String _review(String sessionId) => jsonEncode(<String, Object?>{
      'protocol_version': personalOsProtocolV0,
      'review_id': 'review-external-1',
      'session_id': sessionId,
      'created_at': '2026-09-18T00:00:00Z',
      'review': <String, Object?>{
        'strategy_ref': <String, Object?>{
          'type': 'strategy',
          'id': 'strategy-1',
          'revision': 3,
        },
        'summary': 'The experiment improved the measured outcome.',
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
        'keep': <Object?>['bounded experiment'],
        'change': <Object?>[],
        'unknowns': <Object?>['long-term effect'],
      },
    });

final class _EventStore implements EventStore {
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
  DateTime now() => DateTime.utc(2026, 9, 18);
}

final class _NoContext implements AgentContextSource {
  const _NoContext();

  @override
  Future<ContextRecord?> get({
    required EntityId sessionId,
    required ObjectRef ref,
  }) async =>
      null;

  @override
  Future<ContextPage> query({
    required EntityId sessionId,
    required String purpose,
    required Set<String> objectTypes,
    String? cursor,
    int limit = 100,
  }) async =>
      ContextPage(records: const <ContextRecord>[]);
}
