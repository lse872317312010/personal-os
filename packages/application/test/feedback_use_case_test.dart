import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  late _MemoryStore store;
  late _Ids ids;
  late ActionFeedbackUseCase useCase;
  final user = ActorRef(
    actorId: 'user:self',
    actorType: ActorType.user,
    authoritySource: 'local-session',
  );

  setUp(() {
    store = _MemoryStore();
    ids = _Ids();
    useCase = ActionFeedbackUseCase(
      eventStore: store,
      ids: ids,
      clock: _Clock(),
    );
  });

  test(
      'complete task atomically records execution before referenced completion',
      () async {
    final result = await useCase.completeTask(CompleteTaskCommand(
      taskId: EntityId('T1'),
      expectedTaskRevision: 2,
      actor: user,
      correlationId: 'corr:complete',
      executionSummary: '完成理发并拍照',
      profileId: EntityId('profile-1'),
    ));

    expect(store.appendCalls, 1);
    expect(store.batches.single.map((e) => e.eventType), <String>[
      EventTypes.executionRecorded,
      EventTypes.taskCompleted,
    ]);
    final execution = store.batches.single.first;
    final completion = store.batches.single.last;
    expect(completion.causationId, execution.eventId);
    expect(
        completion.payload['execution_ref'], 'execution:${result.executionId}');
    expect(completion.sourceRefs.single.id.value, result.executionId);
    expect(completion.payload['expected_revision'], 2);
    expect(
      completion.subjectRefs.map((ref) => ref.type),
      <String>['task', 'profile'],
    );
  });

  test('blank execution summary has stable failure and writes nothing',
      () async {
    await expectLater(
      useCase.completeTask(CompleteTaskCommand(
        taskId: EntityId('T1'),
        expectedTaskRevision: 1,
        actor: user,
        correlationId: 'corr',
        executionSummary: ' ',
      )),
      throwsA(isA<FeedbackUseCaseFailure>().having(
        (e) => e.code,
        'code',
        FeedbackFailureCode.executionSummaryRequired,
      )),
    );
    expect(store.appendCalls, 0);
  });

  test('skip is an explicit event with a non-blank reason', () async {
    await useCase.skipTask(SkipTaskCommand(
      taskId: EntityId('T2'),
      expectedTaskRevision: 1,
      actor: user,
      correlationId: 'corr:skip',
      reason: '今天皮肤过敏',
      profileId: EntityId('profile-1'),
    ));
    expect(store.appendCalls, 1);
    final event = store.batches.single.single;
    expect(event.eventType, EventTypes.taskSkipped);
    expect(event.payload['reason'], '今天皮肤过敏');
    expect(event.subjectRefs.map((ref) => ref.type), <String>[
      'task',
      'profile',
    ]);

    await expectLater(
      useCase.skipTask(SkipTaskCommand(
        taskId: EntityId('T3'),
        expectedTaskRevision: 1,
        actor: user,
        correlationId: 'corr',
        reason: '',
      )),
      throwsA(isA<FeedbackUseCaseFailure>().having(
        (e) => e.code,
        'code',
        FeedbackFailureCode.skipReasonRequired,
      )),
    );
    expect(store.appendCalls, 1);
  });

  test('Agent review records strategy, execution, outcome and conclusion',
      () async {
    final agent = ActorRef(
      actorId: 'custom-harness',
      actorType: ActorType.agent,
      authoritySource: 'offline_bundle',
      sessionOrRunId: 'session-2',
      onBehalfOf: user.actorId,
    );
    final result = await useCase.createReview(
      CreateReviewCommand(
        actor: agent,
        profileId: EntityId('profile-1'),
        correlationId: 'review-v1',
        strategyRef: ObjectRef(
          type: 'strategy',
          id: EntityId('strategy-v1'),
          revision: Revision(3),
        ),
        reviewedBySession: EntityId('session-2'),
        summary: '执行一致，但恢复指标没有改善。',
        conclusion: StrategyReviewConclusion.ineffective,
        executionRefs: <ObjectRef>[
          ObjectRef(
            type: 'execution',
            id: EntityId('execution-1'),
            revision: Revision(1),
          ),
        ],
        outcomeRefs: <ObjectRef>[
          ObjectRef(
            type: 'outcome',
            id: EntityId('outcome-1'),
            revision: Revision(1),
          ),
        ],
        keep: const <String>['固定训练时间'],
        change: const <String>['降低训练量'],
        unknowns: const <String>['睡眠是否是混杂变量'],
      ),
    );

    expect(result.reviewId, startsWith('review-'));
    final event = store.batches.single.single;
    expect(event.actor.actorId, 'custom-harness');
    expect(event.payload['conclusion'], 'ineffective');
    expect(event.payload['summary'], '执行一致，但恢复指标没有改善。');
    expect(event.payload['reviewed_by_session'], 'session-2');
    expect(event.sourceRefs.map((ref) => ref.type),
        <String>['strategy', 'execution', 'outcome']);
    expect(event.subjectRefs.map((ref) => ref.type),
        <String>['review', 'profile']);
  });

  test('structured review rejects unpinned evidence', () async {
    await expectLater(
      useCase.createReview(
        CreateReviewCommand(
          actor: user,
          correlationId: 'review-invalid',
          strategyRef: ObjectRef(
            type: 'strategy',
            id: EntityId('strategy-v1'),
            revision: Revision(3),
          ),
          reviewedBySession: EntityId('session-2'),
          summary: 'Evidence is incomplete.',
          conclusion: StrategyReviewConclusion.inconclusive,
          executionRefs: <ObjectRef>[
            ObjectRef(type: 'execution', id: EntityId('execution-1')),
          ],
          outcomeRefs: <ObjectRef>[
            ObjectRef(
              type: 'outcome',
              id: EntityId('outcome-1'),
              revision: Revision(1),
            ),
          ],
        ),
      ),
      throwsA(
        isA<FeedbackUseCaseFailure>().having(
          (error) => error.code,
          'code',
          FeedbackFailureCode.reviewReferenceUnpinned,
        ),
      ),
    );
    expect(store.appendCalls, 0);
  });

  test('review creation then user decision preserves explicit transitions',
      () async {
    final created = await useCase.createReview(CreateReviewCommand(
      actor: user,
      correlationId: 'corr:review',
      profileId: EntityId('profile-1'),
      sourceRefs: <ObjectRef>[
        ObjectRef(type: 'outcome', id: EntityId('O1')),
      ],
    ));
    final decided = await useCase.decideReview(DecideReviewCommand(
      reviewId: EntityId(created.reviewId),
      expectedReviewRevision: 1,
      actor: user,
      correlationId: 'corr:review',
      decision: ReviewDecision.accept,
      profileId: EntityId('profile-1'),
    ));

    expect(store.appendCalls, 2);
    expect(store.batches.first.single.eventType, EventTypes.reviewCreated);
    expect(store.batches.last.map((e) => e.eventType), <String>[
      EventTypes.reviewUserReviewed,
      EventTypes.reviewAccepted,
    ]);
    expect(store.batches.last.last.causationId, decided.eventIds.first);
    expect(store.batches.last.first.payload['expected_revision'], 1);
    expect(store.batches.last.last.payload['expected_revision'], 2);
  });

  test('reject path is explicit and atomically follows user_reviewed',
      () async {
    await useCase.decideReview(DecideReviewCommand(
      reviewId: EntityId('R1'),
      expectedReviewRevision: 1,
      actor: user,
      correlationId: 'corr:reject',
      decision: ReviewDecision.reject,
      note: '证据不足',
    ));
    expect(store.appendCalls, 1);
    expect(store.batches.single.map((e) => e.eventType), <String>[
      EventTypes.reviewUserReviewed,
      EventTypes.reviewRejected,
    ]);
  });

  test('non-user cannot accept or reject a review and writes nothing',
      () async {
    final agent = ActorRef(
      actorId: 'agent:reviewer',
      actorType: ActorType.agent,
      authoritySource: 'delegation',
      onBehalfOf: 'user:self',
    );
    await expectLater(
      useCase.decideReview(DecideReviewCommand(
        reviewId: EntityId('R1'),
        expectedReviewRevision: 1,
        actor: agent,
        correlationId: 'corr',
        decision: ReviewDecision.accept,
      )),
      throwsA(isA<FeedbackUseCaseFailure>().having(
        (e) => e.code,
        'code',
        FeedbackFailureCode.reviewDecisionRequiresUser,
      )),
    );
    expect(store.appendCalls, 0);
  });

  group('D4 is rejected by the shared application guard before any write', () {
    Future<void> expectD4Rejected(Future<Object?> Function() invoke) async {
      await expectLater(
        invoke(),
        throwsA(isA<FeedbackUseCaseFailure>().having(
          (e) => e.code,
          'code',
          FeedbackFailureCode.d4Forbidden,
        )),
      );
      expect(store.appendCalls, 0);
      expect(ids.next, 0);
    }

    test('completeTask', () async {
      await expectD4Rejected(() => useCase.completeTask(CompleteTaskCommand(
            taskId: EntityId('T1'),
            expectedTaskRevision: 1,
            actor: user,
            correlationId: 'corr:d4',
            executionSummary: '不应落盘',
            sensitivity: Sensitivity.d4,
          )));
    });

    test('skipTask', () async {
      await expectD4Rejected(() => useCase.skipTask(SkipTaskCommand(
            taskId: EntityId('T1'),
            expectedTaskRevision: 1,
            actor: user,
            correlationId: 'corr:d4',
            reason: '不应落盘',
            sensitivity: Sensitivity.d4,
          )));
    });

    test('createReview', () async {
      await expectD4Rejected(() => useCase.createReview(CreateReviewCommand(
            actor: user,
            correlationId: 'corr:d4',
            sourceRefs: <ObjectRef>[
              ObjectRef(type: 'outcome', id: EntityId('O1')),
            ],
            sensitivity: Sensitivity.d4,
          )));
    });

    test('decideReview', () async {
      await expectD4Rejected(() => useCase.decideReview(DecideReviewCommand(
            reviewId: EntityId('R1'),
            expectedReviewRevision: 1,
            actor: user,
            correlationId: 'corr:d4',
            decision: ReviewDecision.accept,
            sensitivity: Sensitivity.d4,
          )));
    });
  });
}

final class _MemoryStore implements EventStore {
  final batches = <List<EventEnvelope>>[];
  int appendCalls = 0;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    appendCalls++;
    batches.add(List<EventEnvelope>.unmodifiable(events));
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject,
          {int? limit}) async =>
      const <EventEnvelope>[];
}

final class _Ids implements IdGenerator {
  int next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++next}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 8, 20, 16);
}
