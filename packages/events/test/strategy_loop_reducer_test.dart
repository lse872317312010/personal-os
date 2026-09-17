import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 9, 16, 9);

  EventEnvelope event({
    required String id,
    required String type,
    required String subjectType,
    required String subjectId,
    required ActorRef actor,
    required int expectedRevision,
    Map<String, Object?> payload = const <String, Object?>{},
  }) =>
      EventEnvelope(
        eventId: id,
        eventType: type,
        eventVersion: 1,
        occurredAt: at,
        recordedAt: at,
        actor: actor,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: subjectType, id: EntityId(subjectId)),
        ],
        correlationId: 'loop-1',
        sensitivity: Sensitivity.d2,
        payload: <String, Object?>{
          'expected_revision': expectedRevision,
          ...payload,
        },
      );

  final agent = ActorRef(
    actorId: 'harness.codex',
    actorType: ActorType.agent,
    authoritySource: 'mcp',
    sessionOrRunId: 'session-1',
    onBehalfOf: 'user',
    capabilityRefs: const <String>['proposal.submit'],
  );
  final user = ActorRef(
    actorId: 'user',
    actorType: ActorType.user,
    authoritySource: 'android',
  );

  test('strategy proposal to active preserves auditable payload', () {
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};

    final proposal = reduceCore(
      projections: projections,
      seenEventIds: seen,
      event: event(
        id: 'event-1',
        type: EventTypes.strategyProposed,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        actor: agent,
        expectedRevision: 0,
        payload: const <String, Object?>{
          'title': 'Sleep experiment',
          'created_by_session': 'session-1',
        },
      ),
    );
    expect(proposal.disposition, ReductionDisposition.applied);
    expect(proposal.projections['strategy:strategy-1']!.state, 'proposed');
    expect(
      proposal.projections['strategy:strategy-1']!.attributes['title'],
      'Sleep experiment',
    );
    expect(
      proposal.projections['strategy:strategy-1']!.attributes
          .containsKey('expected_revision'),
      isFalse,
    );

    projections = proposal.projections;
    seen = proposal.seenEventIds;
    final accepted = reduceCore(
      projections: projections,
      seenEventIds: seen,
      event: event(
        id: 'event-2',
        type: EventTypes.strategyAccepted,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        actor: user,
        expectedRevision: 1,
      ),
    );
    final activated = reduceCore(
      projections: accepted.projections,
      seenEventIds: accepted.seenEventIds,
      event: event(
        id: 'event-3',
        type: EventTypes.strategyActivated,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        actor: user,
        expectedRevision: 2,
      ),
    );

    expect(activated.disposition, ReductionDisposition.applied);
    expect(activated.projections['strategy:strategy-1']!.state, 'active');
    expect(
      activated.projections['strategy:strategy-1']!.revision,
      Revision(3),
    );
    expect(
      activated.projections['strategy:strategy-1']!.attributes['title'],
      'Sleep experiment',
    );
  });

  test('strategy cannot activate before explicit acceptance', () {
    final proposed = reduceCore(
      projections: const <String, ObjectProjection>{},
      seenEventIds: const <String>{},
      event: event(
        id: 'event-1',
        type: EventTypes.strategyProposed,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        actor: agent,
        expectedRevision: 0,
      ),
    );
    final activated = reduceCore(
      projections: proposed.projections,
      seenEventIds: proposed.seenEventIds,
      event: event(
        id: 'event-2',
        type: EventTypes.strategyActivated,
        subjectType: 'strategy',
        subjectId: 'strategy-1',
        actor: user,
        expectedRevision: 1,
      ),
    );

    expect(activated.disposition, ReductionDisposition.rejected);
    expect(activated.reasonCode, ReductionReason.illegalStateTransition);
  });

  test('agent session closes after a proposal is submitted', () {
    final opened = reduceCore(
      projections: const <String, ObjectProjection>{},
      seenEventIds: const <String>{},
      event: event(
        id: 'event-1',
        type: EventTypes.agentSessionOpened,
        subjectType: 'agent_session',
        subjectId: 'session-1',
        actor: agent,
        expectedRevision: 0,
        payload: const <String, Object?>{
          'agent_id': 'harness.codex',
          'protocol_version': 'personal-os.mcp.v0',
        },
      ),
    );
    final submitted = reduceCore(
      projections: opened.projections,
      seenEventIds: opened.seenEventIds,
      event: event(
        id: 'event-2',
        type: EventTypes.agentSessionProposalSubmitted,
        subjectType: 'agent_session',
        subjectId: 'session-1',
        actor: agent,
        expectedRevision: 1,
      ),
    );
    final closed = reduceCore(
      projections: submitted.projections,
      seenEventIds: submitted.seenEventIds,
      event: event(
        id: 'event-3',
        type: EventTypes.agentSessionClosed,
        subjectType: 'agent_session',
        subjectId: 'session-1',
        actor: agent,
        expectedRevision: 2,
      ),
    );

    expect(closed.projections['agent_session:session-1']!.state, 'closed');
  });
}
