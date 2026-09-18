import 'dart:convert';

import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('offline proposal bundle maps to the same application command', () {
    final bundle = ProposalBundleCodec.decodeString(
      jsonEncode(<String, Object?>{
        'protocol_version': personalOsProtocolV0,
        'proposal_id': 'proposal-1',
        'session_id': 'session-1',
        'created_at': '2026-09-17T01:00:00Z',
        'strategy': <String, Object?>{
          'title': 'Run experiment',
          'rationale': 'Need evidence',
          'goal_refs': <Object?>[
            <String, Object?>{
              'type': 'goal',
              'id': 'goal-1',
              'revision': 2,
            },
          ],
          'asset_refs': <Object?>[],
          'parent_strategy': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-v1',
            'revision': 3,
          },
          'actions': <Object?>[
            <String, Object?>{
              'id': 'action-1',
              'instruction': 'Perform experiment',
            },
          ],
          'assumptions': <Object?>['The action is feasible'],
        },
      }),
    );
    final agent = ActorRef(
      actorId: 'harness.codex',
      actorType: ActorType.agent,
      authoritySource: 'offline_bundle',
      sessionOrRunId: 'session-1',
      onBehalfOf: 'user',
    );
    final command = bundle.toCommand(
      agent: agent,
      profileId: EntityId('primary-user'),
      expectedSessionRevision: 1,
      correlationId: 'proposal-1',
    );

    expect(command.sessionId.value, 'session-1');
    expect(command.goalRefs.single.revision, Revision(2));
    expect(command.actions.single['instruction'], 'Perform experiment');
    expect(command.parentStrategy?.id.value, 'strategy-v1');
    expect(command.parentStrategy?.revision, Revision(3));
  });


  test('structured review bundle maps pinned evidence to review command', () {
    final bundle = ReviewBundleCodec.decodeString(
      jsonEncode(<String, Object?>{
        'protocol_version': personalOsProtocolV0,
        'review_id': 'review-external-1',
        'session_id': 'session-2',
        'created_at': '2026-09-18T02:00:00Z',
        'review': <String, Object?>{
          'strategy_ref': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-v1',
            'revision': 3,
          },
          'summary': 'The bounded experiment improved the outcome.',
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
          'feedback_refs': <Object?>[],
          'keep': <Object?>['short feedback loop'],
          'change': <Object?>['reduce setup'],
          'unknowns': <Object?>['durability'],
        },
      }),
    );
    final command = bundle.toCommand(
      agent: ActorRef(
        actorId: 'harness.codex',
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        sessionOrRunId: 'session-2',
        onBehalfOf: 'primary-user',
      ),
      profileId: EntityId('primary-user'),
      correlationId: bundle.reviewId,
    );

    expect(command.strategyRef?.revision, Revision(3));
    expect(command.executionRefs.single.revision, Revision(1));
    expect(command.outcomeRefs.single.id.value, 'outcome-1');
    expect(command.conclusion, StrategyReviewConclusion.effective);
    expect(command.reviewedBySession?.value, 'session-2');
  });

  test('proposal rejects unpinned context', () {
    expect(
      () => ProposalBundleCodec.decode(<String, Object?>{
        'protocol_version': personalOsProtocolV0,
        'proposal_id': 'proposal-1',
        'session_id': 'session-1',
        'created_at': '2026-09-17T01:00:00Z',
        'strategy': <String, Object?>{
          'title': 'Run experiment',
          'rationale': 'Need evidence',
          'goal_refs': <Object?>[
            <String, Object?>{'type': 'goal', 'id': 'goal-1'},
          ],
          'asset_refs': <Object?>[],
          'actions': <Object?>[
            <String, Object?>{'id': 'a1', 'instruction': 'Act'},
          ],
        },
      }),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          AgentProtocolError.unpinnedReference,
        ),
      ),
    );
  });

  test('context export contains only pinned records and protocol version', () {
    final encoded = ContextBundleCodec.encode(
      ContextBundle(
        bundleId: 'bundle-1',
        sessionId: EntityId('session-1'),
        createdAt: DateTime.utc(2026, 9, 17, 1),
        purpose: 'strategy review',
        records: <ContextRecord>[
          ContextRecord(
            ref: ObjectRef(
              type: 'goal',
              id: EntityId('goal-1'),
              revision: Revision(2),
            ),
            data: const <String, Object?>{'statement': 'Improve sleep'},
            redactedFields: const <String>['private_note'],
          ),
        ],
      ),
    );
    final decoded = jsonDecode(encoded) as Map<String, Object?>;

    expect(decoded['protocol_version'], personalOsProtocolV0);
    final objects = decoded['objects']! as List<Object?>;
    final first = objects.single as Map<String, Object?>;
    expect(first['redacted_fields'], <Object?>['private_note']);
  });
}
